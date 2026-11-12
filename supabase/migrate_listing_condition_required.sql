-- Every listing needs a condition (the app already blocks posting without one).
-- This makes the database refuse an empty condition too. NOT VALID skips checking
-- rows that already exist, so it applies cleanly; new and edited rows are checked.
ALTER TABLE public.products
  DROP CONSTRAINT IF EXISTS products_condition_required;
ALTER TABLE public.products
  ADD CONSTRAINT products_condition_required
  CHECK (btrim(condition) <> '') NOT VALID;
