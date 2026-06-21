-- ============================================================
-- SAVA Technical Institute — database schema
-- Paste this whole file into Supabase → SQL Editor → Run.
-- It is idempotent: safe to run again after edits.
-- ============================================================

-- ----- Clean slate ------------------------------------------
-- Removes any half-created tables from an earlier attempt so
-- this script always rebuilds cleanly. Safe before real data.
drop table if exists public.attendance       cascade;
drop table if exists public.payments         cascade;
drop table if exists public.finance_accounts cascade;
drop table if exists public.grades           cascade;
drop table if exists public.subjects         cascade;
drop table if exists public.calendar_events  cascade;
drop table if exists public.announcements    cascade;
drop table if exists public.profiles         cascade;
drop function if exists public.handle_new_user()        cascade;
drop function if exists public.protect_profile_fields() cascade;
drop function if exists public.is_admin() cascade;
drop function if exists public.is_staff() cascade;
drop type if exists public.user_role cascade;

create extension if not exists pgcrypto;

-- ----- Role type --------------------------------------------
do $$ begin
  create type public.user_role as enum ('super_admin', 'admin', 'teacher', 'student');
exception when duplicate_object then null; end $$;

-- ----- Profiles (1:1 with auth.users) -----------------------
create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text,
  role        public.user_role not null default 'student',
  department  text,
  year        int,
  created_at  timestamptz not null default now()
);

alter table public.profiles add column if not exists email         text;
alter table public.profiles add column if not exists phone         text;
alter table public.profiles add column if not exists blood         text;
alter table public.profiles add column if not exists photo_url     text;
alter table public.profiles add column if not exists phone_privacy text default 'staff';

alter table public.profiles enable row level security;

-- ----- Role helpers (SECURITY DEFINER avoids RLS recursion) -
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles
                 where id = auth.uid() and role in ('admin','super_admin'));
$$;

create or replace function public.is_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles
                 where id = auth.uid() and role in ('admin','super_admin','teacher'));
$$;

-- ----- Profiles policies ------------------------------------
-- Read: any signed-in user (needed for people lists, chat, etc.)
drop policy if exists "profiles_select_authenticated" on public.profiles;
create policy "profiles_select_authenticated"
  on public.profiles for select to authenticated using (true);

-- Update own row...
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own"
  on public.profiles for update to authenticated
  using (auth.uid() = id) with check (auth.uid() = id);

-- ...or any row if you are an admin.
drop policy if exists "profiles_update_admin" on public.profiles;
create policy "profiles_update_admin"
  on public.profiles for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- Stop non-admins from promoting themselves: lock role/department/year
-- to their previous values unless the caller is an admin.
create or replace function public.protect_profile_fields()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    new.role := old.role;
    new.department := old.department;
    new.year := old.year;
  end if;
  return new;
end;
$$;
drop trigger if exists protect_profile_fields_trg on public.profiles;
create trigger protect_profile_fields_trg
  before update on public.profiles
  for each row execute function public.protect_profile_fields();

-- ----- Auto-create a profile on signup ----------------------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  requested_role public.user_role;
begin
  begin
    requested_role := (new.raw_user_meta_data->>'role')::public.user_role;
  exception when others then
    requested_role := 'student';
  end;
  -- Self-signup may only be student or teacher.
  if requested_role is null or requested_role in ('admin','super_admin') then
    requested_role := 'student';
  end if;

  insert into public.profiles (id, email, full_name, role, department, year, phone_privacy)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data->>'full_name',
    requested_role,
    new.raw_user_meta_data->>'department',
    nullif(new.raw_user_meta_data->>'year', '')::int,
    'staff'
  );
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ----- Announcements ----------------------------------------
create table if not exists public.announcements (
  id            uuid primary key default gen_random_uuid(),
  title         text not null,
  body          text not null default '',
  audience_dept text,   -- null = whole institute
  audience_year int,    -- null = all years
  created_by    uuid references public.profiles(id) on delete set null,
  created_at    timestamptz not null default now()
);
alter table public.announcements enable row level security;
drop policy if exists "ann_select" on public.announcements;
create policy "ann_select" on public.announcements for select to authenticated using (true);
drop policy if exists "ann_write" on public.announcements;
create policy "ann_write" on public.announcements for all to authenticated
  using (public.is_staff()) with check (public.is_staff());

-- ----- Subjects ---------------------------------------------
create table if not exists public.subjects (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  department   text not null,
  year         int not null,
  exam_weights jsonb not null default '{"quiz":10,"midterm":25,"final":40,"practical":25}'::jsonb,
  created_at   timestamptz not null default now()
);
alter table public.subjects enable row level security;
drop policy if exists "subj_select" on public.subjects;
create policy "subj_select" on public.subjects for select to authenticated using (true);
drop policy if exists "subj_write" on public.subjects;
create policy "subj_write" on public.subjects for all to authenticated
  using (public.is_staff()) with check (public.is_staff());

-- ----- Grades -----------------------------------------------
create table if not exists public.grades (
  id         uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  quiz       numeric,
  midterm    numeric,
  final      numeric,
  practical  numeric,
  updated_at timestamptz not null default now(),
  unique (subject_id, student_id)
);
alter table public.grades enable row level security;
drop policy if exists "grades_select" on public.grades;
create policy "grades_select" on public.grades for select to authenticated
  using (student_id = auth.uid() or public.is_staff());
drop policy if exists "grades_write" on public.grades;
create policy "grades_write" on public.grades for all to authenticated
  using (public.is_staff()) with check (public.is_staff());

-- ----- Finance ----------------------------------------------
create table if not exists public.finance_accounts (
  user_id    uuid primary key references public.profiles(id) on delete cascade,
  total      numeric not null default 0,
  updated_at timestamptz not null default now()
);
create table if not exists public.payments (
  id      uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  amount  numeric not null,
  note    text,
  paid_at timestamptz not null default now()
);
alter table public.finance_accounts enable row level security;
alter table public.payments enable row level security;
drop policy if exists "fin_select" on public.finance_accounts;
create policy "fin_select" on public.finance_accounts for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
drop policy if exists "fin_write" on public.finance_accounts;
create policy "fin_write" on public.finance_accounts for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
drop policy if exists "pay_select" on public.payments;
create policy "pay_select" on public.payments for select to authenticated
  using (user_id = auth.uid() or public.is_admin());
drop policy if exists "pay_write" on public.payments;
create policy "pay_write" on public.payments for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ----- Attendance -------------------------------------------
create table if not exists public.attendance (
  id         uuid primary key default gen_random_uuid(),
  subject_id uuid not null references public.subjects(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  date       date not null,
  status     text not null check (status in ('present','late','absent')),
  unique (subject_id, student_id, date)
);
alter table public.attendance enable row level security;
drop policy if exists "att_select" on public.attendance;
create policy "att_select" on public.attendance for select to authenticated
  using (student_id = auth.uid() or public.is_staff());
drop policy if exists "att_write" on public.attendance;
create policy "att_write" on public.attendance for all to authenticated
  using (public.is_staff()) with check (public.is_staff());

-- ----- Academic calendar ------------------------------------
create table if not exists public.calendar_events (
  id         uuid primary key default gen_random_uuid(),
  title      text not null,
  type       text not null default 'event' check (type in ('exam','holiday','event')),
  start_date date not null,
  end_date   date,
  dept       text,  -- null = whole institute
  year       int,   -- null = all years
  note       text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table public.calendar_events enable row level security;
drop policy if exists "cal_select" on public.calendar_events;
create policy "cal_select" on public.calendar_events for select to authenticated using (true);
drop policy if exists "cal_write" on public.calendar_events;
create policy "cal_write" on public.calendar_events for all to authenticated
  using (public.is_staff()) with check (public.is_staff());

-- ============================================================
-- After signing up your own account, promote it to Super Admin
-- (replace the email):
--
--   update public.profiles p
--   set role = 'super_admin'
--   from auth.users u
--   where u.id = p.id and u.email = 'you@example.com';
-- ============================================================
