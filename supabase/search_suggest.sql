-- Popup search suggestions / events (Phase 1 ranking data)
-- Paste into Supabase SQL Editor if you already ran install_all / schema.

CREATE TABLE IF NOT EXISTS public.search_events (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id              UUID REFERENCES public.profiles (id) ON DELETE SET NULL,
  school               TEXT,
  query_text           TEXT NOT NULL DEFAULT '',
  suggestion_text      TEXT,
  suggestion_type      TEXT,
  result_product_id    UUID REFERENCES public.products (id) ON DELETE SET NULL,
  event_type           TEXT NOT NULL DEFAULT 'impression',
  -- event_type: typeahead | click | submit
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS search_events_query_idx
  ON public.search_events (lower(query_text), created_at DESC);

CREATE INDEX IF NOT EXISTS search_events_suggestion_idx
  ON public.search_events (lower(suggestion_text), created_at DESC)
  WHERE suggestion_text IS NOT NULL;

CREATE INDEX IF NOT EXISTS search_events_user_idx
  ON public.search_events (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS search_events_type_idx
  ON public.search_events (event_type, created_at DESC);

ALTER TABLE public.search_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "search_events_insert" ON public.search_events;
CREATE POLICY "search_events_insert"
  ON public.search_events FOR INSERT TO anon, authenticated
  WITH CHECK (
    user_id IS NULL OR user_id = auth.uid()
  );

DROP POLICY IF EXISTS "search_events_select_own" ON public.search_events;
CREATE POLICY "search_events_select_own"
  ON public.search_events FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR user_id IS NULL);

-- Aggregated popularity for ranking (readable by authenticated + anon for suggest)
DROP POLICY IF EXISTS "search_events_select_public_agg" ON public.search_events;
CREATE POLICY "search_events_select_public_agg"
  ON public.search_events FOR SELECT TO anon, authenticated
  USING (true);
