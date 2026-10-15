-- In-person Pay/Receive sessions: seller opens Receive, buyer can Apple Pay only while waiting.
-- Safe to re-run. Does not enable Tap to Pay.

CREATE TABLE IF NOT EXISTS public.payment_sessions (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id          UUID NOT NULL REFERENCES public.products (id) ON DELETE CASCADE,
  meetup_id           UUID REFERENCES public.meetups (id) ON DELETE SET NULL,
  payment_request_id  UUID NOT NULL REFERENCES public.payment_requests (id) ON DELETE CASCADE,
  seller_id           UUID NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
  buyer_id            UUID REFERENCES public.profiles (id) ON DELETE SET NULL,
  amount_cents        INTEGER NOT NULL CHECK (amount_cents > 0),
  product_title       TEXT NOT NULL DEFAULT '',
  status              TEXT NOT NULL DEFAULT 'waiting'
                      CHECK (status IN ('waiting', 'paid', 'cancelled', 'expired')),
  expires_at          TIMESTAMPTZ NOT NULL,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS payment_sessions_product_id_idx
  ON public.payment_sessions (product_id);

CREATE INDEX IF NOT EXISTS payment_sessions_seller_id_idx
  ON public.payment_sessions (seller_id);

CREATE INDEX IF NOT EXISTS payment_sessions_buyer_id_idx
  ON public.payment_sessions (buyer_id);

CREATE INDEX IF NOT EXISTS payment_sessions_status_expires_idx
  ON public.payment_sessions (status, expires_at DESC);

-- One open waiting session per product at a time.
CREATE UNIQUE INDEX IF NOT EXISTS payment_sessions_open_product_uidx
  ON public.payment_sessions (product_id)
  WHERE status = 'waiting';

DROP TRIGGER IF EXISTS payment_sessions_updated_at ON public.payment_sessions;
CREATE TRIGGER payment_sessions_updated_at
  BEFORE UPDATE ON public.payment_sessions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.payment_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "payment_sessions_select_participants" ON public.payment_sessions;
CREATE POLICY "payment_sessions_select_participants"
  ON public.payment_sessions FOR SELECT
  TO authenticated
  USING (seller_id = auth.uid() OR buyer_id = auth.uid());

-- Mutations go through the service-role API; no client inserts/updates.
DROP POLICY IF EXISTS "payment_sessions_no_client_write" ON public.payment_sessions;
-- Intentionally no INSERT/UPDATE/DELETE policies for authenticated.

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.payment_sessions;
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

GRANT SELECT ON TABLE public.payment_sessions TO authenticated;
GRANT ALL ON TABLE public.payment_sessions TO service_role;
