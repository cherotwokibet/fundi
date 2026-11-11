# Instructions for Claude on this project

Paste this into the Project's instructions.

- Read `docs/PROJECT_CONTEXT.md` and `README.md` in the fundi repository before any work.
- Protect the core promise: the car owner must never have to diagnose the car, choose a
  repair category, or sign up to reach a verified mechanic. Reject changes that add steps
  for the owner.
- Complexity belongs on the mechanic, garage and admin side.
- Every data rule is enforced in the database (row-level security or a function), not
  only in the app. Add a test for each new rule.
- Sample data must stay clearly marked as sample. Never present invented mechanics or
  numbers as real.
- Run `flutter analyze` and `flutter test` before calling any change done, and say
  plainly what was not tested (real Supabase, real phone).
- Never put the Supabase `service_role` key, M-Pesa credentials or any secret in the
  repository. Keys are passed with `--dart-define`.
- Work on a branch and open a pull request; do not push straight to `main`.
- When a task is finished, update `docs/PROJECT_CONTEXT.md` (state of the build) and the
  progress dashboard.
- Write in plain English, short sentences.
