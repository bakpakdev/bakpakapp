-- Usernames (the @name people see on popup) must be unique, ignoring case.
-- The table already had UNIQUE (username), but that is case-sensitive, so
-- "Hadi" and "hadi" could both exist. This migration:
--   1. renames any existing case-insensitive duplicates (the oldest account keeps
--      the name, later ones get a short suffix like "hadi_3f9a2c"),
--   2. adds a unique index on lower(username) so the database refuses a taken name,
--   3. updates the signup trigger to avoid case-insensitive collisions,
--   4. adds username_available() so the app can check a name while you type.
-- Safe to run more than once. Run in the Supabase SQL Editor.

BEGIN;

-- 1. Rename existing duplicates (keep the oldest account's name as-is).
WITH ranked AS (
  SELECT id,
         username,
         row_number() OVER (PARTITION BY lower(username) ORDER BY created_at, id) AS rn
  FROM public.profiles
)
UPDATE public.profiles p
SET username = left(r.username, 40) || '_' || substr(md5(p.id::text || random()::text), 1, 6),
    updated_at = now()
FROM ranked r
WHERE p.id = r.id
  AND r.rn > 1;

-- 2. Case-insensitive uniqueness, enforced by the database.
CREATE UNIQUE INDEX IF NOT EXISTS profiles_username_lower_key
  ON public.profiles (lower(username));

-- 3. Signup trigger: check collisions ignoring case.
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  base_name TEXT;
  final_name TEXT;
BEGIN
  base_name := COALESCE(
    NULLIF(trim(NEW.raw_user_meta_data->>'username'), ''),
    regexp_replace(split_part(NEW.email, '@', 1), '[^a-zA-Z0-9_]', '_', 'g')
  );
  IF base_name IS NULL OR base_name = '' THEN
    base_name := 'user_' || replace(substr(NEW.id::text, 1, 13), '-', '');
  END IF;
  final_name := base_name;
  WHILE EXISTS (SELECT 1 FROM public.profiles WHERE lower(username) = lower(final_name)) LOOP
    final_name := base_name || '_' || substr(md5(random()::text), 1, 6);
  END LOOP;

  INSERT INTO public.profiles (id, username, email)
  VALUES (NEW.id, final_name, NEW.email);
  RETURN NEW;
END;
$$;

-- 4. Availability check for the app. Your own current name counts as available.
CREATE OR REPLACE FUNCTION public.username_available(p_username TEXT)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT NOT EXISTS (
    SELECT 1
    FROM public.profiles
    WHERE lower(username) = lower(btrim(replace(p_username, '@', '')))
      AND id IS DISTINCT FROM auth.uid()
  );
$$;

REVOKE ALL ON FUNCTION public.username_available(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.username_available(TEXT) TO authenticated;

COMMIT;
