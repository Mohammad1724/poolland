import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
// The state of the running test is only exposed by the test framework's
// internals; nothing here is used for anything but reporting.
// ignore: implementation_imports, depend_on_referenced_packages
import 'package:test_api/src/backend/invoker.dart' as test_api;

/// Called by `flutter test` instead of `main()` for every test file.
///
/// A failing test announces itself with a GitHub Actions workflow command,
/// which the runner turns into a check annotation. Only the tail of a CI log
/// can be read from the outside, so this is how a failing test can name itself
/// — and the line it failed on — without downloading the whole log.
///
/// Nothing here changes how tests run: it never throws, and it stays quiet
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

/// `"<suite path> :: <test name> | <what went wrong>"` of the test that just
/// failed, or null when it passed (or when the internals are not shaped as
/// expected).
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
  if (name == null) return null;
  final String? path = _pick<String>(
    () => (live.suite as dynamic).path as String,
  );
  final String? why = _why(live, path);
  final String label = path == null ? name : '$path :: $name';
  return _escaped(why == null ? label : '$label | $why');
}

/// One line describing the error the test failed with, plus the first stack
/// frame that points into the test file, so the failing line is known.
String? _why(dynamic live, String? path) {
  List<dynamic>? errors;
  try {
    errors = live.errors as List<dynamic>;
  } catch (_) {
    return null;
  }
  if (errors == null || errors.isEmpty) return null;
  final dynamic event = errors.last;
  final String message = _pick<String>(
    () => (event as dynamic).error.toString() as String,
  ) ?? 'failure';
  final String code = _onOneLine(message, 160);
  final String? trace = _pick<String>(
    () => (event as dynamic).stackTrace.toString() as String,
  );
  if (path == null || trace == null) return code;
  final String file = path.split('/').last;
  for (final String line in trace.split('\n')) {
    if (line.contains(file)) return '$code @ ${_onOneLine(line, 120)}';
  }
  return code;
}

/// Reads [read], returning null instead of throwing when the field is missing.
T? _pick<T>(T Function() read) {
  try {
    return read();
  } catch (_) {
    return null;
  }
}

/// Collapses [value] to a single line of at most [limit] characters.
String _onOneLine(String value, int limit) {
  final String flat = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  final String cut = flat.length > limit
      ? '${flat.substring(0, limit - 3)}...'
      : flat;
  return _escaped(cut);
}

/// Escapes the characters a workflow command treats specially.
String _escaped(String value) => value
    .replaceAll('%', '%25')
    .replaceAll('\r', ' ')
    .replaceAll('\n', ' ');
