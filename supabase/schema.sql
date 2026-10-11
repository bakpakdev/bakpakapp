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
  stripe_account_id TEXT,
  last_active_at    TIMESTAMPTZ,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX profiles_username_idx ON public.profiles (username);
CREATE INDEX profiles_stripe_account_id_idx ON public.profiles (stripe_account_id);

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
CREATE INDEX products_school_idx ON public.products (school);
CREATE INDEX products_school_created_at_idx ON public.products (school, created_at DESC);

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

CREATE TABLE public.user_reports (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id     UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  reported_id     UUID NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  conversation_id UUID REFERENCES public.conversations (id) ON DELETE SET NULL,
  product_id      UUID REFERENCES public.products (id) ON DELETE SET NULL,
  reason          TEXT NOT NULL,
  details         TEXT,
  status          TEXT NOT NULL DEFAULT 'open',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT user_reports_status_check CHECK (
    status IN ('open', 'reviewed', 'actioned', 'dismissed')
  ),
  CONSTRAINT user_reports_not_self CHECK (reporter_id <> reported_id)
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

-- Autocomplete / ranking events for search suggestions
CREATE TABLE public.search_events (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              UUID REFERENCES public.profiles (id) ON DELETE SET NULL,
  school               TEXT,
  query_text           TEXT NOT NULL DEFAULT '',
  suggestion_text      TEXT,
  suggestion_type      TEXT,
  result_product_id    UUID REFERENCES public.products (id) ON DELETE SET NULL,
  event_type           TEXT NOT NULL DEFAULT 'impression',
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX search_events_query_idx
  ON public.search_events (lower(query_text), created_at DESC);
CREATE INDEX search_events_suggestion_idx
  ON public.search_events (lower(suggestion_text), created_at DESC)
  WHERE suggestion_text IS NOT NULL;
CREATE INDEX search_events_user_idx
  ON public.search_events (user_id, created_at DESC);
CREATE INDEX search_events_type_idx
  ON public.search_events (event_type, created_at DESC);

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
