-- Platform-held seller balances (separate charges + later transfers).
-- Sales credit available_cents; cashout debits the popup wallet held on Square.

CREATE TABLE IF NOT EXISTS public.seller_balances (
  seller_id              UUID PRIMARY KEY REFERENCES public.profiles (id) ON DELETE CASCADE,
  available_cents        INTEGER NOT NULL DEFAULT 0 CHECK (available_cents >= 0),
  pending_cents          INTEGER NOT NULL DEFAULT 0 CHECK (pending_cents >= 0),
  lifetime_earned_cents  INTEGER NOT NULL DEFAULT 0 CHECK (lifetime_earned_cents >= 0),
  lifetime_paid_out_cents INTEGER NOT NULL DEFAULT 0 CHECK (lifetime_paid_out_cents >= 0),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.seller_payouts (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  seller_id          UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  amount_cents       INTEGER NOT NULL CHECK (amount_cents > 0),
  stripe_transfer_id TEXT,
  status             TEXT NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'paid', 'failed')),
  failure_reason     TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS seller_payouts_seller_id_idx
  ON public.seller_payouts (seller_id, created_at DESC);

DROP TRIGGER IF EXISTS seller_payouts_updated_at ON public.seller_payouts;
CREATE TRIGGER seller_payouts_updated_at
  BEFORE UPDATE ON public.seller_payouts
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.seller_balances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seller_payouts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "seller_balances_select_own" ON public.seller_balances;
CREATE POLICY "seller_balances_select_own"
  ON public.seller_balances FOR SELECT
  TO authenticated
  USING (seller_id = auth.uid());

DROP POLICY IF EXISTS "seller_payouts_select_own" ON public.seller_payouts;
CREATE POLICY "seller_payouts_select_own"
  ON public.seller_payouts FOR SELECT
  TO authenticated
  USING (seller_id = auth.uid());

-- Writes go through the backend service role (bypasses RLS).
