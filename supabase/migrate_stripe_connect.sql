-- Stripe Connect Express support for seller payouts
-- Run in Supabase SQL Editor after schema.sql / policies.sql

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS stripe_account_id TEXT;

CREATE INDEX IF NOT EXISTS profiles_stripe_account_id_idx
  ON public.profiles (stripe_account_id);
