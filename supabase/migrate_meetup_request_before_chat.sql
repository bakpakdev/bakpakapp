-- Listing-first meetup requests: conversation is created only after the seller accepts.
-- Safe to re-run.

ALTER TABLE public.meetups
  ALTER COLUMN conversation_id DROP NOT NULL;

-- Prefer SET NULL if the conversation is removed after a listing-first request.
ALTER TABLE public.meetups DROP CONSTRAINT IF EXISTS meetups_conversation_id_fkey;
ALTER TABLE public.meetups
  ADD CONSTRAINT meetups_conversation_id_fkey
  FOREIGN KEY (conversation_id) REFERENCES public.conversations (id) ON DELETE SET NULL;

DROP INDEX IF EXISTS meetups_one_open_per_conversation_uidx;
CREATE UNIQUE INDEX IF NOT EXISTS meetups_one_open_per_conversation_uidx
  ON public.meetups (conversation_id)
  WHERE status IN ('proposed', 'confirmed') AND conversation_id IS NOT NULL;

-- One pending request per buyer+listing while waiting on the seller.
CREATE UNIQUE INDEX IF NOT EXISTS meetups_one_proposed_per_product_proposer_uidx
  ON public.meetups (product_id, proposer_id)
  WHERE status = 'proposed' AND product_id IS NOT NULL;
