-- Meetup scheduling (server source of truth)
-- Run in Supabase SQL Editor after schema.sql
-- Safe to re-run.

CREATE TABLE IF NOT EXISTS public.meetups (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id          UUID NOT NULL REFERENCES public.conversations (id) ON DELETE CASCADE,
  product_id               UUID REFERENCES public.products (id) ON DELETE SET NULL,
  proposer_id              UUID NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
  recipient_id             UUID NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
  seller_id                UUID REFERENCES public.profiles (id) ON DELETE SET NULL,
  spot_id                  TEXT NOT NULL,
  spot_name                TEXT NOT NULL,
  school                   TEXT,
  scheduled_at             TIMESTAMPTZ NOT NULL,
  status                   TEXT NOT NULL DEFAULT 'proposed'
                           CHECK (status IN (
                             'proposed',
                             'confirmed',
                             'declined',
                             'cancelled',
                             'completed',
                             'expired',
                             'no_show'
                           )),
  cancel_reason            TEXT,
  proposer_checked_in_at   TIMESTAMPTZ,
  recipient_checked_in_at  TIMESTAMPTZ,
  eta_minutes              INTEGER,
  eta_set_by               UUID REFERENCES public.profiles (id) ON DELETE SET NULL,
  expires_at               TIMESTAMPTZ NOT NULL,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Invites expire at the meeting time unless the client sends a different expires_at.
CREATE OR REPLACE FUNCTION public.meetups_set_expires_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.expires_at IS NULL THEN
    NEW.expires_at := NEW.scheduled_at;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS meetups_set_expires_at ON public.meetups;
CREATE TRIGGER meetups_set_expires_at
  BEFORE INSERT OR UPDATE ON public.meetups
  FOR EACH ROW EXECUTE FUNCTION public.meetups_set_expires_at();

CREATE INDEX IF NOT EXISTS meetups_proposer_scheduled_idx
  ON public.meetups (proposer_id, scheduled_at);

CREATE INDEX IF NOT EXISTS meetups_recipient_scheduled_idx
  ON public.meetups (recipient_id, scheduled_at);

CREATE INDEX IF NOT EXISTS meetups_conversation_id_idx
  ON public.meetups (conversation_id);

CREATE UNIQUE INDEX IF NOT EXISTS meetups_one_open_per_conversation_uidx
  ON public.meetups (conversation_id)
  WHERE status IN ('proposed', 'confirmed');

DROP TRIGGER IF EXISTS meetups_updated_at ON public.meetups;
CREATE TRIGGER meetups_updated_at
  BEFORE UPDATE ON public.meetups
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.meetups ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "meetups_select_participants" ON public.meetups;
CREATE POLICY "meetups_select_participants"
  ON public.meetups FOR SELECT
  TO authenticated
  USING (proposer_id = auth.uid() OR recipient_id = auth.uid());

DROP POLICY IF EXISTS "meetups_insert_proposer" ON public.meetups;
CREATE POLICY "meetups_insert_proposer"
  ON public.meetups FOR INSERT
  TO authenticated
  WITH CHECK (proposer_id = auth.uid());

DROP POLICY IF EXISTS "meetups_update_participants" ON public.meetups;
CREATE POLICY "meetups_update_participants"
  ON public.meetups FOR UPDATE
  TO authenticated
  USING (proposer_id = auth.uid() OR recipient_id = auth.uid())
  WITH CHECK (proposer_id = auth.uid() OR recipient_id = auth.uid());

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.meetups;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

GRANT SELECT, INSERT, UPDATE ON TABLE public.meetups TO authenticated;
GRANT ALL ON TABLE public.meetups TO service_role;
