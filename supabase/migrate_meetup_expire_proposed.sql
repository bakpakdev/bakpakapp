-- Expire unanswered meetup proposals once the scheduled meetup time passes.
-- Safe to re-run. Clients also call this logic via direct UPDATE; this RPC is optional.

CREATE OR REPLACE FUNCTION public.expire_stale_meetup_proposals()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  updated_count INTEGER;
BEGIN
  UPDATE public.meetups
  SET status = 'expired',
      updated_at = now()
  WHERE status = 'proposed'
    AND expires_at <= now()
    AND (proposer_id = auth.uid() OR recipient_id = auth.uid());

  GET DIAGNOSTICS updated_count = ROW_COUNT;
  RETURN updated_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.expire_stale_meetup_proposals() TO authenticated;
