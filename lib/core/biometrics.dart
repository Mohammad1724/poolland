import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

import 'localization.dart';

/// What came back from a biometric prompt, flattened to the three cases the
/// lock screen actually behaves differently about.
enum BiometricOutcome {
  /// The fingerprint or face matched.
  success,

  /// The user dismissed the sheet, or the system took it away. Not an error:
  /// they most likely want to type their PIN instead.
  canceled,

  /// Something went wrong, or biometrics are not usable on this device.
  failed,
}

/// Thin wrapper over `local_auth`.
///
/// Every call is defensive on purpose. Biometrics are a convenience bolted on
/// top of the PIN, so a device that reports nonsense, a plugin that is not
/// registered, or a platform with no implementation at all must degrade to
/// "no biometrics" — never to a user locked out of their own ledger.
class Biometrics {
  Biometrics._();

  static final LocalAuthentication _auth = LocalAuthentication();

  /// Android is the only platform this app ships biometrics on. `local_auth`
  /// has no web implementation, so the plugin would throw there.
  static bool get supportedPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Can this device prompt for a fingerprint or face *right now*?
  ///
  /// Requires hardware plus at least one enrolled biometric: a phone with a
  /// sensor but no registered fingerprint must not be offered the option.
  static Future<bool> isAvailable() async {
    if (!supportedPlatform) return false;
    try {
      if (!await _auth.isDeviceSupported()) return false;
      final enrolled = await _auth.getAvailableBiometrics();
      return enrolled.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Show the system biometric sheet.
  static Future<BiometricOutcome> prompt() async {
    if (!supportedPlatform) return BiometricOutcome.failed;
    try {
      final unlocked = await _auth.authenticate(
        localizedReason: 'Unlock Poolland with your fingerprint'.tr,
        // Falling back to the device PIN/pattern here would be confusing:
        // this app has its own PIN, and the lock screen is already showing it.
        biometricOnly: true,
        authMessages: <AuthMessages>[
          AndroidAuthMessages(
            signInTitle: 'Unlock Poolland'.tr,
            signInHint: 'Unlock Poolland with your fingerprint'.tr,
            cancelButton: 'Use PIN'.tr,
          ),
        ],
      );
      return unlocked ? BiometricOutcome.success : BiometricOutcome.failed;
    } on LocalAuthException catch (error) {
      // In local_auth 3.x a dismissed sheet arrives as an exception rather
      // than `false`, so cancellation has to be sorted out from real errors.
      return switch (error.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.timeout ||
        LocalAuthExceptionCode.authInProgress => BiometricOutcome.canceled,
        _ => BiometricOutcome.failed,
      };
    } catch (_) {
      return BiometricOutcome.failed;
    }
  }
}
