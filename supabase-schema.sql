-- AttendX Cloud schema for Supabase
-- Run in Supabase Dashboard > SQL Editor > New query.
-- This creates the cloud tables and RLS policies. It does NOT migrate localStorage data or connect attendance.html by itself.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  role text not null default 'student' check (role in ('admin','teacher','student')),
  created_at timestamptz not null default now()
);

create table if not exists public.students (
  id uuid primary key default gen_random_uuid(),
  student_code text not null unique,
  full_name text not null,
  year text not null default '',
  branch text not null default '',
  user_id uuid unique references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.subjects (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  year text not null default '',
  branch text not null default '',
  teacher_id uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table if not exists public.attendance_sessions (
  id uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id) on delete cascade,
  attendance_date date not null default current_date,
  slot text not null default 'Lecture 1',
  created_by uuid not null default auth.uid() references public.profiles(id),
  created_at timestamptz not null default now(),
  unique (subject_id, attendance_date, slot)
);

create table if not exists public.attendance_records (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.attendance_sessions(id) on delete cascade,
  student_id uuid not null references public.students(id) on delete cascade,
  status text not null check (status in ('present','absent','leave','medical','od')),
  created_at timestamptz not null default now(),
  unique (session_id, student_id)
);

create index if not exists students_user_id_idx on public.students(user_id);
create index if not exists subjects_teacher_id_idx on public.subjects(teacher_id);
create index if not exists sessions_subject_date_idx on public.attendance_sessions(subject_id, attendance_date);
create index if not exists records_student_id_idx on public.attendance_records(student_id);

-- Helper functions avoid recursive RLS policies on profiles.
create or replace function public.current_attendx_role()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select p.role from public.profiles p where p.id = (select auth.uid()) limit 1
$$;

create or replace function public.attendx_is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(public.current_attendx_role() = 'admin', false)
$$;

create or replace function public.attendx_teacher_has_subject(p_subject_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.subjects s
    where s.id = p_subject_id and s.teacher_id = (select auth.uid())
  )
$$;

create or replace function public.attendx_teacher_can_access_student(p_student_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.students st
    join public.subjects su
      on (su.year = '' or su.year = st.year)
     and (su.branch = '' or lower(su.branch) = lower(st.branch))
    where st.id = p_student_id
      and su.teacher_id = (select auth.uid())
  )
$$;

alter table public.profiles enable row level security;
alter table public.students enable row level security;
alter table public.subjects enable row level security;
alter table public.attendance_sessions enable row level security;
alter table public.attendance_records enable row level security;

create policy "profiles_read_self_or_admin" on public.profiles
for select to authenticated
using (id = (select auth.uid()) or public.attendx_is_admin());

create policy "profiles_admin_update" on public.profiles
for update to authenticated
using (public.attendx_is_admin())
with check (public.attendx_is_admin());

create policy "students_read_scoped" on public.students
for select to authenticated
using (
  public.attendx_is_admin()
  or user_id = (select auth.uid())
  or (public.current_attendx_role() = 'teacher' and public.attendx_teacher_can_access_student(id))
);

create policy "students_admin_manage" on public.students
for all to authenticated
using (public.attendx_is_admin())
with check (public.attendx_is_admin());

create policy "subjects_read_scoped" on public.subjects
for select to authenticated
using (
  public.attendx_is_admin()
  or teacher_id = (select auth.uid())
  or exists (select 1 from public.students st where st.user_id = (select auth.uid()) and (subjects.year = '' or subjects.year = st.year) and (subjects.branch = '' or lower(subjects.branch) = lower(st.branch)))
);

create policy "subjects_admin_manage" on public.subjects
for all to authenticated
using (public.attendx_is_admin())
with check (public.attendx_is_admin());

create policy "sessions_read_scoped" on public.attendance_sessions
for select to authenticated
using (
  public.attendx_is_admin()
  or public.attendx_teacher_has_subject(subject_id)
  or exists (
    select 1 from public.attendance_records ar
    join public.students st on st.id = ar.student_id
    where ar.session_id = attendance_sessions.id and st.user_id = (select auth.uid())
  )
);

create policy "sessions_admin_or_assigned_teacher_insert" on public.attendance_sessions
for insert to authenticated
with check (
  public.attendx_is_admin()
  or (created_by = (select auth.uid()) and public.attendx_teacher_has_subject(subject_id))
);

create policy "sessions_admin_or_assigned_teacher_update" on public.attendance_sessions
for update to authenticated
using (public.attendx_is_admin() or public.attendx_teacher_has_subject(subject_id))
with check (public.attendx_is_admin() or public.attendx_teacher_has_subject(subject_id));

create policy "sessions_admin_or_assigned_teacher_delete" on public.attendance_sessions
for delete to authenticated
using (public.attendx_is_admin() or public.attendx_teacher_has_subject(subject_id));

create policy "records_read_scoped" on public.attendance_records
for select to authenticated
using (
  public.attendx_is_admin()
  or public.attendx_teacher_has_subject((select ses.subject_id from public.attendance_sessions ses where ses.id = session_id))
  or exists (select 1 from public.students st where st.id = student_id and st.user_id = (select auth.uid()))
);

create policy "records_admin_or_assigned_teacher_insert" on public.attendance_records
for insert to authenticated
with check (
  public.attendx_is_admin()
  or (
    public.attendx_teacher_has_subject((select ses.subject_id from public.attendance_sessions ses where ses.id = session_id))
    and public.attendx_teacher_can_access_student(student_id)
  )
);

create policy "records_admin_or_assigned_teacher_update" on public.attendance_records
for update to authenticated
using (
  public.attendx_is_admin()
  or (
    public.attendx_teacher_has_subject((select ses.subject_id from public.attendance_sessions ses where ses.id = session_id))
    and public.attendx_teacher_can_access_student(student_id)
  )
)
with check (
  public.attendx_is_admin()
  or (
    public.attendx_teacher_has_subject((select ses.subject_id from public.attendance_sessions ses where ses.id = session_id))
    and public.attendx_teacher_can_access_student(student_id)
  )
);

create policy "records_admin_or_assigned_teacher_delete" on public.attendance_records
for delete to authenticated
using (
  public.attendx_is_admin()
  or (
    public.attendx_teacher_has_subject((select ses.subject_id from public.attendance_sessions ses where ses.id = session_id))
    and public.attendx_teacher_can_access_student(student_id)
  )
);

-- New Supabase Auth accounts start as students. Promote the first admin manually
-- from SQL Editor after creating that account; never let public sign-up choose admin.
create or replace function public.attendx_create_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', ''), 'student')
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger attendx_auth_user_created
after insert on auth.users
for each row execute procedure public.attendx_create_profile();

grant usage on schema public to authenticated;
grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.students to authenticated;
grant select, insert, update, delete on public.subjects to authenticated;
grant select, insert, update, delete on public.attendance_sessions to authenticated;
grant select, insert, update, delete on public.attendance_records to authenticated;
grant execute on function public.current_attendx_role() to authenticated;
grant execute on function public.attendx_is_admin() to authenticated;
grant execute on function public.attendx_teacher_has_subject(uuid) to authenticated;
grant execute on function public.attendx_teacher_can_access_student(uuid) to authenticated;
