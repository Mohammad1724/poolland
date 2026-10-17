import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/ui/design.dart';
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
  // The motion kit stays out of widget tests: no celebration overlays, no
  // stagger timers, no ambient loops, and animated values settle instantly.
  // Production code never touches this flag.
  Motion.motionEnabled = false;

  tearDown(() {
    final String? failed = _failedTest();
    if (failed == null) return;
    // ignore: avoid_print
    print('::error::FAILED_TEST $failed');
    final String? detail = _failureDetail();
    if (detail != null && detail.isNotEmpty) {
      // ignore: avoid_print
      print('::error::FAIL_DETAIL $detail');
    }
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

/// A compact view of the failure (error text + top of the stack) of the test
/// that just failed, for the FAIL_DETAIL annotation.
String? _failureDetail() {
  dynamic live;
  try {
    final dynamic invoker = test_api.Invoker.current;
    if (invoker == null) return null;
    live = invoker.liveTest;
    if (live == null) return null;
    final dynamic state = live.state;
    if (state == null || state.result.isFailing != true) return null;
    final dynamic result = state.result;
    final StringBuffer buf = StringBuffer();
    Object? err = _pick(() => (result.error as dynamic));
    final dynamic errors = _pick(() => (result.errors as dynamic));
    if (err == null && errors is List) {
      for (final dynamic e in errors) {
        err = _pick<Object?>(() => (e.error as Object?));
        if (err != null) break;
      }
    }
    if (err != null) {
      buf.write('$err');
    }
    final dynamic trace = _pick(() => (result.stackTrace as dynamic));
    if (trace != null && buf.length < 1200) {
      final List<String> lines = trace.toString().split('\n');
      buf.write(' @ ');
      buf.write(lines.take(8).join(' / '));
    }
    final String s = buf.toString().trim();
    if (s.isEmpty) return null;
    return _escaped(s.length > 1500 ? s.substring(0, 1500) : s);
  } catch (_) {
    return null;
  }
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
