-- One chat per user pair (not per listing).
-- Messaging about another item reuses the existing conversation and keeps history.
-- Optionally refreshes conversations.product_id to the latest listing being discussed.
--
-- Run in the Supabase SQL Editor (or via apply_with_psql.sh).

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
    -- Keep chat context pointed at the listing they just messaged about.
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
