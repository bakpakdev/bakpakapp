-- Public-profile privacy choices (Settings → Privacy). Other students' apps read these
-- through the existing profiles_select_public policy; owners write them through
-- profiles_update_own. Missing keys mean "on" (today's behavior).
--   show_school_badge   bool  school pill on the public profile
--   show_sold_items     bool  "sold" section on the public closet
--   show_follower_counts bool follower / following counts on the public profile
--   allow_new_messages  bool  people without an existing chat can start one
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS privacy JSONB NOT NULL DEFAULT '{}'::jsonb;
