-- Follows + purchase-verified seller reviews
-- Run in Supabase SQL Editor after schema.sql / policies.sql

-- ---------------------------------------------------------------------------
-- Reviews: one review per purchased item (was one per seller)
-- ---------------------------------------------------------------------------
ALTER TABLE public.reviews DROP CONSTRAINT IF EXISTS reviews_reviewer_id_reviewed_id_key;

CREATE UNIQUE INDEX IF NOT EXISTS reviews_reviewer_product_uidx
  ON public.reviews (reviewer_id, product_id);

CREATE INDEX IF NOT EXISTS reviews_reviewed_id_idx
  ON public.reviews (reviewed_id, created_at DESC);

ALTER TABLE public.reviews
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

DROP TRIGGER IF EXISTS reviews_updated_at ON public.reviews;
CREATE TRIGGER reviews_updated_at
  BEFORE UPDATE ON public.reviews
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- True when the signed-in user bought this exact sold item from this seller.
-- Orders are only written by the backend (service role), so they can't be forged.
CREATE OR REPLACE FUNCTION public.can_review_purchase(p_product_id uuid, p_seller_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.order_items oi
    JOIN public.orders o ON o.id = oi.order_id
    JOIN public.products p ON p.id = oi.product_id
    WHERE oi.product_id = p_product_id
      AND o.buyer_id = auth.uid()
      AND o.seller_id = p_seller_id
      AND p.user_id = p_seller_id
      AND p.is_sold = true
      AND o.status <> 'cancelled'
  );
$$;

REVOKE ALL ON FUNCTION public.can_review_purchase(uuid, uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.can_review_purchase(uuid, uuid) TO authenticated;

DROP POLICY IF EXISTS "reviews_read" ON public.reviews;
CREATE POLICY "reviews_read"
  ON public.reviews FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "reviews_insert" ON public.reviews;
CREATE POLICY "reviews_insert"
  ON public.reviews FOR INSERT TO authenticated
  WITH CHECK (
    reviewer_id = auth.uid()
    AND reviewed_id <> auth.uid()
    AND product_id IS NOT NULL
    AND public.can_review_purchase(product_id, reviewed_id)
  );

DROP POLICY IF EXISTS "reviews_update_own" ON public.reviews;
CREATE POLICY "reviews_update_own"
  ON public.reviews FOR UPDATE TO authenticated
  USING (reviewer_id = auth.uid())
  WITH CHECK (
    reviewer_id = auth.uid()
    AND product_id IS NOT NULL
    AND public.can_review_purchase(product_id, reviewed_id)
  );

DROP POLICY IF EXISTS "reviews_delete_own" ON public.reviews;
CREATE POLICY "reviews_delete_own"
  ON public.reviews FOR DELETE TO authenticated
  USING (reviewer_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Orders: only the backend (service role) creates or edits orders, so a
-- buyer can't fabricate a purchase to unlock a review.
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "orders_insert_buyer" ON public.orders;
DROP POLICY IF EXISTS "orders_update_party" ON public.orders;
DROP POLICY IF EXISTS "order_items_insert" ON public.order_items;

-- ---------------------------------------------------------------------------
-- Follows: anyone signed in can see follows; you can only add/remove your own.
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS follows_following_id_idx ON public.follows (following_id);
CREATE INDEX IF NOT EXISTS follows_follower_id_idx ON public.follows (follower_id);

DROP POLICY IF EXISTS "follows_select" ON public.follows;
CREATE POLICY "follows_select"
  ON public.follows FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "follows_insert" ON public.follows;
CREATE POLICY "follows_insert"
  ON public.follows FOR INSERT TO authenticated
  WITH CHECK (follower_id = auth.uid() AND following_id <> auth.uid());

DROP POLICY IF EXISTS "follows_delete" ON public.follows;
CREATE POLICY "follows_delete"
  ON public.follows FOR DELETE TO authenticated USING (follower_id = auth.uid());
