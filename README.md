# SAVA Technical Institute — Next.js + Supabase

Production foundation for the SAVA portal: **Next.js 14 (App Router) · TypeScript · Tailwind · Supabase** with real authentication, four roles, and database-backed features protected by Row-Level Security (RLS).

This is **Stage 1** of porting the prototype into a real app. What's wired end-to-end today:

- 🔐 **Auth** — sign up / sign in / sign out (Supabase Auth)
- 🧑‍🤝‍🧑 **4 roles** — `super_admin`, `admin`, `teacher`, `student`, with protected routes
- 👤 **Profile** — every user edits their own details
- 🗂️ **People** — admins manage everyone (roles, department, year)
- 📣 **Announcements** — staff post; everyone sees the ones meant for them
- 🛡️ **Database + RLS** — security rules so users only touch what they should

The schema also already includes tables for **subjects, grades, finance, payments, attendance, and the academic calendar** — those screens get built in the next stages.

---

## 1. Prerequisites

- Node.js 18.18+ (or 20+)
- Your Supabase project (already created)

## 2. Environment

`.env.local` is already filled in with your project URL and **publishable** key:

```
NEXT_PUBLIC_SUPABASE_URL=https://hptjmpvhkaigmjmosyyp.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=sb_publishable_...
```

> The publishable key is safe to ship to the browser — it's protected by RLS.
> Keep your **secret / service_role** key private; this app never needs it.

## 3. Create the database

1. Open Supabase → **SQL Editor**.
2. Paste the entire contents of [`supabase/schema.sql`](supabase/schema.sql) and click **Run**.
   It creates the tables, the role helpers, RLS policies, and the trigger that
   makes a profile automatically whenever someone signs up. It's safe to re-run.

## 4. Turn off email confirmation (for quick testing)

By default Supabase makes new users confirm their email before they can sign in.
For local testing: Supabase → **Authentication → Providers → Email** → turn **Confirm email** off.
(Leave it on in production and let users confirm via the emailed link.)

## 5. Run it

```bash
npm install
npm run dev
```

Open http://localhost:3000 → you'll be sent to **/login**. Click **Create an account**
and sign up (as student or teacher).

## 6. Make yourself the Super Admin

Self-signup can only create students/teachers (so nobody promotes themselves).
After signing up, run this once in the SQL Editor (use your email):

```sql
update public.profiles p
set role = 'super_admin'
from auth.users u
where u.id = p.id and u.email = 'you@example.com';
```

Sign out and back in — you'll now have the **People** screen and full access.

---

## Project structure

```
src/
  app/
    login/ signup/            Auth pages
    dashboard/
      layout.tsx              Shell + top nav (role-aware)
      admin|teacher|student|super-admin/   Role home pages
      profile/                Edit your own profile  ✅ wired
      people/                 Admin: manage everyone ✅ wired
      announcements/          Post + read notices     ✅ wired
  components/                 SignOutButton, DashboardNav
  lib/
    supabase/                 Browser + server + middleware clients
    auth.ts                   getSessionProfile(), requireRole()
    types.ts                  Role, Profile, helpers, departments
middleware.ts                 Refreshes session + guards /dashboard
supabase/schema.sql           Tables + RLS + triggers (run this)
```

## How the security works

- Every signed-in user can **read** profiles (needed for lists/chat later).
- A user can edit **their own** profile, but the DB blocks them from changing
  their own **role / department / year** — only admins can (enforced by a trigger,
  not just the UI).
- Staff-only tables (announcements, subjects, attendance…) reject writes from
  students at the database level via `is_staff()` / `is_admin()` policies.
- Students can read **only their own** grades, finance, and attendance rows.

## Deploying

Push to GitHub and import into **Vercel**. Add the two `NEXT_PUBLIC_SUPABASE_*`
variables in Vercel → Project → Settings → Environment Variables. That's it.

---

## What's next (later stages)

Subjects & GPA · Attendance (with QR) · Finance & payroll · Timetable ·
Academic calendar UI · Messaging & friends · Documents (ID card, receipts, letters) ·
Super-Admin control center. We port these onto this foundation one feature at a time.
