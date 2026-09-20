-- =============================================================================
-- Row Level Security — run AFTER schema.sql + storage.sql
-- Uses auth.uid() (UUID) = public.profiles.id
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Storage: public read; authenticated upload only under folder = their user id
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Public read product images" ON storage.objects;
CREATE POLICY "Public read product images"
  ON storage.objects FOR SELECT
  TO public
  USING (bucket_id = 'product-images');

DROP POLICY IF EXISTS "Users upload own folder" ON storage.objects;
CREATE POLICY "Users upload own folder"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'product-images'
    AND lower((storage.foldername(name))[1]) = auth.uid()::text
  );

DROP POLICY IF EXISTS "Users update own folder" ON storage.objects;
CREATE POLICY "Users update own folder"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (
    bucket_id = 'product-images'
    AND lower((storage.foldername(name))[1]) = auth.uid()::text
  );

DROP POLICY IF EXISTS "Users delete own folder" ON storage.objects;
CREATE POLICY "Users delete own folder"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'product-images'
    AND lower((storage.foldername(name))[1]) = auth.uid()::text
  );

-- ---------------------------------------------------------------------------
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.images ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shipping_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_shipments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.follows ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.likes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.saved_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.conversation_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_views ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cart_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_blocks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.listing_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.saved_searches ENABLE ROW LEVEL SECURITY;

-- profiles
DROP POLICY IF EXISTS "profiles_select_public" ON public.profiles;
CREATE POLICY "profiles_select_public"
  ON public.profiles FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "profiles_update_own" ON public.profiles;
CREATE POLICY "profiles_update_own"
  ON public.profiles FOR UPDATE TO authenticated
  USING (id = auth.uid()) WITH CHECK (id = auth.uid());

-- categories
DROP POLICY IF EXISTS "categories_read" ON public.categories;
CREATE POLICY "categories_read"
  ON public.categories FOR SELECT TO anon, authenticated USING (true);

-- products
DROP POLICY IF EXISTS "products_select" ON public.products;
CREATE POLICY "products_select"
  ON public.products FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "products_insert_own" ON public.products;
CREATE POLICY "products_insert_own"
  ON public.products FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "products_update_own" ON public.products;
CREATE POLICY "products_update_own"
  ON public.products FOR UPDATE TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "products_delete_own" ON public.products;
CREATE POLICY "products_delete_own"
  ON public.products FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- images
DROP POLICY IF EXISTS "images_select" ON public.images;
CREATE POLICY "images_select"
  ON public.images FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "images_insert_owner" ON public.images;
CREATE POLICY "images_insert_owner"
  ON public.images FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.products p
      WHERE p.id = images.product_id AND p.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "images_mutate_owner" ON public.images;
CREATE POLICY "images_mutate_owner"
  ON public.images FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.products p
      WHERE p.id = images.product_id AND p.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "images_delete_owner" ON public.images;
CREATE POLICY "images_delete_owner"
  ON public.images FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.products p
      WHERE p.id = images.product_id AND p.user_id = auth.uid()
    )
  );

-- shipping_addresses
DROP POLICY IF EXISTS "addresses_own" ON public.shipping_addresses;
CREATE POLICY "addresses_own"
  ON public.shipping_addresses FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- cart
DROP POLICY IF EXISTS "cart_own" ON public.cart_items;
CREATE POLICY "cart_own"
  ON public.cart_items FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- likes
DROP POLICY IF EXISTS "likes_select" ON public.likes;
CREATE POLICY "likes_select"
  ON public.likes FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "likes_own" ON public.likes;
CREATE POLICY "likes_own"
  ON public.likes FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "likes_delete_own" ON public.likes;
CREATE POLICY "likes_delete_own"
  ON public.likes FOR DELETE TO authenticated USING (user_id = auth.uid());

-- saved_items
DROP POLICY IF EXISTS "saved_select" ON public.saved_items;
CREATE POLICY "saved_select"
  ON public.saved_items FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "saved_insert_own" ON public.saved_items;
CREATE POLICY "saved_insert_own"
  ON public.saved_items FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "saved_delete_own" ON public.saved_items;
CREATE POLICY "saved_delete_own"
  ON public.saved_items FOR DELETE TO authenticated USING (user_id = auth.uid());

-- follows
DROP POLICY IF EXISTS "follows_select" ON public.follows;
CREATE POLICY "follows_select"
  ON public.follows FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "follows_insert" ON public.follows;
CREATE POLICY "follows_insert"
  ON public.follows FOR INSERT TO authenticated WITH CHECK (follower_id = auth.uid());

DROP POLICY IF EXISTS "follows_delete" ON public.follows;
CREATE POLICY "follows_delete"
  ON public.follows FOR DELETE TO authenticated USING (follower_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Conversation membership helper (avoids RLS recursion on conversation_participants)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_conversation_member(conv_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.conversation_participants
    WHERE conversation_id = conv_id
      AND user_id = auth.uid()
  );
$$;

REVOKE ALL ON FUNCTION public.is_conversation_member(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.is_conversation_member(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.open_or_create_conversation(
  p_other_user_id uuid,
  p_product_id uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  me uuid := auth.uid();
  existing_id uuid;
  new_id uuid;
BEGIN
  IF me IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_other_user_id IS NULL OR me = p_other_user_id THEN
    RAISE EXCEPTION 'Invalid recipient';
  END IF;

  -- Always match on the two participants, never on product_id.
  SELECT c.id INTO existing_id
  FROM public.conversations c
  JOIN public.conversation_participants a
    ON a.conversation_id = c.id AND a.user_id = me
  JOIN public.conversation_participants b
    ON b.conversation_id = c.id AND b.user_id = p_other_user_id
  ORDER BY c.updated_at DESC NULLS LAST
  LIMIT 1;

  IF existing_id IS NOT NULL THEN
    IF p_product_id IS NOT NULL THEN
      UPDATE public.conversations
      SET product_id = p_product_id,
          updated_at = now()
      WHERE id = existing_id;
    END IF;
    RETURN existing_id;
  END IF;

  INSERT INTO public.conversations (product_id)
  VALUES (p_product_id)
  RETURNING id INTO new_id;

  INSERT INTO public.conversation_participants (conversation_id, user_id)
  VALUES (new_id, me), (new_id, p_other_user_id);

  RETURN new_id;
END;
$$;

REVOKE ALL ON FUNCTION public.open_or_create_conversation(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.open_or_create_conversation(uuid, uuid) TO authenticated;

-- conversations
DROP POLICY IF EXISTS "conv_select_member" ON public.conversations;
CREATE POLICY "conv_select_member"
  ON public.conversations FOR SELECT TO authenticated
  USING (public.is_conversation_member(id));

DROP POLICY IF EXISTS "conv_insert_auth" ON public.conversations;
CREATE POLICY "conv_insert_auth"
  ON public.conversations FOR INSERT TO authenticated WITH CHECK (true);

DROP POLICY IF EXISTS "conv_update_member" ON public.conversations;
CREATE POLICY "conv_update_member"
  ON public.conversations FOR UPDATE TO authenticated
  USING (public.is_conversation_member(id))
  WITH CHECK (public.is_conversation_member(id));

-- conversation_participants
-- NOTE: never SELECT conversation_participants inside its own policy (infinite recursion).
-- Use public.is_conversation_member() (SECURITY DEFINER) instead — see migrate_fix_conversation_rls.sql.
DROP POLICY IF EXISTS "cp_select" ON public.conversation_participants;
CREATE POLICY "cp_select"
  ON public.conversation_participants FOR SELECT TO authenticated
  USING (public.is_conversation_member(conversation_id));

DROP POLICY IF EXISTS "cp_insert" ON public.conversation_participants;
CREATE POLICY "cp_insert"
  ON public.conversation_participants FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    OR public.is_conversation_member(conversation_id)
  );

-- messages
DROP POLICY IF EXISTS "msg_select" ON public.messages;
CREATE POLICY "msg_select"
  ON public.messages FOR SELECT TO authenticated
  USING (public.is_conversation_member(conversation_id));

DROP POLICY IF EXISTS "msg_insert" ON public.messages;
CREATE POLICY "msg_insert"
  ON public.messages FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = auth.uid()
    AND public.is_conversation_member(conversation_id)
  );

DROP POLICY IF EXISTS "msg_update" ON public.messages;
CREATE POLICY "msg_update"
  ON public.messages FOR UPDATE TO authenticated
  USING (public.is_conversation_member(conversation_id))
  WITH CHECK (public.is_conversation_member(conversation_id));

DROP POLICY IF EXISTS "cp_update" ON public.conversation_participants;
CREATE POLICY "cp_update"
  ON public.conversation_participants FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- reviews
DROP POLICY IF EXISTS "reviews_read" ON public.reviews;
CREATE POLICY "reviews_read"
  ON public.reviews FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "reviews_insert" ON public.reviews;
CREATE POLICY "reviews_insert"
  ON public.reviews FOR INSERT TO authenticated
  WITH CHECK (reviewer_id = auth.uid());

-- product_views
DROP POLICY IF EXISTS "views_insert" ON public.product_views;
CREATE POLICY "views_insert"
  ON public.product_views FOR INSERT TO authenticated
  WITH CHECK (user_id IS NULL OR user_id = auth.uid());

DROP POLICY IF EXISTS "views_insert_anon" ON public.product_views;
CREATE POLICY "views_insert_anon"
  ON public.product_views FOR INSERT TO anon
  WITH CHECK (user_id IS NULL);

-- orders
DROP POLICY IF EXISTS "orders_select_party" ON public.orders;
CREATE POLICY "orders_select_party"
  ON public.orders FOR SELECT TO authenticated
  USING (buyer_id = auth.uid() OR seller_id = auth.uid());

DROP POLICY IF EXISTS "orders_insert_buyer" ON public.orders;
CREATE POLICY "orders_insert_buyer"
  ON public.orders FOR INSERT TO authenticated
  WITH CHECK (buyer_id = auth.uid());

DROP POLICY IF EXISTS "orders_update_party" ON public.orders;
CREATE POLICY "orders_update_party"
  ON public.orders FOR UPDATE TO authenticated
  USING (buyer_id = auth.uid() OR seller_id = auth.uid());

-- order_items (inherit via join — allow if order party)
DROP POLICY IF EXISTS "order_items_select" ON public.order_items;
CREATE POLICY "order_items_select"
  ON public.order_items FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_items.order_id
        AND (o.buyer_id = auth.uid() OR o.seller_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "order_items_insert" ON public.order_items;
CREATE POLICY "order_items_insert"
  ON public.order_items FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_items.order_id AND o.buyer_id = auth.uid()
    )
  );

-- order_shipments
DROP POLICY IF EXISTS "shipments_select" ON public.order_shipments;
CREATE POLICY "shipments_select"
  ON public.order_shipments FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_shipments.order_id
        AND (o.buyer_id = auth.uid() OR o.seller_id = auth.uid())
    )
  );

DROP POLICY IF EXISTS "shipments_mutate_seller" ON public.order_shipments;
CREATE POLICY "shipments_mutate_seller"
  ON public.order_shipments FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_shipments.order_id AND o.seller_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "shipments_update_seller" ON public.order_shipments;
CREATE POLICY "shipments_update_seller"
  ON public.order_shipments FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_shipments.order_id AND o.seller_id = auth.uid()
    )
  );

-- offers
DROP POLICY IF EXISTS "offers_select" ON public.offers;
CREATE POLICY "offers_select"
  ON public.offers FOR SELECT TO authenticated
  USING (
    buyer_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.products p
      WHERE p.id = offers.product_id AND p.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "offers_insert" ON public.offers;
CREATE POLICY "offers_insert"
  ON public.offers FOR INSERT TO authenticated
  WITH CHECK (buyer_id = auth.uid());

DROP POLICY IF EXISTS "offers_update_parties" ON public.offers;
CREATE POLICY "offers_update_parties"
  ON public.offers FOR UPDATE TO authenticated
  USING (
    buyer_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.products p
      WHERE p.id = offers.product_id AND p.user_id = auth.uid()
    )
  );

-- blocks
DROP POLICY IF EXISTS "blocks_own" ON public.user_blocks;
CREATE POLICY "blocks_own"
  ON public.user_blocks FOR ALL TO authenticated
  USING (blocker_id = auth.uid()) WITH CHECK (blocker_id = auth.uid());

-- listing_reports
DROP POLICY IF EXISTS "reports_insert" ON public.listing_reports;
CREATE POLICY "reports_insert"
  ON public.listing_reports FOR INSERT TO authenticated
  WITH CHECK (reporter_id = auth.uid());

-- notifications
DROP POLICY IF EXISTS "notif_own" ON public.notifications;
CREATE POLICY "notif_own"
  ON public.notifications FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "notif_update_own" ON public.notifications;
CREATE POLICY "notif_update_own"
  ON public.notifications FOR UPDATE TO authenticated
  USING (user_id = auth.uid());

-- saved_searches
DROP POLICY IF EXISTS "saved_search_own" ON public.saved_searches;
CREATE POLICY "saved_search_own"
  ON public.saved_searches FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- search_events (typeahead ranking)
ALTER TABLE public.search_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "search_events_insert" ON public.search_events;
CREATE POLICY "search_events_insert"
  ON public.search_events FOR INSERT TO anon, authenticated
  WITH CHECK (user_id IS NULL OR user_id = auth.uid());

DROP POLICY IF EXISTS "search_events_select_public" ON public.search_events;
CREATE POLICY "search_events_select_public"
  ON public.search_events FOR SELECT TO anon, authenticated
  USING (true);
