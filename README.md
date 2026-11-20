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

   In sample mode (no keys), any number works with code 123456, and a requested
   sample mechanic "accepts" after 15 seconds so the waiting screen can be tried.

## Put it online for testing (Netlify)

So any phone or computer can open the app against the cloud backend.

One-time setup:

```
npm install -g netlify-cli
netlify login
copy deploy.env.example deploy.env     # then fill in the URL and publishable key
```

Publish (run again for every new version):

```
dart run tool/deploy_web.dart
```

The first run asks which Netlify site to use: choose "Create & configure a new
project". Add `--draft` for a preview link that does not replace the live site.

**Test sign-in codes.** While the mock SMS hook is on, nobody gets a text. Open
`https://<your-site>/?testcodes=<key>` to see the latest codes; the page updates by
itself. Only the hash of the key is stored (`dev_settings`); the top of
`supabase/migrations/20261113000000_dev_codes_link.sql` says how to change the key or
switch the link off. Anyone with the link can sign in as any number, so share it only
with testers you trust, and switch it off before launch.

Never put the `service_role` key in the app.

## What is built (Phase 1, owner side)

- Home: one dark card with **Find me a mechanic**, then **Browse and call a
  mechanic**; location from GPS or a picked Nairobi zone; an **Accident or
  unsafe location?** link with 999, 112 and Kenya Red Cross 1199
- Browse: verified providers ranked by real availability, then distance. Each
  card shows how fresh the status is, what was checked in plain words, the fee
  and what it covers, and Call
- Tap to call through the phone dialer; the tap is logged, the call is not
- Provider profile showing exactly what was verified
- Find me a mechanic: come to me / drive to a garage, optional note, best match.
  Nothing is sent until the owner taps **Request this mechanic**
- Waiting screen: updates itself when the mechanic accepts or passes; suggests
  someone else after 5 minutes; the owner can call or cancel at any point
- **My repair** on the home screen leads back to an open request
- Stale "Available" shows as "Availability not confirmed"
- Design rules and colours: `docs/DESIGN.md`
- Database: tables, `nearby_providers` PostGIS function, row-level security
- No self-onboarding. An admin adds every garage, mobile mechanic and parts
  shop in the admin console, with the phone numbers of the people who work
  there. A person signs in ("For mechanics, garages and parts shops" on the
  home screen) with that number and is linked to what they were added to. A
  number nobody added sees "This number is not registered" and nothing else.
- Mechanic side: the Available / Busy / Offline switch. "Available" expires
  after 4 hours, set by the server clock.

- Verification documents: the admin (or the provider) uploads ID photos to a
  private storage bucket; only the provider and admins can open them
- Admin console: two tabs. **Mechanics & garages**: add one, tick each check,
  approve or pause it, add helpers under People. **Parts shops**: add a shop
  and its owner, add workers, pause a shop. Nobody can be approved before the
  identity check is passed. Switching a person off removes their access. To
  make an admin, see the top of `supabase/migrations/20261111000000_verification_admin.sql`.
- Spare parts marketplace, trade only: approved garages and mechanics (and
  their helpers) search parts by name, number and car make, nearest shop
  first, call the shop or order. Shops (owners and workers) list parts with
  price, stock and fitment, and move orders on: confirmed → ready → collected.
  The shop's Orders tab checks for new orders every 30 seconds and shows how
  many are waiting.
  Stock is held when an order is placed and given back if it is cancelled.
  Payment is between buyer and shop for now. Car owners and guests never see
  any of it; the database refuses them.
- Sample mode numbers (code 123456): 0700 000 000 admin, 0711 000 001 a live
  mechanic, 0711 000 002 a parts shop. What the admin adds in sample mode can
  be signed in to straight away.

- Find me a mechanic accepts an optional photo and a voice note (up to 60
  seconds), stored privately; only the sender, the assigned mechanic and admins
  can open them.

- Mechanic inbox: an approved mechanic sees the requests sent to them, newest
  first, with the note, photo and voice note. They tap **I'll take it** or
  **I can't take it**. Passing frees the request and the mechanic loses access
  to its files; it can never be sent back to them. Owners can now only cancel
  a request, not edit it.
- Re-matching: when a mechanic passes, the database sends the request on to
  the next best free mechanic (approved, identity checked, not busy or
  offline, within reach; available first, then nearest), at most three times.
  The owner's waiting screen says who has it now and restarts its timer. Only
  when nobody fits does the owner see mechanics nearby. After 5 minutes with no
  answer, the waiting screen has the request sent on the same way.
- Limits: at most 2 open requests and 6 a day per account; a mechanic with 5
  waiting requests gets no more. The owner is told plainly and can still call.
- Quotes: on a job they took, the mechanic sends lines of labour, parts and other
  costs; the owner sees them on My repair and taps Approve or Decline. A new quote
  replaces one not yet answered. The mechanic gets a text when the owner answers.
- Text alerts: a mechanic getting a request, a shop getting an order, and a
  buyer whose order is confirmed, ready or cancelled get a text. Texts queue in
  `sms_outbox`; nothing sends them until an SMS provider is connected. Testers
  see them on the test codes page.

## Test the database rules

`supabase/tests/run.sh` builds a fresh local database (Postgres with PostGIS),
adds a small stand-in for Supabase auth and storage, applies every migration,
then runs every `*_test.sql`. Any broken rule stops it with `FAIL: ...`.

```
supabase/tests/run.sh
```

## Not built yet

- Phone sign-in for owners, M-Pesa payments, reviews (Phase 2)
- Paying for parts in the app, delivery, push or SMS alerts for new orders

## Layout

```
lib/models/      ServiceProvider and enums
lib/data/        repositories (Supabase + sample), launch zones
lib/state/       Riverpod providers, location, matching rules
lib/ui/          screens and widgets
supabase/        migrations, seed SQL, and SQL rule tests
test/            ranking, owner, mechanic, inbox, admin, parts and layout tests
```

## Checks on GitHub

`.github/workflows/ci.yml` runs on every push and pull request: `flutter analyze` and
`flutter test` (sample data), and every migration plus every access-rule test on
Postgres with PostGIS (`supabase/tests/run.sh`). It needs no secrets and never touches
the live Supabase project.
