-- Meetup / in-person Square payments
-- Run in Supabase SQL Editor after schema.sql

CREATE TABLE IF NOT EXISTS public.payment_requests (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id        UUID NOT NULL REFERENCES public.products (id) ON DELETE CASCADE,
  seller_id         UUID NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
  buyer_id          UUID REFERENCES public.profiles (id) ON DELETE SET NULL,
  payment_intent_id TEXT NOT NULL,
  amount_cents      INTEGER NOT NULL CHECK (amount_cents > 0),
  status            TEXT NOT NULL DEFAULT 'awaiting_payment'
                    CHECK (status IN ('awaiting_payment', 'paid', 'cancelled', 'expired')),
  expires_at        TIMESTAMPTZ NOT NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS payment_requests_product_id_idx
  ON public.payment_requests (product_id);

CREATE INDEX IF NOT EXISTS payment_requests_seller_id_idx
  ON public.payment_requests (seller_id);

CREATE INDEX IF NOT EXISTS payment_requests_status_expires_idx
  ON public.payment_requests (status, expires_at DESC);

CREATE UNIQUE INDEX IF NOT EXISTS payment_requests_open_product_uidx
  ON public.payment_requests (product_id)
  WHERE status = 'awaiting_payment';

DROP TRIGGER IF EXISTS payment_requests_updated_at ON public.payment_requests;
CREATE TRIGGER payment_requests_updated_at
  BEFORE UPDATE ON public.payment_requests
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.payment_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "payment_requests_select_authenticated" ON public.payment_requests;
CREATE POLICY "payment_requests_select_authenticated"
  ON public.payment_requests FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "payment_requests_insert_seller" ON public.payment_requests;
CREATE POLICY "payment_requests_insert_seller"
  ON public.payment_requests FOR INSERT
  TO authenticated
  WITH CHECK (seller_id = auth.uid());

DROP POLICY IF EXISTS "payment_requests_update_participants" ON public.payment_requests;
CREATE POLICY "payment_requests_update_participants"
  ON public.payment_requests FOR UPDATE
  TO authenticated
  USING (seller_id = auth.uid() OR buyer_id = auth.uid())
  WITH CHECK (seller_id = auth.uid() OR buyer_id = auth.uid());
