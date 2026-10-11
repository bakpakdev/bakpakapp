-- User reports from chat / profile (in-app report flow).
CREATE TABLE IF NOT EXISTS public.user_reports (
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

CREATE INDEX IF NOT EXISTS user_reports_reported_id_idx ON public.user_reports (reported_id);
CREATE INDEX IF NOT EXISTS user_reports_reporter_id_idx ON public.user_reports (reporter_id);
CREATE INDEX IF NOT EXISTS user_reports_status_idx ON public.user_reports (status);

ALTER TABLE public.user_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "user_reports_insert" ON public.user_reports;
CREATE POLICY "user_reports_insert"
  ON public.user_reports FOR INSERT TO authenticated
  WITH CHECK (reporter_id = auth.uid());

DROP POLICY IF EXISTS "user_reports_select_own" ON public.user_reports;
CREATE POLICY "user_reports_select_own"
  ON public.user_reports FOR SELECT TO authenticated
  USING (reporter_id = auth.uid());
