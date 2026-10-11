-- Mutual block visibility: either party can read a block row so both clients hide each other.
DROP POLICY IF EXISTS "blocks_own" ON public.user_blocks;

DROP POLICY IF EXISTS "blocks_select_involved" ON public.user_blocks;
CREATE POLICY "blocks_select_involved"
  ON public.user_blocks FOR SELECT TO authenticated
  USING (blocker_id = auth.uid() OR blocked_id = auth.uid());

DROP POLICY IF EXISTS "blocks_insert_own" ON public.user_blocks;
CREATE POLICY "blocks_insert_own"
  ON public.user_blocks FOR INSERT TO authenticated
  WITH CHECK (blocker_id = auth.uid());

DROP POLICY IF EXISTS "blocks_delete_own" ON public.user_blocks;
CREATE POLICY "blocks_delete_own"
  ON public.user_blocks FOR DELETE TO authenticated
  USING (blocker_id = auth.uid());

DROP POLICY IF EXISTS "blocks_update_own" ON public.user_blocks;
CREATE POLICY "blocks_update_own"
  ON public.user_blocks FOR UPDATE TO authenticated
  USING (blocker_id = auth.uid())
  WITH CHECK (blocker_id = auth.uid());
