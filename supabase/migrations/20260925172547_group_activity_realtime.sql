-- New posts and comments reach open apps through Supabase Realtime, like
-- chat messages already do. Row level security still decides who hears.
alter publication supabase_realtime add table public.submissions, public.comments;
