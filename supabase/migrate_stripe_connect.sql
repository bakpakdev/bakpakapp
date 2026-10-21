-- Stripe Connect Express support for buyer checkout and seller payouts.
-- Run in Supabase SQL Editor after migrate_payment_requests.sql, migrate_square_connect.sql,
-- migrate_seller_balances.sql and migrate_payment_sessions.sql. Safe to re-run.
--
-- Money flow: buyers pay popup's Stripe account (PaymentIntent), the sale credits
-- seller_balances, and cash out sends a Stripe Transfer to the seller's Express
-- account (profiles.stripe_account_id), recorded in seller_payouts.stripe_transfer_id.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS stripe_account_id TEXT;

CREATE INDEX IF NOT EXISTS profiles_stripe_account_id_idx
  ON public.profiles (stripe_account_id);

-- payment_requests.payment_intent_id holds the Stripe PaymentIntent (pi_...) once
-- the buyer opens checkout, or a stripe:pending:<uuid> placeholder before that.
CREATE INDEX IF NOT EXISTS payment_requests_payment_intent_id_idx
  ON public.payment_requests (payment_intent_id);

ALTER TABLE public.payment_requests
  ALTER COLUMN provider SET DEFAULT 'stripe';

-- All payment_requests writes go through the backend service role. The old client
-- insert/update policies let a buyer or seller flip status (e.g. to 'paid') directly.
DROP POLICY IF EXISTS "payment_requests_insert_seller" ON public.payment_requests;
DROP POLICY IF EXISTS "payment_requests_update_participants" ON public.payment_requests;

CREATE INDEX IF NOT EXISTS seller_payouts_stripe_transfer_id_idx
  ON public.seller_payouts (stripe_transfer_id);

-- popup's service fee (backend/lib/platformFee.js): the buyer pays it on top of the
-- listing price and popup keeps it; the seller gets the full price (amount_cents).
-- popup's revenue: SUM(platform_fee_cents) WHERE status = 'paid'.
ALTER TABLE public.payment_requests
  ADD COLUMN IF NOT EXISTS platform_fee_cents INTEGER CHECK (platform_fee_cents >= 0),
  ADD COLUMN IF NOT EXISTS total_cents INTEGER CHECK (total_cents >= 0);

ALTER TABLE public.payment_sessions
  ADD COLUMN IF NOT EXISTS service_fee_cents INTEGER CHECK (service_fee_cents >= 0),
  ADD COLUMN IF NOT EXISTS total_cents INTEGER CHECK (total_cents >= 0);
