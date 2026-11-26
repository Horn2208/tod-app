-- Deleting one's own account, as Apple requires of apps with accounts.
-- Removing the auth user cascades to the profile and from there to
-- memberships, posts, votes, gems, comments and chat messages; groups the
-- person started stay for the others (creator_id is set null). Pictures in
-- storage are removed by the app first: storage.objects is only emptied
-- through the Storage API.
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
