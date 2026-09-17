-- TodApp, first schema.
--
-- Friend groups post one song a day, rate each other's songs blind, and see
-- everyone's ratings the next day. Everything is scoped to group membership,
-- and nothing is readable without signing in: `anon` gets no table at all.
--
-- Derived, not stored: a member's streak and posting days (from submissions),
-- a round's end (midnight), a song's fallback cover colour (from its title),
-- round scores (from votes). Battles, storage buckets and realtime come later.

-- ---------------------------------------------------------------------------
-- Private helpers. Not in an exposed schema, so not callable over the Data API;
-- `authenticated` may run them only because the policies below do.
-- ---------------------------------------------------------------------------

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

-- The day a round belongs to. One time zone for every group for now -- the
-- groups are in Germany. It is also spelled out in submissions.round_day;
-- change both together.
create function private.today()
returns date
language sql
stable
set search_path = ''
as $fn$
  select (now() at time zone 'Europe/Berlin')::date
$fn$;

-- ---------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------

-- One row per account, made by a trigger on sign-up. `is_premium` is set by
-- the server (StoreKit, later), never by the app: it is not granted for update.
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 40),
  avatar_path text,
  is_premium boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 40),
  icon text not null default '🎵' check (char_length(icon) between 1 and 16),
  image_path text,
  -- Kept when the creator's account goes: the group is everyone's.
  creator_id uuid default auth.uid() references public.profiles (id) on delete set null,
  invite_policy text not null default 'everyone'
    check (invite_policy in ('everyone', 'creator_only')),
  created_at timestamptz not null default now()
);
create index groups_creator_id_idx on public.groups (creator_id);

create table public.group_members (
  group_id uuid not null references public.groups (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, user_id)
);
create index group_members_user_id_idx on public.group_members (user_id);

-- A code to pass on to a friend; `join_group` turns it into a membership.
create table public.group_invites (
  code text primary key default encode(extensions.gen_random_bytes(8), 'hex'),
  group_id uuid not null references public.groups (id) on delete cascade,
  created_by uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '7 days'
);
create index group_invites_group_id_idx on public.group_invites (group_id);
create index group_invites_created_by_idx on public.group_invites (created_by);

-- A posted song. The round it belongs to follows from when it was posted, and
-- `posted_at` is not granted for insert, so a post always lands in today's round.
create table public.submissions (
  id bigint generated always as identity primary key,
  group_id uuid not null references public.groups (id) on delete cascade,
  poster_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  track text not null check (char_length(track) between 1 and 200),
  artist text not null check (char_length(artist) between 1 and 200),
  -- Where the song was found. All three or none.
  service text check (service in ('spotify', 'soundcloud')),
  service_track_id text,
  page_url text,
  artwork_url text,
  -- The whole song's length: it tells a song from its remix in the catalog.
  duration_seconds integer check (duration_seconds > 0),
  isrc text,
  apple_music_id text,
  -- The stretch the poster picked, in seconds. Both or neither.
  section_start double precision,
  section_end double precision,
  posted_at timestamptz not null default now(),
  round_day date not null
    generated always as ((posted_at at time zone 'Europe/Berlin')::date) stored,
  constraint submissions_source_complete check (
    (service is null) = (service_track_id is null)
    and (service is null) = (page_url is null)
  ),
  constraint submissions_section_valid check (
    (section_start is null and section_end is null)
    or (section_start >= 0 and section_end > section_start)
  ),
  -- One song a day per person per group.
  constraint submissions_one_per_day unique (group_id, poster_id, round_day),
  -- Targets for the composite keys below, which keep a vote's group and day
  -- equal to its song's.
  constraint submissions_id_group_day unique (id, group_id, round_day),
  constraint submissions_id_group unique (id, group_id)
);
create index submissions_poster_id_idx on public.submissions (poster_id);
create index submissions_group_day_idx on public.submissions (group_id, round_day);

-- One rating per person per song. Group and day are carried along so the
-- policies can tell a running round from a revealed one without a join; the
-- composite key keeps them true to the song.
create table public.votes (
  submission_id bigint not null,
  group_id uuid not null,
  round_day date not null,
  voter_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  rating smallint not null check (rating between -2 and 2),
  -- The reason, seen by everyone with the ratings the next day.
  note text check (char_length(note) <= 280),
  primary key (submission_id, voter_id),
  foreign key (submission_id, group_id, round_day)
    references public.submissions (id, group_id, round_day) on delete cascade
);
create index votes_voter_id_idx on public.votes (voter_id);
create index votes_group_day_idx on public.votes (group_id, round_day);

-- At most one hidden gem per person per group per day; the key says so.
create table public.hidden_gems (
  voter_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  group_id uuid not null,
  round_day date not null,
  submission_id bigint not null,
  primary key (voter_id, group_id, round_day),
  foreign key (submission_id, group_id, round_day)
    references public.submissions (id, group_id, round_day) on delete cascade
);
create index hidden_gems_submission_idx on public.hidden_gems (submission_id, group_id, round_day);
create index hidden_gems_group_day_idx on public.hidden_gems (group_id, round_day);

create table public.comments (
  id bigint generated always as identity primary key,
  submission_id bigint not null,
  group_id uuid not null,
  author_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000),
  created_at timestamptz not null default now(),
  foreign key (submission_id, group_id)
    references public.submissions (id, group_id) on delete cascade
);
create index comments_submission_idx on public.comments (submission_id, group_id, created_at);
create index comments_author_id_idx on public.comments (author_id);

-- The id may come from the app, which makes one for each message it shows
-- before the server has answered.
create table public.chat_messages (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  author_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  body text not null default '',
  mentioned_submission_id bigint,
  created_at timestamptz not null default now(),
  -- A message may be only a song; otherwise it needs words.
  constraint chat_messages_body_valid check (
    char_length(body) <= 2000
    and (char_length(body) >= 1 or mentioned_submission_id is not null)
  ),
  -- A mentioned song belongs to the same group.
  foreign key (mentioned_submission_id, group_id)
    references public.submissions (id, group_id) on delete set null (mentioned_submission_id)
);
create index chat_messages_group_created_idx on public.chat_messages (group_id, created_at);
create index chat_messages_author_id_idx on public.chat_messages (author_id);
create index chat_messages_mention_idx on public.chat_messages (mentioned_submission_id, group_id)
  where mentioned_submission_id is not null;

-- ---------------------------------------------------------------------------
-- Membership helpers for the policies. Security definer so a policy on
-- group_members can ask about group_members without recursing into itself;
-- each answers only about the signed-in user.
-- ---------------------------------------------------------------------------

create function private.my_group_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $fn$
  select m.group_id
  from public.group_members m
  where m.user_id = (select auth.uid())
$fn$;

-- Everyone in any of my groups, me included.
create function private.my_group_mate_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $fn$
  select distinct theirs.user_id
  from public.group_members mine
  join public.group_members theirs on theirs.group_id = mine.group_id
  where mine.user_id = (select auth.uid())
$fn$;

-- The creator always; every member when the group lets everyone invite.
create function private.can_invite(target_group uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select exists (
    select 1
    from public.groups g
    where g.id = target_group
      and (
        g.creator_id = (select auth.uid())
        or (
          g.invite_policy = 'everyone'
          and exists (
            select 1 from public.group_members m
            where m.group_id = g.id and m.user_id = (select auth.uid())
          )
        )
      )
  )
$fn$;

revoke execute on function
  private.today(), private.my_group_ids(), private.my_group_mate_ids(), private.can_invite(uuid)
  from public;
grant execute on function
  private.today(), private.my_group_ids(), private.my_group_mate_ids(), private.can_invite(uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------

-- Every new account gets a profile, named from the sign-up form or, failing
-- that, from its e-mail address. The name is for display only; nothing
-- authorises on it.
create function private.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  insert into public.profiles (id, name)
  values (
    new.id,
    left(
      coalesce(
        nullif(trim(new.raw_user_meta_data ->> 'name'), ''),
        nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
        'Neu'
      ),
      40
    )
  );
  return new;
end;
$fn$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function private.handle_new_user();

-- Whoever makes a group is its first member.
create function private.add_creator_as_member()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if new.creator_id is not null then
    insert into public.group_members (group_id, user_id)
    values (new.id, new.creator_id)
    on conflict do nothing;
  end if;
  return new;
end;
$fn$;

create trigger groups_add_creator
  after insert on public.groups
  for each row execute function private.add_creator_as_member();

-- Members may rename a group and change its picture; who may invite is the
-- creator's call alone (`InvitePolicy` in the app).
create function private.guard_group_update()
returns trigger
language plpgsql
set search_path = ''
as $fn$
begin
  if new.invite_policy is distinct from old.invite_policy
     and (select auth.uid()) is not null
     and old.creator_id is distinct from (select auth.uid()) then
    raise exception 'only the group''s creator decides who may invite'
      using errcode = '42501';
  end if;
  return new;
end;
$fn$;

create trigger groups_guard_update
  before update on public.groups
  for each row execute function private.guard_group_update();

revoke execute on function
  private.handle_new_user(), private.add_creator_as_member(), private.guard_group_update()
  from public;

-- ---------------------------------------------------------------------------
-- Joining by invite code: the one function the app calls directly. Security
-- definer because a joiner cannot see the group before being in it; it only
-- ever adds the signed-in user.
-- ---------------------------------------------------------------------------

create function public.join_group(invite_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  me uuid := (select auth.uid());
  target uuid;
begin
  if me is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;

  select i.group_id into target
  from public.group_invites i
  where i.code = lower(trim(invite_code))
    and i.expires_at > now();

  if target is null then
    raise exception 'invite not found or expired' using errcode = 'P0002';
  end if;

  insert into public.group_members (group_id, user_id)
  values (target, me)
  on conflict do nothing;

  return target;
end;
$fn$;

revoke execute on function public.join_group(text) from public, anon;
grant execute on function public.join_group(text) to authenticated;

-- ---------------------------------------------------------------------------
-- Privileges. New tables here are granted to everyone by default; take that
-- back and hand `authenticated` exactly what the app does. Columns the server
-- fills (ids, authors, times, days) are left out of insert and update.
-- ---------------------------------------------------------------------------

revoke all on
  public.profiles, public.groups, public.group_members, public.group_invites,
  public.submissions, public.votes, public.hidden_gems, public.comments,
  public.chat_messages
  from anon, authenticated;

grant select on public.profiles to authenticated;
grant update (name, avatar_path) on public.profiles to authenticated;

grant select, delete on public.groups to authenticated;
grant insert (name, icon, image_path, invite_policy) on public.groups to authenticated;
grant update (name, icon, image_path, invite_policy) on public.groups to authenticated;

grant select, delete on public.group_members to authenticated;

grant select, delete on public.group_invites to authenticated;
grant insert (group_id) on public.group_invites to authenticated;

grant select, delete on public.submissions to authenticated;
grant insert (
  group_id, track, artist, service, service_track_id, page_url, artwork_url,
  duration_seconds, isrc, apple_music_id, section_start, section_end
) on public.submissions to authenticated;

grant select, delete on public.votes to authenticated;
grant insert (submission_id, group_id, round_day, rating, note) on public.votes to authenticated;
grant update (rating, note) on public.votes to authenticated;

grant select, delete on public.hidden_gems to authenticated;
grant insert (group_id, round_day, submission_id) on public.hidden_gems to authenticated;
grant update (submission_id) on public.hidden_gems to authenticated;

grant select, delete on public.comments to authenticated;
grant insert (submission_id, group_id, body) on public.comments to authenticated;

grant select, delete on public.chat_messages to authenticated;
grant insert (id, group_id, body, mentioned_submission_id) on public.chat_messages to authenticated;

-- ---------------------------------------------------------------------------
-- Row level security
-- ---------------------------------------------------------------------------

alter table public.profiles enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.group_invites enable row level security;
alter table public.submissions enable row level security;
alter table public.votes enable row level security;
alter table public.hidden_gems enable row level security;
alter table public.comments enable row level security;
alter table public.chat_messages enable row level security;

-- profiles: yourself and the people in your groups.
create policy "profiles_select_group_mates" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()) or id in (select private.my_group_mate_ids()));

create policy "profiles_update_own" on public.profiles
  for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- groups: yours; the creator sees the row even before the trigger has made
-- them a member, so an insert can return it.
create policy "groups_select_member" on public.groups
  for select to authenticated
  using (id in (select private.my_group_ids()) or creator_id = (select auth.uid()));

create policy "groups_insert_as_creator" on public.groups
  for insert to authenticated
  with check (creator_id = (select auth.uid()));

create policy "groups_update_member" on public.groups
  for update to authenticated
  using (id in (select private.my_group_ids()))
  with check (id in (select private.my_group_ids()));

create policy "groups_delete_creator" on public.groups
  for delete to authenticated
  using (creator_id = (select auth.uid()));

-- group_members: see your groups' members; leave yourself, or remove someone
-- from a group you created. Joining goes through join_group().
create policy "group_members_select_member" on public.group_members
  for select to authenticated
  using (group_id in (select private.my_group_ids()));

create policy "group_members_delete_self_or_creator" on public.group_members
  for delete to authenticated
  using (
    user_id = (select auth.uid())
    or group_id in (
      select g.id from public.groups g where g.creator_id = (select auth.uid())
    )
  );

-- group_invites
create policy "group_invites_select_member" on public.group_invites
  for select to authenticated
  using (group_id in (select private.my_group_ids()));

create policy "group_invites_insert_if_allowed" on public.group_invites
  for insert to authenticated
  with check (created_by = (select auth.uid()) and private.can_invite(group_id));

create policy "group_invites_delete_own_or_creator" on public.group_invites
  for delete to authenticated
  using (
    created_by = (select auth.uid())
    or group_id in (
      select g.id from public.groups g where g.creator_id = (select auth.uid())
    )
  );

-- submissions: members see all posts at once -- blind is the rating, not the
-- song. Your own post can be taken back while its round runs.
create policy "submissions_select_member" on public.submissions
  for select to authenticated
  using (group_id in (select private.my_group_ids()));

create policy "submissions_insert_own" on public.submissions
  for insert to authenticated
  with check (
    poster_id = (select auth.uid())
    and group_id in (select private.my_group_ids())
  );

create policy "submissions_delete_own_today" on public.submissions
  for delete to authenticated
  using (poster_id = (select auth.uid()) and round_day = (select private.today()));

-- votes: your own always; everyone's once the round is over. Rating is for
-- today's songs, not your own.
create policy "votes_select_own_or_revealed" on public.votes
  for select to authenticated
  using (
    voter_id = (select auth.uid())
    or (
      group_id in (select private.my_group_ids())
      and round_day < (select private.today())
    )
  );

create policy "votes_insert_today" on public.votes
  for insert to authenticated
  with check (
    voter_id = (select auth.uid())
    and group_id in (select private.my_group_ids())
    and round_day = (select private.today())
    and not exists (
      select 1 from public.submissions s
      where s.id = submission_id and s.poster_id = (select auth.uid())
    )
  );

create policy "votes_update_today" on public.votes
  for update to authenticated
  using (voter_id = (select auth.uid()) and round_day = (select private.today()))
  with check (voter_id = (select auth.uid()) and round_day = (select private.today()));

create policy "votes_delete_today" on public.votes
  for delete to authenticated
  using (voter_id = (select auth.uid()) and round_day = (select private.today()));

-- hidden_gems: the same rules as votes.
create policy "hidden_gems_select_own_or_revealed" on public.hidden_gems
  for select to authenticated
  using (
    voter_id = (select auth.uid())
    or (
      group_id in (select private.my_group_ids())
      and round_day < (select private.today())
    )
  );

create policy "hidden_gems_insert_today" on public.hidden_gems
  for insert to authenticated
  with check (
    voter_id = (select auth.uid())
    and group_id in (select private.my_group_ids())
    and round_day = (select private.today())
    and not exists (
      select 1 from public.submissions s
      where s.id = submission_id and s.poster_id = (select auth.uid())
    )
  );

create policy "hidden_gems_update_today" on public.hidden_gems
  for update to authenticated
  using (voter_id = (select auth.uid()) and round_day = (select private.today()))
  with check (
    voter_id = (select auth.uid())
    and round_day = (select private.today())
    and not exists (
      select 1 from public.submissions s
      where s.id = submission_id and s.poster_id = (select auth.uid())
    )
  );

create policy "hidden_gems_delete_today" on public.hidden_gems
  for delete to authenticated
  using (voter_id = (select auth.uid()) and round_day = (select private.today()));

-- comments
create policy "comments_select_member" on public.comments
  for select to authenticated
  using (group_id in (select private.my_group_ids()));

create policy "comments_insert_own" on public.comments
  for insert to authenticated
  with check (
    author_id = (select auth.uid())
    and group_id in (select private.my_group_ids())
  );

create policy "comments_delete_own" on public.comments
  for delete to authenticated
  using (author_id = (select auth.uid()));

-- chat_messages
create policy "chat_messages_select_member" on public.chat_messages
  for select to authenticated
  using (group_id in (select private.my_group_ids()));

create policy "chat_messages_insert_own" on public.chat_messages
  for insert to authenticated
  with check (
    author_id = (select auth.uid())
    and group_id in (select private.my_group_ids())
  );

create policy "chat_messages_delete_own" on public.chat_messages
  for delete to authenticated
  using (author_id = (select auth.uid()));
