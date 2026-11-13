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
- Spare parts will be a **mechanic-only B2B marketplace** (Phase 3). Owners never see a parts catalogue.
- Insurance is an optional later pathway, not part of the MVP.
- Paying in the app is optional for the owner; money is held until the job is confirmed (Phase 2).
- Stack: Flutter (one codebase) + Supabase (Postgres, PostGIS, Auth, Storage). Payments: IntaSend first, own Daraja paybill later.
- "Available" expires after 4 hours on the server clock; stale status shows as "Availability not confirmed".
- Nobody is shown to owners, or approved, before the identity check is passed.

## Phases

1. **Find and call** — owner app, mechanic sign-up and availability, verification, admin console.
2. **Match, quote, pay** — owner phone sign-in, live matching, itemised quotes, M-Pesa, reviews, complaints.
3. **Parts for mechanics** — supplier portal, fitment, mechanic ordering.

Gates: 90 verified providers live before Phase 2; 300 paid jobs in the pilot before Phase 3.

## State of the build (12 Nov 2026)

Built and covered by tests (29 passing), on sample data:
owner home, browse, tap to call, mechanic profile, find-me best match with optional photo
and voice note, mechanic phone sign-in, listing application, document upload,
availability switch, admin console, mechanic inbox (note, photo, voice note, take or pass).

Owner app redesign (12 Nov): forest green and lime look, main button low on the screen,
confirm before a request is sent, waiting screen, My repair, safety sheet with emergency
numbers. Responsive: one column on phones, two columns from 900 px wide (13 Nov).
Rules are in `docs/DESIGN.md`; the proposal with research is at
https://claude.ai/artifact/SngcAzUst8vE8KrQKrBQrU. Mechanic and admin screens took the new
colours but not new layouts.

Database: seven migrations in `supabase/migrations/`. The access rules are tested on a
local Postgres with a stand-in for Supabase auth and storage: `supabase/tests/run.sh`
(three SQL test files: inbox rules, mock SMS, owner request status).

**Supabase project:** `lfgpmngtlypwyvpqytrz` (Frankfurt, free plan), URL
`https://lfgpmngtlypwyvpqytrz.supabase.co`. All seven migrations applied by 12 Nov 2026 and
the access rules checked in the live database. It holds test data only: one admin and one test mechanic (Kowino Mechs). Anonymous sign-ins are on. Phone sign-in uses a development-only mock
(`mock_send_sms`): codes are stored in `dev_sms_outbox`, not sent. Switch it off before launch. The public key is passed
with `--dart-define`; it is not stored in the repo.

**Proven on the live project (11 Nov, web):** anonymous and phone sign-in, listing
application, document upload to private storage, admin approval.

**Not yet proven:** the redesigned owner flow and the inbox against the live project
(request with photo and voice note, accept, waiting screen), signed links for files,
voice-note playback on a real phone, any Android or iOS build, and real owners using it
outdoors.

**Known gaps:** a passed-on request is not re-matched automatically yet (an admin can re-send it
in the database). Owners give no phone number, so the mechanic waits for the owner's call.
Nothing limits how many requests a guest can send.

**Next build items:** test the owner flow with five car owners on their own phones; then
Phase 2, starting with owner phone sign-in and live matching (re-send a passed-on request
to the next best match).

**Waiting on the owner of the project:** in Supabase, turn on phone sign-in and the mock
SMS hook (development only; a real SMS provider before launch), and make the first admin; pick the brand name
and package ID, test on a real Android phone, run the owner and mechanic interviews,
choose launch zones, register with the Data Protection Commissioner.

## Where things live

- Code: this repository. Setup steps are in `README.md`.
- Implementation plan: https://claude.ai/artifact/Hvbn4bXyzvgFsQaX8XJn7q
- Progress dashboard: https://claude.ai/artifact/7RE9zYSX2GfwGLNPW1inWW
- Local folder: `C:\Users\bcherotwo\StudioProjects\fundi`
