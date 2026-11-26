-- New chat messages reach the open chat screens of the group through
-- Supabase Realtime. Row level security still decides who hears of a row.
alter publication supabase_realtime add table public.chat_messages;
