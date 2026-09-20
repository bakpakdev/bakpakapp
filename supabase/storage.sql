-- =============================================================================
-- Supabase Storage — run AFTER schema.sql, BEFORE policies.sql
-- (policies reference bucket id `product-images`)
-- =============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('product-images', 'product-images', true, 10485760)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit;
