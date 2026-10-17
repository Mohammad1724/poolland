# Contributing 🤝

Welcome! Poolland is a simple, offline-first project, and every contribution is appreciated.

## Set up the development environment

```bash
git clone https://github.com/Mohammad1724/poolland.git
cd poolland
flutter pub get
flutter run            # runs on a phone or emulator
```

The project has a single Android build. `READ_SMS` supports recent-inbox sync;
optional new-bank-SMS alerts use `RECEIVE_SMS` only after the user enables them.
The receiver is disabled in the manifest until that opt-in, filters candidates
on-device, and only opens the review flow—never recording a transaction by
itself. Sideloaded APKs requesting SMS permissions may trigger a Google Play
Protect warning or block, and Google Play restricts their use. Users can leave
SMS features off and paste a message on the review page. See
`docs/android-install.md`.

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
- Keep SMS access least-privilege: use `READ_SMS` only for inbox sync and
  `RECEIVE_SMS` only for the separately opted-in, manifest-disabled-by-default
  arrival receiver. Keep candidate filtering on-device and require approval
  before recording; do not add a notification listener or accessibility
  service. CI checks the merged APK permissions and receiver.
