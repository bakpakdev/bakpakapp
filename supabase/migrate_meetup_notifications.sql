-- Allow meetup peers to write in-app notifications for the other person.
-- Run after schema.sql / migrate_meetups.sql. Safe to re-run.

DROP POLICY IF EXISTS "notif_insert_own" ON public.notifications;
CREATE POLICY "notif_insert_own"
  ON public.notifications FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "notif_insert_meetup_peer" ON public.notifications;
CREATE POLICY "notif_insert_meetup_peer"
  ON public.notifications FOR INSERT
  TO authenticated
  WITH CHECK (
    type = 'meetup'
    AND user_id <> auth.uid()
    AND COALESCE(data->>'meetup_id', '') <> ''
    AND EXISTS (
      SELECT 1
      FROM public.meetups m
      WHERE m.id::text = data->>'meetup_id'
        AND (m.proposer_id = auth.uid() OR m.recipient_id = auth.uid())
        AND (m.proposer_id = user_id OR m.recipient_id = user_id)
    )
  );

CREATE INDEX IF NOT EXISTS notifications_user_created_idx
  ON public.notifications (user_id, created_at DESC);

GRANT SELECT, INSERT, UPDATE ON TABLE public.notifications TO authenticated;
