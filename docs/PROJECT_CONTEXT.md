# Fundi — project context

Read this first when picking the project up in a new session or on another machine.

## What it is

A platform that connects car owners with verified mechanics and garages in Nairobi.
`fundi` is a working codename; the brand name is not chosen yet.

**Core promise:** "My car has a problem. Connect me with a verified mechanic who can sort it out."
The owner never diagnoses the car, picks a repair category or signs up to get help.
Every screen is tested against one question: does this make the owner do more?

## Decisions already made

- Two actions on the home screen: **Find me a mechanic** and **Browse and call**.
- Calling is never blocked by sign-up, booking or payment.
- The mechanic diagnoses, not the app. Note, photo and voice note are optional.
- **No self-onboarding (19 Nov 2026).** Only an admin adds garages, mobile mechanics and parts
  shops, with the phone numbers of their people. Signing in links a person to what they were
  added to; an unknown number gets nothing. Sign-in itself stays open because car owners need it.
- Spare parts are a **trade-only marketplace**: only approved garages and mechanics (and their
  helpers), parts shop owners and workers, and admins can see it. Owners never see a parts catalogue.
  Built ahead of the Phase 3 gate at the project owner's request (19 Nov 2026).
- Insurance is an optional later pathway, not part of the MVP.
- Paying in the app is optional for the owner; money is held until the job is confirmed (Phase 2).
- Stack: Flutter (one codebase) + Supabase (Postgres, PostGIS, Auth, Storage). Payments: IntaSend first, own Daraja paybill later.
- "Available" expires after 4 hours on the server clock; stale status shows as "Availability not confirmed".
- Nobody is shown to owners, or approved, before the identity check is passed.

## Phases

1. **Find and call** — owner app, admin onboarding of mechanics, availability, verification, admin console.
2. **Match, quote, pay** — owner phone sign-in, live matching, itemised quotes, M-Pesa, reviews, complaints.
3. **Parts for mechanics** — supplier portal, fitment, mechanic ordering.

Gates: 90 verified providers live before Phase 2; 300 paid jobs in the pilot before Phase 3.

## Portal redesign (20 Nov 2026, night)

The owner found the screens plain and hard to use, so every portal was redesigned
first: https://claude.ai/artifact/5SCfdYUeDtJ7zazmkbgevw (12 screens, research notes
in the chat). Order agreed: admin console first, then the owner app, garage and parts.

**Admin console rebuilt** (`lib/ui/admin_screen.dart`, `lib/ui/admin_overview.dart`):
- Laptop (1000 px and up): forest sidebar with counts on Mechanics & garages and
  Complaints; Parts catalogue and Sign out in it. Phone: tabs along the bottom.
- Opens on **Overview**: four number tiles (verified and live out of 90, waiting for
  checks, parts shops open, open complaints and refunds due) and a **Needs you** list
  whose buttons jump to the right section.
- Lists have a filter and the add button in one row, cards show initials and
  "x of y checks", and empty lists say what will appear there.
Not built from the design yet: live requests table, side-by-side detail view, search.

**Owner app restyled** (same flows and rules, no new steps):
- Home: a live "N checked mechanics free near you" pill in the hero (from the nearby
  list, only those marked Available), the safety tile says "Emergency numbers first",
  and on phones a row of three trust cards (ID-checked, Price first, We step in).
- My repair: a mechanic card (initials, name, ID checked, state in words) replaces the
  big round badge; once accepted, four steps show where the job is (sent, taken,
  price, approve and done).
- Quote: each line has its kind above it, a bold total, "Nothing is done until you
  approve", and full-width Approve (lime) and Decline buttons. Mechanics see the
  same line style.
Left out on purpose: the map and arrival time (no mechanic location is collected),
paying through Fundi (M-Pesa not built), and a bottom tab bar (the My repair button
in the header already does this without adding a step).

**Garage portal rebuilt (21 Nov 2026)** (same rules, `lib/ui/garage_screen.dart`
replaces the old inbox screen):
- Phone: a Today screen. A forest card on top with the name, Verified, and an
  Available / Busy / Offline switch ("Keep me on for 4 more hours" when available).
  New requests show right there with the owner's note, voice note and photo, and
  Take the job / Pass. Taken jobs are listed under Your jobs with where each stands
  (Write the price, Price sent, Approved, Done). Order spare parts sits below.
- One job: four-step bar (Taken, Price sent, Approved, Done), call the owner, what
  the owner said, any complaint and the one reply, Your price, and Job done.
- Laptop (1000 px and wider): availability on the left and a job board with five
  columns: New requests, Write the price, Waiting for owner, Working, Done, plus
  the money waiting for owners and approved.
Left out on purpose: the answer countdown and "Arrived" step (not tracked yet),
team members per job (garages have no staff assignment yet), and a bottom tab bar.
66 Flutter tests.

## Separate portal links (20 Nov 2026, evening)

Each kind of user has its own link on the same site (one Flutter build):
- `/` car owners. The home screen no longer has a trade link.
- `/admin` the Fundi team: admin console (mechanics, shops, complaints, parts view).
- `/garage` mechanics and garages: listing, availability, inbox, quotes, ordering parts.
- `/parts` parts shops: listings and incoming orders (the seller side of the marketplace).
A portal only opens its own screens. A number signed in on the wrong link gets
"This number is not for the …" and a button to the portal(s) it belongs to.
`netlify.toml` rewrites every path to `index.html`; the app uses path URLs
(`usePathUrlStrategy`); the first screen is a named route so the path stays in the address bar. 61 Flutter tests. Not yet deployed to fundi-test.netlify.app.

## State of the build (20 Nov 2026, later)

Every migration up to and including `20261122000000_complaints_refunds.sql` is applied
live (20 Nov). Job done and reviews turned out not to be live yet; it was applied the same
day, just before complaints. Several earlier migrations were run from the SQL editor, so
the live migration history does not list them; check for the objects, not the history.
Supabase grants every new table to `anon` and `authenticated` by default, which the local
test stub does not copy: a migration that limits columns must `revoke all` first.

**Complaints and refunds** (`20261122000000_complaints_refunds.sql`, own SQL test
`complaints_test.sql`). Applied live; access checked there (no table-level grants, no
access to the refund number). Not yet tried end to end in the live app.
- The owner taps "Report a problem" on My repair while a job is under way, or
  "Problem with the work by …?" on the home screen for 14 days after it is done. They say
  what went wrong in their own words; nothing else to pick. Once per job.
- "I want my money back" also asks for an M-Pesa number (owners are guests with no number
  on file). Only admins can read it; the mechanic and even the owner's own reads cannot.
- The mechanic sees the complaint on the job in their inbox, gets a text, and can answer once.
- Admins decide on a new Complaints tab: upheld or not, with a note both sides read. A refund
  needs an upheld complaint and is capped at what the job cost (approved quotes plus the
  call-out fee). Paying in the app is not built, so the admin sends the refund by M-Pesa and
  enters the code; the refund then shows as paid. The owner gets a text on their refund number.
- `job_payout_on_hold(request)` is true while a complaint is open or a refund is due. The
  M-Pesa step must check it before releasing held money to a mechanic.
56 Flutter tests, eleven SQL test files.

Next: M-Pesa through IntaSend once the sandbox keys arrive. Keys go into Supabase secrets
(Edge Function), never into the repo or `--dart-define`.

## State of the build (20 Nov 2026)

All migrations up to `20261120030000_sms_alerts.sql` are applied live (checked 20 Nov).
Branch `feature/admin-onboarding-parts` is on GitHub as PR #2; GitHub Actions (`ci.yml`)
runs the Flutter tests and the SQL rule tests on every push and passed on the PR.

Phase 2 started: **itemised quotes** (`20261121000000_quotes.sql`, own SQL test). On a job
they took, the mechanic sends lines of labour, parts and other costs; the owner sees them on
My repair and taps Approve or Decline, no sign-up. A new quote replaces one not yet answered;
extra work after approval is a new quote. The mechanic gets a text when the owner answers.
Quotes migration applied live (20 Nov).

**Job done and reviews** (`20261121010000_job_done_reviews.sql`, own SQL test): the mechanic
taps "Job done" (or the owner taps "The work is done"); the owner's home screen then asks
"How did they do?" — one tap on 1–5 stars, optional comment, skippable. One rating per job,
within 14 days; the listing's rating is worked out only from these. **Not yet applied live.**
51 Flutter tests, ten SQL test files.

## State of the build (19 Nov 2026, night)

Night of 19 Nov, three more migrations on the same branch:
- `20261120010000_pin_search_path.sql` (security advisor fix) — **applied live**.
- `20261120020000_request_limits_and_no_answer.sql` — per account at most 2 open requests and
  6 a day; a mechanic with 5 waiting gets no more; after 5 minutes with no answer the owner's
  waiting screen has the request sent on to the next free mechanic (server checks the time).
- `20261120030000_sms_alerts.sql` — texts queued in `sms_outbox` for: a mechanic getting a
  request, a shop getting an order, a buyer's order confirmed / ready / cancelled. Not sent
  yet; testers see them on the test codes page under "Text alerts".
All three are applied live (20 Nov). 46 Flutter tests and eight SQL test files pass.


Re-matching (migration `20261120000000_rematch_on_pass.sql`, own SQL test): a passed-on
request goes to the next best free mechanic by itself, up to three times; the owner's
waiting screen says who has it now. Parts: several parts from one shop in one order, and
the shop's Orders tab refreshes every 30 seconds with a count of new orders. 44 Flutter
tests and six SQL test files pass. Same branch, `feature/admin-onboarding-parts`.


Admin-only onboarding and the parts marketplace (19 Nov, branch `feature/admin-onboarding-parts`):
admin adds mechanics, garages and parts shops and their people; the listing application form
is gone; shops list parts and handle orders; mechanics search, call and order. Migration
`20261119000000_admin_onboarding_parts.sql` with its own SQL test file; 41 Flutter tests pass.
**Neither the 19 Nov nor the 20 Nov migration is applied to the live Supabase project yet.** Not tested against real Supabase or on a phone.

Built and covered by tests, on sample data:
owner home, browse, tap to call, mechanic profile, find-me best match with optional photo
and voice note, phone sign-in for trade people, admin onboarding, document upload,
availability switch, admin console, mechanic inbox (note, photo, voice note, take or pass),
parts search, ordering and shop order handling.

Owner app redesign (12 Nov): forest green and lime look, main button low on the screen,
confirm before a request is sent, waiting screen, My repair, safety sheet with emergency
numbers. Responsive: one column on phones, two columns from 900 px wide (13 Nov).
Rules are in `docs/DESIGN.md`; the proposal with research is at
https://claude.ai/artifact/SngcAzUst8vE8KrQKrBQrU. Mechanic and admin screens took the new
colours but not new layouts.

Database: nine migrations in `supabase/migrations/`. The access rules are tested on a
local Postgres with a stand-in for Supabase auth and storage: `supabase/tests/run.sh`
(five SQL test files: admin onboarding and parts, inbox rules, mock SMS, owner request
status, test codes link).

**Supabase project:** `lfgpmngtlypwyvpqytrz` (Frankfurt, free plan), URL
`https://lfgpmngtlypwyvpqytrz.supabase.co`. All eight migrations applied by 13 Nov 2026 and
the access rules checked in the live database. It holds test data only: one admin and one test mechanic (Kowino Mechs). Anonymous sign-ins are on. Phone sign-in uses a development-only mock
(`mock_send_sms`): codes are stored in `dev_sms_outbox`, not sent. Testers read them at
`<site>/?testcodes=<key>` (development only; the key is not in the repo). Switch both off
before launch.

**Web hosting for testing:** Netlify, published from the owner's PC with
`dart run tool/deploy_web.dart` (settings in `deploy.env`, not in git). The public key is passed
with `--dart-define`; it is not stored in the repo.

**Proven on the live project (11 Nov, web):** anonymous and phone sign-in, listing
application, document upload to private storage, admin approval.

**Not yet proven:** the redesigned owner flow and the inbox against the live project
(request with photo and voice note, accept, waiting screen), signed links for files,
voice-note playback on a real phone, any Android or iOS build, and real owners using it
outdoors.

**Known gaps:** a no-answer request is only sent on while the owner's waiting screen is
open (no server timer yet). Owners give no phone number, so the mechanic waits for the
owner's call.

**Parts marketplace gaps:** no in-app payment or delivery. SMS alerts are queued but nothing
sends them until a real SMS provider is connected (an Edge Function reading `sms_outbox`).

**Next build items:** apply the job-done/reviews migration live, M-Pesa payments (needs IntaSend sandbox keys), connect an SMS provider for sign-in codes and alerts, and onboard the first real
garage and parts shop through the admin console; test the owner flow with five car owners on their own phones; then
Phase 2, starting with owner phone sign-in and quotes.

**Waiting on the owner of the project:** in Supabase, turn on phone sign-in and the mock
SMS hook (development only; a real SMS provider before launch), and make the first admin; pick the brand name
and package ID, test on a real Android phone, run the owner and mechanic interviews,
choose launch zones, register with the Data Protection Commissioner.

## Where things live

- Code: this repository. Setup steps are in `README.md`.
- Implementation plan: https://claude.ai/artifact/Hvbn4bXyzvgFsQaX8XJn7q
- Progress dashboard: https://claude.ai/artifact/7RE9zYSX2GfwGLNPW1inWW
- Local folder: `C:\Users\bcherotwo\StudioProjects\fundi`
