-- =============================================================================
-- Migration: school-scoped listings + meetup location + case-safe storage RLS
-- Run in Supabase Dashboard → SQL Editor (or via apply_with_psql.sh after schema).
-- Safe to re-run.
-- =============================================================================

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS school TEXT;

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS meetup_location TEXT;

CREATE INDEX IF NOT EXISTS products_school_idx ON public.products (school);
CREATE INDEX IF NOT EXISTS products_school_created_at_idx
  ON public.products (school, created_at DESC);

-- Backfill school from seller profile (profiles.country stores school name).
UPDATE public.products p
SET school = CASE
  WHEN lower(coalesce(pr.country, '')) LIKE '%oregon state%'
    OR lower(coalesce(pr.country, '')) LIKE '%osu%'
    OR lower(coalesce(pr.country, '')) LIKE '%beaver%'
    THEN 'osu'
  WHEN pr.country IS NOT NULL AND btrim(pr.country) <> '' THEN 'uo'
  ELSE p.school
END
FROM public.profiles pr
WHERE pr.id = p.user_id
  AND (p.school IS NULL OR btrim(p.school) = '');

-- Storage folder checks: Swift UUID().uuidString is uppercase; auth.uid()::text is lowercase.
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

-- Ensure public can read all listings (same-campus filtering is done in the app).
DROP POLICY IF EXISTS "products_select" ON public.products;
CREATE POLICY "products_select"
  ON public.products FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "products_insert_own" ON public.products;
CREATE POLICY "products_insert_own"
  ON public.products FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "images_select" ON public.images;
CREATE POLICY "images_select"
  ON public.images FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "images_insert_owner" ON public.images;
CREATE POLICY "images_insert_owner"
  ON public.images FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.products p
      WHERE p.id = images.product_id AND p.user_id = auth.uid()
    )
  );
