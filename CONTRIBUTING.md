# Contributing 🤝

Welcome! Poolland is a simple, offline-first project, and every contribution is appreciated.

## Set up the development environment

```bash
git clone https://github.com/Mohammad1724/poolland.git
cd poolland
flutter pub get
flutter run            # runs on a phone or emulator
```

The project has a single Android build. It declares `READ_SMS` for an
explicitly user-triggered sync of recent bank messages; it deliberately omits
`RECEIVE_SMS` and does not monitor messages in the background. Sideloaded APKs
requesting `READ_SMS` may trigger a Google Play Protect warning or block, and
Google Play restricts this permission. Users who decline it can still paste a
message on the review page. See `docs/android-install.md`.

## Before submitting changes

```bash
flutter analyze   # Should report: No issues found
flutter test      # All tests should pass
```

## Guidelines

- Keep accounting logic in `lib/data/ledger.dart` (pure functions, no UI).
- Add tests in `test/ledger_test.dart` for changes to calculations.
- Keep interface copy clear, concise, and friendly.
- Do not add server or cloud-service dependencies; the app must remain 100% offline.
- Reuse widgets from `lib/ui/widgets/` when adding repeated UI patterns.
- Keep SMS access least-privilege: `READ_SMS` is used only for an explicit
  recent-inbox sync; do not add `RECEIVE_SMS`, a notification listener, or an
  accessibility service. CI checks the merged APK permissions and receiver.
