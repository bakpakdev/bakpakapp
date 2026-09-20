-- Fix conversation RLS + create chat safely.
-- 1) Avoids infinite recursion on conversation_participants
-- 2) Creates conversation + both participants in one SECURITY DEFINER call
--    (plain insert+select fails because the new row isn't "yours" until participants exist)
--
-- Run this once in the Supabase SQL Editor, then try Message seller again.

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
