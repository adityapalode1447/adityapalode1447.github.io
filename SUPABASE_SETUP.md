# AttendX Cloud setup

This repository uses GitHub Pages for static hosting. Supabase provides the shared database and authentication.

## Important
- Running `supabase-schema.sql` creates tables and Row Level Security (RLS) policies only. It does not automatically change `attendance.html` or migrate its existing browser-local data.
- Do not commit database passwords, Supabase secret keys, service-role keys, or backup JSON files. The existing app's backup contains account password hashes and must remain private.
- The browser app must use only the project's publishable key (or legacy anon key) with RLS enabled.
- The existing `attendance.html` uses custom localStorage/sessionStorage authentication. It must be migrated to Supabase Auth and rewritten to use the cloud tables before cross-device sync works. Do not rely on localStorage accounts as cloud authentication.

## Setup
1. In Supabase Dashboard, open SQL Editor and create a new query.
2. Copy the complete contents of `supabase-schema.sql`, run it, and check for errors.
3. Create your own account through the future Supabase Auth login screen.
4. To promote your own account to admin, first find your auth user UUID in Authentication > Users. Then run this SQL in SQL Editor, replacing the UUID:
   `update public.profiles set role = 'admin' where id = 'YOUR-AUTH-USER-UUID';`
   Never expose an admin-promotion flow to public signup.
5. The future HTML integration will require the Project URL and publishable key. These are not the database password or service-role key.

## Tables
- `profiles`: account roles linked to Supabase Auth
- `students`: student details and optional account linkage
- `subjects`: subject/class scope and assigned teacher
- `attendance_sessions`: date/slot per subject
- `attendance_records`: one status per student per session

## Existing data
Download a private JSON backup from the current AttendX app before changing it. It must be imported with a one-time migration after the cloud app is ready. Never upload that backup to this public repository.
