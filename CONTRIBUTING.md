# Contributing 🤝

Welcome! Poolland is a simple, offline-first project, and every contribution is appreciated.

## Set up the development environment

```bash
git clone https://github.com/Mohammad1724/poolland.git
cd poolland
flutter pub get
flutter run            # runs on a phone or emulator
```

The project has a single Android build. It declares **no SMS permission**:
Google Play Protect blocks the sideload of any APK that asks for
`READ_SMS`/`RECEIVE_SMS`, and the block is by permission, not by signature.
A bank message reaches the ledger by pasting its text on the review page.
See `docs/android-install.md`.

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
- Never add `READ_SMS`, `RECEIVE_SMS`, a notification listener, or an
  accessibility service: CI and the release workflow fail if the built APK
  declares any of them.
