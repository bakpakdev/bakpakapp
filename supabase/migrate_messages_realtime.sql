-- Enable live chat updates for messages (Supabase Realtime).
-- Run once in the Supabase SQL editor if Instant updates aren't arriving.

alter publication supabase_realtime add table public.messages;
