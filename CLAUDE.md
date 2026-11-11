# fundi

Read `docs/PROJECT_CONTEXT.md` for what this is and the decisions already made, and
`docs/PROJECT_INSTRUCTIONS.md` for the working rules.

## Commands

```
flutter pub get
flutter analyze
flutter test
flutter run -d chrome          # sample data, no backend needed
flutter build web --release
```

## Layout

- `lib/models` data classes and enums
- `lib/data` repositories: each has a Supabase and a Sample implementation
- `lib/state` Riverpod providers, location, matching rules
- `lib/ui` screens
- `supabase/migrations` SQL, applied in file-name order
- `test/widget_test.dart` ranking, owner, mechanic and admin journeys

## Conventions

- New backend calls go behind a repository interface with a Sample implementation, so
  the app and tests run without a backend.
- Device features (dialer, GPS, camera, microphone) are Riverpod providers that tests override.
- Access rules live in SQL. Test them against a local Postgres before shipping a migration.
