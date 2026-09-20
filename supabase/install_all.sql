-- SUPABASE SQL EDITOR: paste EVERYTHING below into Dashboard → SQL → New query.
-- Do NOT paste a file path (e.g. supabase/install_all.sql) — only the SQL text from this file.
-- First real SQL line should be CREATE TABLE or similar after these comments.

-- =============================================================================
-- Popup — Supabase Auth + Postgres (fresh project)
-- Run order in SQL Editor:
--   1) schema.sql   2) storage.sql   3) policies.sql
-- Then: Authentication → disable "Confirm email" for dev (or confirm in inbox).
--
-- Uses public.profiles (id = auth.users.id UUID). No public.users password table.
-- Products, cart, messages, etc. reference profiles(id).
--
-- Dashboard: Authentication → disable "Confirm email" for easier iOS dev, or
-- handle unconfirmed users in the app.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Profile row per auth user (trigger below inserts on signup)
-- ---------------------------------------------------------------------------
CREATE TABLE public.profiles (
  id                UUID PRIMARY KEY REFERENCES auth.users (id) ON DELETE CASCADE,
  username          TEXT NOT NULL UNIQUE,
  email             TEXT,
  first_name        TEXT,
  last_name         TEXT,
  bio               TEXT,
  avatar_url        TEXT,
  shop_name         TEXT,
  date_of_birth     TIMESTAMPTZ,
  country           TEXT,
  is_verified       BOOLEAN NOT NULL DEFAULT FALSE,
  instagram_handle  TEXT,
  website_url       TEXT,
  city              TEXT,
  postal_code       TEXT,
  last_active_at    TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX profiles_username_idx ON public.profiles (username);

-- ---------------------------------------------------------------------------
CREATE TABLE public.categories (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id   UUID REFERENCES public.categories (id) ON DELETE SET NULL,
  name        TEXT NOT NULL,
  slug        TEXT NOT NULL UNIQUE,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  icon        TEXT
);

CREATE INDEX categories_parent_id_idx ON public.categories (parent_id);

-- ---------------------------------------------------------------------------
CREATE TABLE public.products (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title              TEXT NOT NULL,
  description        TEXT NOT NULL,
  price              DOUBLE PRECISION NOT NULL CHECK (price >= 0),
  condition          TEXT NOT NULL,
  size               TEXT,
  brand              TEXT,
  category           TEXT NOT NULL,
  tags               JSONB,
  is_sold            BOOLEAN NOT NULL DEFAULT FALSE,
  color              TEXT,
  material           TEXT,
  department         TEXT,
  package_size       TEXT,
  ship_from_city     TEXT,
  ship_from_country  TEXT,
  original_price     DOUBLE PRECISION,
  currency           TEXT NOT NULL DEFAULT 'USD',
  is_boosted         BOOLEAN NOT NULL DEFAULT FALSE,
  boosted_until      TIMESTAMPTZ,
  school             TEXT,
  meetup_location    TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  user_id            UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE
);

CREATE INDEX products_user_id_idx ON public.products (user_id);
CREATE INDEX products_category_idx ON public.products (category);
CREATE INDEX products_is_sold_idx ON public.products (is_sold);
CREATE INDEX products_created_at_idx ON public.products (created_at DESC);
CREATE INDEX IF NOT EXISTS products_school_idx ON public.products (school);
CREATE INDEX IF NOT EXISTS products_school_created_at_idx ON public.products (school, created_at DESC);

-- ---------------------------------------------------------------------------
CREATE TABLE public.images (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  url         TEXT NOT NULL,
  public_id   TEXT,
  is_primary  BOOLEAN NOT NULL DEFAULT FALSE,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  product_id  UUID NOT NULL REFERENCES public.products (id) ON DELETE CASCADE
);

CREATE INDEX images_product_id_idx ON public.images (product_id);

-- ---------------------------------------------------------------------------
CREATE TABLE public.shipping_addresses (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  full_name    TEXT NOT NULL,
  line1        TEXT NOT NULL,
  line2        TEXT,
  city         TEXT NOT NULL,
  region       TEXT,
  postal_code  TEXT NOT NULL,
  country      TEXT NOT NULL,
  phone        TEXT,
  is_default   BOOLEAN NOT NULL DEFAULT FALSE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX shipping_addresses_user_id_idx ON public.shipping_addresses (user_id);

-- ---------------------------------------------------------------------------
CREATE TABLE public.orders (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  total                 DOUBLE PRECISION NOT NULL,
  status                TEXT NOT NULL DEFAULT 'pending',
  shipping_address      TEXT NOT NULL,
  payment_intent_id     TEXT,
  shipping_address_id   UUID REFERENCES public.shipping_addresses (id) ON DELETE SET NULL,
  buyer_note            TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
  buyer_id              UUID NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
  seller_id             UUID NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT
);

CREATE INDEX orders_buyer_id_idx ON public.orders (buyer_id);
CREATE INDEX orders_seller_id_idx ON public.orders (seller_id);

-- ---------------------------------------------------------------------------
CREATE TABLE public.order_items (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  quantity   INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
  price      DOUBLE PRECISION NOT NULL,
  order_id   UUID NOT NULL REFERENCES public.orders (id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES public.products (id) ON DELETE RESTRICT
);

-- ---------------------------------------------------------------------------
CREATE TABLE public.order_shipments (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id         UUID NOT NULL REFERENCES public.orders (id) ON DELETE CASCADE,
  carrier          TEXT,
  tracking_number  TEXT,
  label_url        TEXT,
  shipped_at       TIMESTAMPTZ,
  delivered_at     TIMESTAMPTZ,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
CREATE TABLE public.offers (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id  UUID NOT NULL REFERENCES public.products (id) ON DELETE CASCADE,
  buyer_id    UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  amount      DOUBLE PRECISION NOT NULL CHECK (amount > 0),
  currency    TEXT NOT NULL DEFAULT 'USD',
  message     TEXT,
  status      TEXT NOT NULL DEFAULT 'pending',
  expires_at  TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT offers_status_check CHECK (
    status IN ('pending', 'accepted', 'declined', 'expired', 'withdrawn')
  )
);

CREATE INDEX offers_product_id_idx ON public.offers (product_id);

-- ---------------------------------------------------------------------------
CREATE TABLE public.follows (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  follower_id   UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  following_id  UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  UNIQUE (follower_id, following_id),
  CHECK (follower_id <> following_id)
);

CREATE TABLE public.likes (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  user_id    UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES public.products (id) ON DELETE CASCADE,
  UNIQUE (user_id, product_id)
);

CREATE TABLE public.saved_items (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  user_id    UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES public.products (id) ON DELETE CASCADE,
  UNIQUE (user_id, product_id)
);

-- ---------------------------------------------------------------------------
CREATE TABLE public.conversations (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id  UUID REFERENCES public.products (id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.conversation_participants (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id  UUID NOT NULL REFERENCES public.conversations (id) ON DELETE CASCADE,
  user_id          UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  last_read_at     TIMESTAMPTZ,
  UNIQUE (conversation_id, user_id)
);

CREATE TABLE public.messages (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  content          TEXT NOT NULL,
  is_read          BOOLEAN NOT NULL DEFAULT FALSE,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  sender_id        UUID NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
  conversation_id  UUID NOT NULL REFERENCES public.conversations (id) ON DELETE CASCADE
);

CREATE INDEX messages_conversation_id_idx ON public.messages (conversation_id);

-- ---------------------------------------------------------------------------
CREATE TABLE public.reviews (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rating       INTEGER NOT NULL CHECK (rating >= 1 AND rating <= 5),
  comment      TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  reviewer_id  UUID NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
  reviewed_id  UUID NOT NULL REFERENCES public.profiles (id) ON DELETE RESTRICT,
  order_id     UUID REFERENCES public.orders (id) ON DELETE SET NULL,
  product_id   UUID REFERENCES public.products (id) ON DELETE SET NULL,
  UNIQUE (reviewer_id, reviewed_id)
);

-- ---------------------------------------------------------------------------
CREATE TABLE public.product_views (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  user_id    UUID REFERENCES public.profiles (id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES public.products (id) ON DELETE CASCADE
);

CREATE TABLE public.cart_items (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  quantity   INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  user_id    UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  product_id UUID NOT NULL REFERENCES public.products (id) ON DELETE CASCADE,
  UNIQUE (user_id, product_id)
);

-- ---------------------------------------------------------------------------
CREATE TABLE public.user_blocks (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  blocker_id  UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  blocked_id  UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  UNIQUE (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);

CREATE TABLE public.listing_reports (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  product_id  UUID NOT NULL REFERENCES public.products (id) ON DELETE CASCADE,
  reason      TEXT NOT NULL,
  details     TEXT,
  status      TEXT NOT NULL DEFAULT 'open',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT listing_reports_status_check CHECK (
    status IN ('open', 'reviewed', 'actioned', 'dismissed')
  )
);

CREATE TABLE public.notifications (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  type       TEXT NOT NULL,
  title      TEXT,
  body       TEXT,
  data       JSONB NOT NULL DEFAULT '{}'::jsonb,
  read_at    TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.saved_searches (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  name                   TEXT,
  query_text             TEXT,
  category_slug          TEXT,
  min_price              DOUBLE PRECISION,
  max_price              DOUBLE PRECISION,
  department             TEXT,
  notify_new_listings    BOOLEAN NOT NULL DEFAULT FALSE,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

CREATE TRIGGER products_updated_at
  BEFORE UPDATE ON public.products
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

CREATE TRIGGER orders_updated_at
  BEFORE UPDATE ON public.orders
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

CREATE TRIGGER conversations_updated_at
  BEFORE UPDATE ON public.conversations
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

CREATE TRIGGER cart_items_updated_at
  BEFORE UPDATE ON public.cart_items
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

CREATE TRIGGER shipping_addresses_updated_at
  BEFORE UPDATE ON public.shipping_addresses
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

CREATE TRIGGER offers_updated_at
  BEFORE UPDATE ON public.offers
  FOR EACH ROW EXECUTE PROCEDURE public.set_updated_at();

-- ---------------------------------------------------------------------------
-- Auto-create profile when a new auth user is created (username from metadata)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  base_name TEXT;
  final_name TEXT;
BEGIN
  base_name := COALESCE(
    NULLIF(trim(NEW.raw_user_meta_data->>'username'), ''),
    regexp_replace(split_part(NEW.email, '@', 1), '[^a-zA-Z0-9_]', '_', 'g')
  );
  IF base_name IS NULL OR base_name = '' THEN
    base_name := 'user_' || replace(substr(NEW.id::text, 1, 13), '-', '');
  END IF;
  final_name := base_name;
  WHILE EXISTS (SELECT 1 FROM public.profiles WHERE username = final_name) LOOP
    final_name := base_name || '_' || substr(md5(random()::text), 1, 6);
  END LOOP;

  INSERT INTO public.profiles (id, username, email)
  VALUES (NEW.id, final_name, NEW.email);
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- ---------------------------------------------------------------------------
INSERT INTO public.categories (parent_id, name, slug, sort_order) VALUES
  (NULL, 'Tops', 'tops', 10),
  (NULL, 'Bottoms', 'bottoms', 20),
  (NULL, 'Dresses', 'dresses', 30),
  (NULL, 'Outerwear', 'outerwear', 40),
  (NULL, 'Shoes', 'shoes', 50),
  (NULL, 'Bags & accessories', 'accessories', 60),
  (NULL, 'Vintage', 'vintage', 70),
  (NULL, 'Streetwear', 'streetwear', 80)
ON CONFLICT (slug) DO NOTHING;

-- --- storage ---
-- =============================================================================
-- Supabase Storage — run AFTER schema.sql, BEFORE policies.sql
-- (policies reference bucket id `product-images`)
-- =============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('product-images', 'product-images', true, 10485760)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit;

-- --- policies ---
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

-- Conversation membership helper (avoids RLS recursion)
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
