import 'package:flutter/services.dart';

/// Lightweight haptic feedback helpers.
///
/// Every helper is fire-and-forget and safe on platforms without a
/// vibration motor (web, desktop): the platform call is simply ignored.
/// Feedback is meant to underline deliberate actions (saving, switching
/// tabs, one-tap recording) — not every single tap in the app.
class Haptics {
  Haptics._();

  /// Soft tick for selections: switching tabs, picking a chip or option.
  static void selection() {
    HapticFeedback.selectionClick();
  }

  /// Light tap for secondary actions.
  static void tap() {
    HapticFeedback.lightImpact();
  }

  /// Emphasized pulse for primary confirmations such as saving a form.
  static void confirm() {
    HapticFeedback.mediumImpact();
  }
}
