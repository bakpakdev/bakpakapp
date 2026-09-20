-- Allow conversation members to mark messages read and update their own last_read_at.
-- Without these, inbox badges never clear after opening a chat.

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
