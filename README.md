# Fundi (codename)

"My car has a problem. Connect me with a verified mechanic who can sort it out."

The owner app has two buttons: **Find me a mechanic** and **Browse and call**.
No sign-up, no repair categories. The mechanic diagnoses the car.

`fundi` is a working codename. The Android/iOS package ID is `ke.co.fundi.fundi`;
change it before the first store release, because it cannot change afterwards.

New here? Read `docs/PROJECT_CONTEXT.md` first.

## Run it

```
flutter pub get
flutter run            # phone or emulator
flutter run -d chrome  # browser
flutter test
```

With no keys, the app runs on built-in sample mechanics (a yellow banner says so).

## Connect the real backend (Supabase)

1. Create a free project at supabase.com.
2. In the SQL editor, run every file in `supabase/migrations/` in name order.
   For test data only, also run `supabase/seed.sql` (invented providers).
3. In Authentication → Sign In / Providers, turn on **Anonymous sign-ins**
   (used so a guest can send a "Find me a mechanic" request).
4. Run the app with your project's URL and publishable (anon) key:

```
flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co --dart-define=SUPABASE_ANON_KEY=xxxx
```

5. For mechanic sign-in, turn on **Phone** sign-in (Authentication → Sign In / Providers → Phone).
   - **During development** no SMS provider is needed: in Authentication → Auth Hooks, add a
     **Send SMS** hook of type Postgres, schema `public`, function `mock_send_sms`. Codes are then
     stored, not sent. Read the latest one in the SQL editor:
     `select phone, otp, created_at from public.dev_sms_outbox order by created_at desc limit 5;`
   - **Before launch**, switch that hook off and connect a real SMS provider. While the hook is
     on, no real person can receive a sign-in code.

   In sample mode (no keys), any number works with code 123456.

Never put the `service_role` key in the app.

## What is built (Phase 1, owner side)

- Home with the two actions; location from GPS or a picked Nairobi zone
- Browse: verified providers ranked by real availability, then distance; filters
- Tap to call through the phone dialer; the tap is logged, the call is not
- Provider profile showing exactly what was verified
- Find me a mechanic: come to me / go to a garage, optional note, best match
- Stale "Available" shows as "Availability not confirmed"
- Database: tables, `nearby_providers` PostGIS function, row-level security
- Mechanic side ("I'm a mechanic or garage" on the home screen): phone sign-in,
  listing application, and the Available / Busy / Offline switch. "Available"
  expires after 4 hours, set by the server clock.

- Verification documents: a provider uploads ID photos to a private storage
  bucket; only the provider and admins can open them
- Admin console: sign in as an admin, tick each check, approve or pause a
  listing. Nobody can be approved before the identity check is passed. To make
  an admin, see the top of `supabase/migrations/20261111000000_verification_admin.sql`.
  In sample mode, sign in as 0700 000 000 with code 123456.

- Find me a mechanic accepts an optional photo and a voice note (up to 60
  seconds), stored privately; only the sender, the assigned mechanic and admins
  can open them.

- Mechanic inbox: an approved mechanic sees the requests sent to them, newest
  first, with the note, photo and voice note. They tap **I'll take it** or
  **I can't take it**. Passing frees the request and the mechanic loses access
  to its files; it can never be sent back to them. Owners can now only cancel
  a request, not edit it.

## Test the database rules

`supabase/tests/run.sh` builds a fresh local database (Postgres with PostGIS),
adds a small stand-in for Supabase auth and storage, applies every migration,
then runs every `*_test.sql`. Any broken rule stops it with `FAIL: ...`.

```
supabase/tests/run.sh
```

## Not built yet

- Phone sign-in for owners, quotes, M-Pesa payments, reviews (Phase 2)
- Mechanic-only parts marketplace (Phase 3)

## Layout

```
lib/models/      ServiceProvider and enums
lib/data/        repositories (Supabase + sample), launch zones
lib/state/       Riverpod providers, location, matching rules
lib/ui/          screens and widgets
supabase/        migrations, seed SQL, and SQL rule tests
test/            ranking, owner, mechanic, inbox and admin tests
```
