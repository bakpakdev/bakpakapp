-- Seller cash-out profile collected in-app before / during Square Connect.
-- Sensitive bank + full tax IDs stay on Square; we only store prep checklist flags.

CREATE TABLE IF NOT EXISTS public.seller_payout_profiles (
  user_id              UUID PRIMARY KEY REFERENCES public.profiles (id) ON DELETE CASCADE,
  legal_first_name     TEXT,
  legal_last_name      TEXT,
  email                TEXT,
  phone                TEXT,
  entity_type          TEXT NOT NULL DEFAULT 'individual'
                       CHECK (entity_type IN ('individual', 'business')),
  business_name        TEXT,
  address_line1        TEXT,
  address_line2        TEXT,
  city                 TEXT,
  state                TEXT,
  postal_code          TEXT,
  country              TEXT NOT NULL DEFAULT 'US',
  has_id_ready         BOOLEAN NOT NULL DEFAULT false,
  has_bank_ready       BOOLEAN NOT NULL DEFAULT false,
  current_step         TEXT NOT NULL DEFAULT 'overview',
  overview_done        BOOLEAN NOT NULL DEFAULT false,
  personal_done        BOOLEAN NOT NULL DEFAULT false,
  address_done         BOOLEAN NOT NULL DEFAULT false,
  entity_done          BOOLEAN NOT NULL DEFAULT false,
  checklist_done       BOOLEAN NOT NULL DEFAULT false,
  square_connect_done  BOOLEAN NOT NULL DEFAULT false,
  bank_link_done       BOOLEAN NOT NULL DEFAULT false,
  completed_at         TIMESTAMPTZ,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS seller_payout_profiles_updated_at ON public.seller_payout_profiles;
CREATE TRIGGER seller_payout_profiles_updated_at
  BEFORE UPDATE ON public.seller_payout_profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.seller_payout_profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS seller_payout_profiles_select_own ON public.seller_payout_profiles;
CREATE POLICY seller_payout_profiles_select_own
  ON public.seller_payout_profiles FOR SELECT
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS seller_payout_profiles_upsert_own ON public.seller_payout_profiles;
CREATE POLICY seller_payout_profiles_insert_own
  ON public.seller_payout_profiles FOR INSERT
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS seller_payout_profiles_update_own ON public.seller_payout_profiles;
CREATE POLICY seller_payout_profiles_update_own
  ON public.seller_payout_profiles FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
