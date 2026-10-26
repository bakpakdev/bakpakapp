-- Push notifications (APNs). Safe to re-run.
--
-- 1. Devices register their APNs token in push_devices (one row per token).
-- 2. Triggers on messages, meetups and follows POST the event to the popup API,
--    which decides who to alert and sends through Apple. Sales are sent by the API
--    itself when a payment is confirmed.
-- 3. Each user's on/off choices live in profiles.notification_prefs
--    (keys: messages, offers, meetups, sales, follows; missing = on).
--
-- After running this, set the API endpoint and shared secret ONCE (same secret as
-- PUSH_WEBHOOK_SECRET on Render):
--   insert into private.push_config (id, endpoint, secret)
--   values (1, 'https://popup-api-hwbg.onrender.com/api/push/event', '<long random secret>')
--   on conflict (id) do update set endpoint = excluded.endpoint, secret = excluded.secret;

CREATE EXTENSION IF NOT EXISTS pg_net;

-- Devices --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.push_devices (
  token        TEXT PRIMARY KEY,
  user_id      UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  environment  TEXT NOT NULL DEFAULT 'production' CHECK (environment IN ('sandbox', 'production')),
  platform     TEXT NOT NULL DEFAULT 'ios',
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS push_devices_user_id_idx ON public.push_devices (user_id);

ALTER TABLE public.push_devices ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "push_devices_select_own" ON public.push_devices;
CREATE POLICY "push_devices_select_own" ON public.push_devices
  FOR SELECT TO authenticated USING (user_id = auth.uid());

DROP POLICY IF EXISTS "push_devices_insert_own" ON public.push_devices;
CREATE POLICY "push_devices_insert_own" ON public.push_devices
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

-- A token moves to whoever signed in last on that phone.
DROP POLICY IF EXISTS "push_devices_update_own" ON public.push_devices;
CREATE POLICY "push_devices_update_own" ON public.push_devices
  FOR UPDATE TO authenticated USING (true) WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "push_devices_delete_own" ON public.push_devices;
CREATE POLICY "push_devices_delete_own" ON public.push_devices
  FOR DELETE TO authenticated USING (user_id = auth.uid());

-- Preferences ------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS notification_prefs JSONB NOT NULL DEFAULT '{}'::jsonb;

-- Webhook config (not exposed to the API) --------------------------------------
CREATE SCHEMA IF NOT EXISTS private;
CREATE TABLE IF NOT EXISTS private.push_config (
  id        INT PRIMARY KEY CHECK (id = 1),
  endpoint  TEXT NOT NULL,
  secret    TEXT NOT NULL
);
REVOKE ALL ON private.push_config FROM anon, authenticated;

CREATE OR REPLACE FUNCTION private.send_push_event(event_type TEXT, record JSONB, old_record JSONB DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, extensions
AS $$
DECLARE
  cfg private.push_config%ROWTYPE;
BEGIN
  SELECT * INTO cfg FROM private.push_config WHERE id = 1;
  IF NOT FOUND THEN
    RETURN; -- not configured yet: never block the insert
  END IF;
  PERFORM net.http_post(
    url := cfg.endpoint,
    body := jsonb_build_object('type', event_type, 'record', record, 'old_record', old_record, 'actor_id', auth.uid()),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-push-secret', cfg.secret)
  );
EXCEPTION WHEN OTHERS THEN
  RETURN; -- a push problem must never fail the user's write
END;
$$;

-- Triggers ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.push_on_message() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
BEGIN
  PERFORM private.send_push_event('message', to_jsonb(NEW));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS push_on_message ON public.messages;
CREATE TRIGGER push_on_message AFTER INSERT ON public.messages
  FOR EACH ROW EXECUTE FUNCTION private.push_on_message();

CREATE OR REPLACE FUNCTION private.push_on_meetup() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM private.send_push_event('meetup', to_jsonb(NEW), NULL);
  ELSIF NEW.status IS DISTINCT FROM OLD.status OR NEW.scheduled_at IS DISTINCT FROM OLD.scheduled_at THEN
    PERFORM private.send_push_event('meetup', to_jsonb(NEW), to_jsonb(OLD));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS push_on_meetup ON public.meetups;
CREATE TRIGGER push_on_meetup AFTER INSERT OR UPDATE ON public.meetups
  FOR EACH ROW EXECUTE FUNCTION private.push_on_meetup();

CREATE OR REPLACE FUNCTION private.push_on_follow() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, private AS $$
BEGIN
  PERFORM private.send_push_event('follow', to_jsonb(NEW));
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS push_on_follow ON public.follows;
CREATE TRIGGER push_on_follow AFTER INSERT ON public.follows
  FOR EACH ROW EXECUTE FUNCTION private.push_on_follow();
