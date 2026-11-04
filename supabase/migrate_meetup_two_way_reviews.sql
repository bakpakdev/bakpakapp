-- Two-way reviews after a meetup sale: the buyer can review the seller and the
-- seller can review the buyer, once per sold item each.
-- Run in Supabase SQL Editor after migrate_follows_reviews.sql. Safe to run again.

-- True when the signed-in user and p_other_id were the buyer and seller (either
-- way round) of a completed order for this sold item. Orders are only written by
-- the backend (service role), so a review can't be unlocked by a fake purchase.
CREATE OR REPLACE FUNCTION public.can_review_sale(p_product_id uuid, p_other_id uuid)
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
      AND p.is_sold = true
      AND o.status <> 'cancelled'
      AND p.user_id = o.seller_id
      AND (
        (o.buyer_id = auth.uid() AND o.seller_id = p_other_id)
        OR (o.seller_id = auth.uid() AND o.buyer_id = p_other_id)
      )
  );
$$;

REVOKE ALL ON FUNCTION public.can_review_sale(uuid, uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.can_review_sale(uuid, uuid) TO authenticated;

DROP POLICY IF EXISTS "reviews_insert" ON public.reviews;
CREATE POLICY "reviews_insert"
  ON public.reviews FOR INSERT TO authenticated
  WITH CHECK (
    reviewer_id = auth.uid()
    AND reviewed_id <> auth.uid()
    AND product_id IS NOT NULL
    AND public.can_review_sale(product_id, reviewed_id)
  );

DROP POLICY IF EXISTS "reviews_update_own" ON public.reviews;
CREATE POLICY "reviews_update_own"
  ON public.reviews FOR UPDATE TO authenticated
  USING (reviewer_id = auth.uid())
  WITH CHECK (
    reviewer_id = auth.uid()
    AND reviewed_id <> auth.uid()
    AND product_id IS NOT NULL
    AND public.can_review_sale(product_id, reviewed_id)
  );
