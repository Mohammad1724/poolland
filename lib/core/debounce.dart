import 'dart:async';

import 'package:flutter/foundation.dart';

/// Runs a callback only after the caller has stopped firing it for [duration].
///
/// Search fields use this so that every keystroke does not re-filter and
/// re-sort the whole list: typing stays instant, and the work happens once the
/// user pauses. Always call [dispose] from `State.dispose`.
class Debouncer {
  Debouncer({this.duration = const Duration(milliseconds: 180)});

  final Duration duration;
  Timer? _timer;

  /// Schedule [action], replacing any previously scheduled call.
  void run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  /// Cancel any pending call.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Cancel and release the timer; call from `State.dispose`.
  void dispose() => cancel();
}
