-- AttendX multi-institute foundation migration
-- Review and run in Supabase SQL Editor after backing up existing data.
-- This adds institute membership and a secure Admin-created institute RPC.
-- IMPORTANT: This foundation does not yet migrate legacy localStorage records or fully replace all existing RLS policies.

create table if not exists public.institutions (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 120),
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.institution_members (
  institution_id uuid not null references public.institutions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('admin','teacher','student')),
  created_at timestamptz not null default now(),
  primary key (institution_id,user_id)
);

create index if not exists institution_members_user_idx on public.institution_members(user_id);
create index if not exists institution_members_role_idx on public.institution_members(institution_id,role);

alter table public.institutions enable row level security;
alter table public.institution_members enable row level security;

drop policy if exists "institutions_read_member" on public.institutions;
create policy "institutions_read_member" on public.institutions
for select to authenticated
using (exists (
  select 1 from public.institution_members m
  where m.institution_id = institutions.id and m.user_id = (select auth.uid())
));

drop policy if exists "members_read_same_institution" on public.institution_members;
create policy "members_read_same_institution" on public.institution_members
for select to authenticated
using (user_id = (select auth.uid()) or exists (
  select 1 from public.institution_members mine
  where mine.institution_id = institution_members.institution_id
    and mine.user_id = (select auth.uid()) and mine.role = 'admin'
));

-- Only a signed-in user can create an institution for themselves.
-- Public signup metadata cannot directly assign a privileged role.
create or replace function public.attendx_create_institution(p_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
  v_name text := trim(coalesce(p_name,''));
begin
  if v_user is null then
    raise exception 'Sign in is required';
  end if;
  if length(v_name) < 2 or length(v_name) > 120 then
    raise exception 'Institute name must be between 2 and 120 characters';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_user) then
    raise exception 'Account profile is not ready; sign out and sign in again';
  end if;
  if exists (select 1 from public.institution_members m where m.user_id = v_user and m.role = 'admin') then
    raise exception 'This account already owns an institute workspace';
  end if;
  insert into public.institutions(name,created_by) values(v_name,v_user) returning id into v_id;
  insert into public.institution_members(institution_id,user_id,role) values(v_id,v_user,'admin');
  update public.profiles set role='admin' where id=v_user;
  return v_id;
end;
$$;

revoke all on function public.attendx_create_institution(text) from public;
grant execute on function public.attendx_create_institution(text) to authenticated;
grant select on public.institutions, public.institution_members to authenticated;

-- Existing students/subjects do not become tenant-isolated automatically just because
-- these tables exist. Before real multi-institute use, add institution_id to all data
-- tables, backfill each existing row to the correct institute, and replace old global
-- admin RLS policies with tenant-scoped policies. Do not enable production use until
-- that migration and the legacy app's cloud integration have been tested.
