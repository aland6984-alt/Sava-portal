-- ============================================================
-- SAVA Portal — Timetable (weekly class schedule)
-- Run this in Supabase → SQL Editor → New query → Run.
-- Safe to run more than once.
-- ============================================================

create table if not exists public.timetable (
  id          uuid primary key default gen_random_uuid(),
  department  text not null,
  year        int  not null,
  day_of_week int  not null,        -- 0 = Saturday ... 6 = Friday
  start_time  text not null,        -- "08:00"
  end_time    text not null,        -- "09:30"
  subject     text not null,
  teacher     text,
  room        text,
  created_at  timestamptz default now()
);

alter table public.timetable enable row level security;

drop policy if exists "tt_select" on public.timetable;
drop policy if exists "tt_write"  on public.timetable;

-- Everyone signed in can read (students see their class via the app).
create policy "tt_select" on public.timetable
  for select to authenticated using (true);

-- Teachers and admins can add/edit/delete.
create policy "tt_write" on public.timetable
  for all to authenticated
  using (public.is_staff()) with check (public.is_staff());
