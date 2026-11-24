-- Username changes are a big deal: once you change your @, you can't change it
-- again for 14 days. This migration:
--   1. adds profiles.username_changed_at (NULL = never changed),
--   2. adds change_username(), which the app's "new username" screen calls.
--      It checks the name, enforces the 14-day lock and stamps the time,
--   3. adds username_change_status() so the app can show "locked until Dec 6",
--   4. adds a trigger so nobody can skip the lock by updating profiles directly,
--      and so username_changed_at can't be edited by the app.
-- Picking your @ during sign-up (onboarding) is free and doesn't start the lock,
-- as long as it happens within a day of creating the account.
-- Changes made from the SQL Editor (no signed-in user) are never blocked.
-- Safe to run more than once. Run in the Supabase SQL Editor.

BEGIN;

-- 1. When the username last changed.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS username_changed_at TIMESTAMPTZ;

-- 2. Guard on every profiles update.
CREATE OR REPLACE FUNCTION public.guard_username_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  unlocks_at TIMESTAMPTZ;
BEGIN
  -- The app can never write this column itself.
  NEW.username_changed_at := OLD.username_changed_at;

  IF NEW.username IS NOT DISTINCT FROM OLD.username THEN
    RETURN NEW;
  END IF;

  -- SQL Editor / service role: no lock, no stamp.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  unlocks_at := OLD.username_changed_at + interval '14 days';
  IF unlocks_at IS NOT NULL AND unlocks_at > now() THEN
    RAISE EXCEPTION 'username_locked until %', to_char(unlocks_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
      USING ERRCODE = 'P0001';
  END IF;

  -- change_username() always starts the lock. A direct update (onboarding) is
  -- free while the account is under a day old and has never changed its name.
  IF current_setting('popup.username_change', true) = 'on'
     OR OLD.username_changed_at IS NOT NULL
     OR OLD.created_at < now() - interval '1 day' THEN
    NEW.username_changed_at := now();
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_guard_username_change ON public.profiles;
CREATE TRIGGER profiles_guard_username_change
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.guard_username_change();

-- 3. Status for the signed-in user.
CREATE OR REPLACE FUNCTION public.username_change_status()
RETURNS JSON
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT json_build_object(
    'username', p.username,
    'changed_at', p.username_changed_at,
    'unlocks_at', p.username_changed_at + interval '14 days',
    'locked', COALESCE(p.username_changed_at + interval '14 days' > now(), false)
  )
  FROM public.profiles p
  WHERE p.id = auth.uid();
$$;

REVOKE ALL ON FUNCTION public.username_change_status() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.username_change_status() TO authenticated;

-- 4. The change itself.
CREATE OR REPLACE FUNCTION public.change_username(p_username TEXT)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  me UUID := auth.uid();
  new_name TEXT := btrim(replace(COALESCE(p_username, ''), '@', ''));
  cur public.profiles%ROWTYPE;
BEGIN
  IF me IS NULL THEN
    RAISE EXCEPTION 'not_signed_in' USING ERRCODE = 'P0001';
  END IF;

  SELECT * INTO cur FROM public.profiles WHERE id = me FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'profile_not_found' USING ERRCODE = 'P0001';
  END IF;

  IF length(new_name) < 3 THEN
    RAISE EXCEPTION 'username_too_short' USING ERRCODE = 'P0001';
  END IF;
  IF new_name ~ '\s' THEN
    RAISE EXCEPTION 'username_has_spaces' USING ERRCODE = 'P0001';
  END IF;
  IF new_name = cur.username THEN
    RAISE EXCEPTION 'username_unchanged' USING ERRCODE = 'P0001';
  END IF;
  IF EXISTS (SELECT 1 FROM public.profiles WHERE lower(username) = lower(new_name) AND id <> me) THEN
    RAISE EXCEPTION 'username_taken' USING ERRCODE = 'P0001';
  END IF;

  PERFORM set_config('popup.username_change', 'on', true);
  UPDATE public.profiles
    SET username = new_name, updated_at = now()
    WHERE id = me
    RETURNING * INTO cur;
  PERFORM set_config('popup.username_change', 'off', true);

  RETURN json_build_object(
    'username', cur.username,
    'changed_at', cur.username_changed_at,
    'unlocks_at', cur.username_changed_at + interval '14 days',
    'locked', true
  );
END;
$$;

REVOKE ALL ON FUNCTION public.change_username(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.change_username(TEXT) TO authenticated;

COMMIT;
