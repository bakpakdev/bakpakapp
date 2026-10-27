-- Migration: every campus is its own community (database-side lock).
-- The app already filters listings, search, suggestions and rankings by campus;
-- this makes the database refuse cross-campus listing reads too.
--
-- NOT APPLIED YET. Review before running: signed-out (anon) reads keep working so
-- closet share links on the web don't break.

-- 1) Backfill any listing still missing a campus from its seller's school.
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

-- 2) Campus of the signed-in student, from profiles.country.
CREATE OR REPLACE FUNCTION public.my_campus()
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN lower(coalesce(country, '')) LIKE '%oregon state%'
      OR lower(coalesce(country, '')) LIKE '%osu%'
      OR lower(coalesce(country, '')) LIKE '%beaver%'
      THEN 'osu'
    WHEN country IS NOT NULL AND btrim(country) <> '' THEN 'uo'
    ELSE NULL
  END
  FROM public.profiles
  WHERE id = auth.uid()
$$;

-- 3) Signed-in students read their own listings, their campus's listings, and the
--    DEV sandbox (only reachable from Debug simulator builds).
DROP POLICY IF EXISTS "products_select" ON public.products;
CREATE POLICY "products_select"
  ON public.products FOR SELECT TO anon
  USING (true);

DROP POLICY IF EXISTS "products_select_campus" ON public.products;
CREATE POLICY "products_select_campus"
  ON public.products FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR school = public.my_campus()
    OR school = 'dev'
  );

-- 4) New listings can only be posted to your own campus (or the DEV sandbox).
DROP POLICY IF EXISTS "products_insert_own" ON public.products;
CREATE POLICY "products_insert_own"
  ON public.products FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND (school = public.my_campus() OR school = 'dev')
  );
