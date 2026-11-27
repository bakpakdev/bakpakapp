-- Saved items are folded into likes: listings now have one like button (a pill
-- with the like count), and "Liked items" is the one list.
-- This copies everyone's saved items into their likes so nothing is lost.
-- Items someone both liked and saved stay a single like.
-- It leaves the saved_items table in place (the app no longer reads it), so it
-- can be dropped later once you're happy.
-- Note: each copied save becomes a like, so a listing's like count can go up.
-- Safe to run more than once. Run in the Supabase SQL Editor.

BEGIN;

INSERT INTO public.likes (user_id, product_id, created_at)
SELECT s.user_id, s.product_id, s.created_at
FROM public.saved_items s
ON CONFLICT (user_id, product_id) DO NOTHING;

COMMIT;
