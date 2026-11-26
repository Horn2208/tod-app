-- Group and profile pictures, and the index the performance advisor asked for.

-- The composite key from votes to submissions, covered as a whole: the
-- primary key starts with submission_id but does not hold the other two.
create index votes_submission_group_day_idx on public.votes (submission_id, group_id, round_day);

-- Pictures are private: a group's picture is for its members, a face for the
-- people who share a group with it. The first folder of a path is its owner:
--   avatars/<user id>/<file>        group-images/<group id>/<file>
-- Deleting and replacing go through the Storage API, which runs these too.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars', 'avatars', false, 5242880, array['image/jpeg', 'image/png', 'image/heic']),
  ('group-images', 'group-images', false, 5242880, array['image/jpeg', 'image/png', 'image/heic']);

create policy "avatars_select_self_and_group_mates" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'avatars'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or (storage.foldername(name))[1] in (select mate::text from private.my_group_mate_ids() as mate)
    )
  );

create policy "avatars_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "avatars_update_own" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "avatars_delete_own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- Every member may change the group's picture, as in the app.
create policy "group_images_select_member" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'group-images'
    and (storage.foldername(name))[1] in (select grp::text from private.my_group_ids() as grp)
  );

create policy "group_images_insert_member" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'group-images'
    and (storage.foldername(name))[1] in (select grp::text from private.my_group_ids() as grp)
  );

create policy "group_images_update_member" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'group-images'
    and (storage.foldername(name))[1] in (select grp::text from private.my_group_ids() as grp)
  )
  with check (
    bucket_id = 'group-images'
    and (storage.foldername(name))[1] in (select grp::text from private.my_group_ids() as grp)
  );

create policy "group_images_delete_member" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'group-images'
    and (storage.foldername(name))[1] in (select grp::text from private.my_group_ids() as grp)
  );
