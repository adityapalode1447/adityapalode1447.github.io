-- AttendX Cloud schema for Supabase
-- Run this in Supabase SQL Editor after reviewing it.
-- Uses Supabase Auth; do not store plaintext passwords or legacy localStorage hashes here.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  role text not null default 'student' check (role in ('admin','teacher','student')),
  student_prn text unique,
  created_at timestamptz not null default now()
);

create table if not exists public.students (
  id uuid primary key default gen_random_uuid(),
  prn text not null unique,
  full_name text not null,
  year text,
  branch text,
  profile_id uuid unique references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.subjects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  year text,
  branch text,
  teacher_profile_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  unique (name, year, branch)
);

create table if not exists public.attendance_sessions (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id) on delete cascade,
  attendance_date date not null,
  slot text not null default 'Lecture 1',
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  unique (subject_id, attendance_date, slot)
);

create table if not exists public.attendance_records (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.attendance_sessions(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  status text not null check (status in ('present','absent','leave','medical','od')),
  marked_by uuid not null references public.profiles(id),
  updated_at timestamptz not null default now(),
  unique (session_id, student_id)
);

create or replace function public.current_user_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select p.role from public.profiles p where p.id = (select auth.uid())
$$;

create or replace function public.is_attendx_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.current_user_role() = 'admin', false)
$$;

create or replace function public.teaches_subject(subject_uuid uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.subjects s
    where s.id = subject_uuid and s.teacher_profile_id = (select auth.uid())
  )
$$;

alter table public.profiles enable row level security;
alter table public.students enable row level security;
alter table public.subjects enable row level security;
alter table public.attendance_sessions enable row level security;
alter table public.attendance_records enable row level security;

-- Profiles: users can read their own profile; admins manage all profiles.
drop policy if exists "profile read self or admin" on public.profiles;
create policy "profile read self or admin" on public.profiles
for select to authenticated
using (id = (select auth.uid()) or public.is_attendx_admin());

drop policy if exists "admin manages profiles" on public.profiles;
create policy "admin manages profiles" on public.profiles
for all to authenticated
using (public.is_attendx_admin())
with check (public.is_attendx_admin());

-- Students: admins manage all; teachers see students matching their assigned subjects.
drop policy if exists "students read admin teacher or self" on public.students;
create policy "students read admin teacher or self" on public.students
for select to authenticated
using (
  public.is_attendx_admin()
  or profile_id = (select auth.uid())
  or exists (
    select 1 from public.subjects s
    where s.teacher_profile_id = (select auth.uid())
      and (s.year is null or s.year = students.year)
      and (s.branch is null or lower(regexp_replace(s.branch, '[^a-zA-Z0-9]', '', 'g')) =
                          lower(regexp_replace(coalesce(students.branch,''), '[^a-zA-Z0-9]', '', 'g')))
  )
);

drop policy if exists "admin manages students" on public.students;
create policy "admin manages students" on public.students
for all to authenticated
using (public.is_attendx_admin())
with check (public.is_attendx_admin());

-- Subjects: admins manage; teachers read their own; students can read subjects for their class.
drop policy if exists "subjects visible to assigned users" on public.subjects;
create policy "subjects visible to assigned users" on public.subjects
for select to authenticated
using (
  public.is_attendx_admin()
  or teacher_profile_id = (select auth.uid())
  or exists (
    select 1 from public.students st
    where st.profile_id = (select auth.uid())
      and (subjects.year is null or subjects.year = st.year)
      and (subjects.branch is null or lower(regexp_replace(subjects.branch, '[^a-zA-Z0-9]', '', 'g')) =
                            lower(regexp_replace(coalesce(st.branch,''), '[^a-zA-Z0-9]', '', 'g')))
  )
);

drop policy if exists "admin manages subjects" on public.subjects;
create policy "admin manages subjects" on public.subjects
for all to authenticated
using (public.is_attendx_admin())
with check (public.is_attendx_admin());

-- Attendance sessions: admin, assigned teacher, or a student in that subject's class can read.
drop policy if exists "sessions visible to class" on public.attendance_sessions;
create policy "sessions visible to class" on public.attendance_sessions
for select to authenticated
using (
  public.is_attendx_admin()
  or public.teaches_subject(subject_id)
  or exists (
    select 1 from public.students st
    join public.subjects sb on sb.id = attendance_sessions.subject_id
    where st.profile_id = (select auth.uid())
      and (sb.year is null or sb.year = st.year)
      and (sb.branch is null or lower(regexp_replace(sb.branch, '[^a-zA-Z0-9]', '', 'g')) =
                            lower(regexp_replace(coalesce(st.branch,''), '[^a-zA-Z0-9]', '', 'g')))
  )
);

drop policy if exists "admin or assigned teacher manages sessions" on public.attendance_sessions;
create policy "admin or assigned teacher manages sessions" on public.attendance_sessions
for all to authenticated
using (public.is_attendx_admin() or public.teaches_subject(subject_id))
with check (
  public.is_attendx_admin()
  or (public.teaches_subject(subject_id) and created_by = (select auth.uid()))
);

-- Attendance records: students can read only their own; admins and assigned teachers can manage class records.
drop policy if exists "records read by permitted users" on public.attendance_records;
create policy "records read by permitted users" on public.attendance_records
for select to authenticated
using (
  public.is_attendx_admin()
  or exists (
    select 1 from public.attendance_sessions se
    where se.id = attendance_records.session_id
      and public.teaches_subject(se.subject_id)
  )
  or exists (
    select 1 from public.students st
    where st.id = attendance_records.student_id
      and st.profile_id = (select auth.uid())
  )
);

drop policy if exists "admin or assigned teacher manages records" on public.attendance_records;
create policy "admin or assigned teacher manages records" on public.attendance_records
for all to authenticated
using (
  public.is_attendx_admin()
  or exists (
    select 1 from public.attendance_sessions se
    where se.id = attendance_records.session_id
      and public.teaches_subject(se.subject_id)
  )
)
with check (
  (public.is_attendx_admin() or exists (
    select 1 from public.attendance_sessions se
    where se.id = attendance_records.session_id
      and public.teaches_subject(se.subject_id)
  ))
  and marked_by = (select auth.uid())
);

-- New signups receive a student profile by default. Promote the first admin manually
-- from the Supabase SQL Editor after creating its Auth user; never allow client-side role escalation.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, role)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', 'AttendX User'), 'student')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_attendx on auth.users;
create trigger on_auth_user_created_attendx
after insert on auth.users
for each row execute procedure public.handle_new_user();
