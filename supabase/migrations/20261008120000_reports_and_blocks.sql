-- Reporting and blocking, as Apple asks of apps where people post for each
-- other (App Review Guideline 1.2).
--
-- A report goes into `reports` and is read by whoever runs the project, in
-- the dashboard: nobody reads anyone else's report through the API, and the
-- reporter sees only their own. A block is one person's private choice: the
-- app leaves the blocked person's posts, comments and messages out for the
-- blocker. The blocked person is not told and sees nothing different.

create table public.reports (
  id bigint generated always as identity primary key,
  reporter_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  group_id uuid not null references public.groups (id) on delete cascade,
  -- What was reported: a post, a comment, a chat message, or the person.
  target_kind text not null check (target_kind in ('submission', 'comment', 'chat_message', 'member')),
  -- The reported row's id as text (posts and comments have numbers, chat
  -- messages uuids), or the person's id for 'member'. Kept as text and not as
  -- a foreign key: the report has to outlive a deleted post.
  target_id text not null check (char_length(target_id) between 1 and 64),
  reported_user_id uuid references public.profiles (id) on delete set null,
  reason text not null check (reason in ('offensive', 'spam', 'inappropriate', 'other')),
  -- What the reported thing said when it was reported, for the same reason.
  excerpt text check (char_length(excerpt) <= 500),
  created_at timestamptz not null default now()
);

create index reports_created_at_idx on public.reports (created_at desc);

create table public.blocks (
  blocker_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  blocked_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

alter table public.reports enable row level security;
alter table public.blocks enable row level security;

revoke all on public.reports, public.blocks from anon, authenticated;

grant select on public.reports to authenticated;
grant insert (group_id, target_kind, target_id, reported_user_id, reason, excerpt)
  on public.reports to authenticated;

grant select, delete on public.blocks to authenticated;
grant insert (blocked_id) on public.blocks to authenticated;

-- Only in groups one is in, and only as oneself.
create policy "reports_insert_member" on public.reports
  for insert to authenticated
  with check (
    reporter_id = (select auth.uid())
    and group_id in (select private.my_group_ids())
  );

create policy "reports_select_own" on public.reports
  for select to authenticated
  using (reporter_id = (select auth.uid()));

-- Only someone one shares a group with can be blocked: nobody else's posts
-- reach this person anyway.
create policy "blocks_insert_own" on public.blocks
  for insert to authenticated
  with check (
    blocker_id = (select auth.uid())
    and blocked_id in (select private.my_group_mate_ids())
  );

create policy "blocks_select_own" on public.blocks
  for select to authenticated
  using (blocker_id = (select auth.uid()));

create policy "blocks_delete_own" on public.blocks
  for delete to authenticated
  using (blocker_id = (select auth.uid()));
