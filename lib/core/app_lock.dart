import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Salted hashing for the optional app-lock PIN.
///
/// Scope, so nobody mistakes this for more than it is: the PIN guards the
/// user interface only. The Hive boxes on disk are **not** encrypted, so
/// anyone with root access or a copy of the app's data directory can still
/// read everything. What the lock does buy you is that a borrowed or
/// briefly-unattended phone does not expose bank SMS and customer debts.
///
/// The PIN is never stored in clear text, and a per-install random salt means
/// the handful of obvious PINs (0000, 1234, …) do not produce a recognisable
/// digest in an exported backup.
class AppLock {
  AppLock._();

  static const int minPinLength = 4;
  static const int maxPinLength = 8;

  static final Random _random = Random.secure();

  /// Hash [pin] with a fresh random salt.
  ///
  /// The salt is kept next to the digest as `salt:digest`; that whole string
  /// is what lands in [AppSettings.pinHash].
  static String hash(String pin) {
    final salt = base64Url.encode(
      List<int>.generate(12, (_) => _random.nextInt(256)),
    );
    return '$salt:${_digest(pin, salt)}';
  }

  /// Does [pin] match a previously stored `salt:digest` value?
  static bool verify(String pin, String? stored) {
    if (stored == null) return false;
    final separator = stored.indexOf(':');
    if (separator <= 0 || separator == stored.length - 1) return false;
    final salt = stored.substring(0, separator);
    final expected = stored.substring(separator + 1);
    return _constantTimeEquals(_digest(pin, salt), expected);
  }

  /// PINs are 4–8 digits. Digits only, so the numeric keypad is enough and
  /// the user is never locked out by a keyboard they cannot reach.
  static bool isValidPin(String pin) =>
      pin.length >= minPinLength &&
      pin.length <= maxPinLength &&
      pin.codeUnits.every((c) => c >= 0x30 && c <= 0x39);

  static String _digest(String pin, String salt) =>
      sha256.convert(utf8.encode('poolland:$salt:$pin')).toString();

  /// Compare without leaking, through timing, how many characters matched.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }
}
