import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
// The state of the running test is only exposed by the test framework's
// internals; nothing here is used for anything but reporting.
// ignore: implementation_imports, depend_on_referenced_packages
import 'package:test_api/src/backend/invoker.dart' as test_api;

/// Called by `flutter test` instead of `main()` for every test file.
///
/// When a test fails it announces itself with a GitHub Actions workflow
/// command, which the runner turns into a check annotation. Only the tail of a
/// CI log is visible from the outside, so this is how a failing test can be
/// named without downloading the whole log.
///
/// Nothing here changes how tests behave: it never throws, and it stays quiet
/// unless the test has already failed.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  tearDown(() {
    final String? failed = _failedTest();
    if (failed == null) return;
    // ignore: avoid_print
    print('::error::FAILED_TEST $failed');
  });

  await testMain();
}

/// `"<suite path> :: <test name>"` of the test that just failed, or null when
/// the test passed (or when the internals are not shaped as expected).
String? _failedTest() {
  dynamic live;
  try {
    final dynamic invoker = test_api.Invoker.current;
    if (invoker == null) return null;
    live = invoker.liveTest;
    if (live == null) return null;
    final dynamic state = live.state;
    if (state == null || state.result.isFailing != true) return null;
  } catch (_) {
    return null;
  }

  final String? name = _pick<String>(() => (live.test as dynamic).name as String);
  final String? path = _pick<String>(() => (live.suite as dynamic).path as String);
  if (name == null) return null;
  return _escaped(path == null ? name : '$path :: $name');
}

/// Reads [read], returning null instead of throwing when the field is missing.
T? _pick<T>(T Function() read) {
  try {
    return read();
  } catch (_) {
    return null;
  }
}

/// Escapes the characters a workflow command treats specially.
String _escaped(String value) => value
    .replaceAll('%', '%25')
    .replaceAll('\r', ' ')
    .replaceAll('\n', ' ');
