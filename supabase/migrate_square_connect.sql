-- Square Tap to Pay (in-person Collect payment)
-- Run in Supabase SQL Editor after migrate_payment_requests.sql
-- Tokens are service-role only. Do not add authenticated RLS policies.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS square_merchant_id TEXT;

CREATE TABLE IF NOT EXISTS public.square_connections (
  user_id        UUID PRIMARY KEY REFERENCES public.profiles (id) ON DELETE CASCADE,
  merchant_id    TEXT NOT NULL,
  location_id    TEXT NOT NULL,
  access_token   TEXT NOT NULL,
  refresh_token  TEXT NOT NULL,
  expires_at     TIMESTAMPTZ NOT NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS square_connections_updated_at ON public.square_connections;
CREATE TRIGGER square_connections_updated_at
  BEFORE UPDATE ON public.square_connections
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.square_connections ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.payment_requests
  ADD COLUMN IF NOT EXISTS provider TEXT NOT NULL DEFAULT 'stripe';

ALTER TABLE public.payment_requests
  ADD COLUMN IF NOT EXISTS square_payment_id TEXT;

ALTER TABLE public.payment_requests
  ALTER COLUMN payment_intent_id DROP NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'payment_requests_provider_check'
  ) THEN
    ALTER TABLE public.payment_requests
      ADD CONSTRAINT payment_requests_provider_check
      CHECK (provider IN ('stripe', 'square'));
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS payment_requests_square_payment_id_uidx
  ON public.payment_requests (square_payment_id)
  WHERE square_payment_id IS NOT NULL;
