import 'package:flutter/services.dart';

import '../platform_info.dart';
import 'sms_models.dart';

/// ============================================================
///  Bridge to native Android code for reading SMS messages.
///
///  Android side: MainActivity.kt and SmsReceiver.kt.
///  · hasPermission            → Check whether SMS permission is granted.
///  · requestPermission        → Request permission.
///  · readInbox                → Read received SMS messages.
///  · onSms                    → Called by Android when a new SMS arrives.
///  · syncSmsPrefs             → Mirror the notification flag, the app
///                                language, and the effective bank rules so
///                                the receiver can filter and localize the
///                                arrival notification it posts while the app
///                                is closed or in the background.
///  · setForeground            → Tell the receiver whether the UI is visible,
///                                so an open app is not doubled by a
///                                notification for the same message.
///  · consumePendingRoute      → The route the app was launched from by
///                                tapping an arrival notification, plus the
///                                date and address of that exact message.
///  · openRoute                → Pushed by Android when a notification is
///                                tapped while the engine is already alive.
/// ============================================================
class SmsService {
  static const MethodChannel _channel = MethodChannel('poolland/sms');

  static bool _inited = false;

  /// Whether this APK can read SMS at all.
  ///
  /// Starts optimistic on Android and is corrected by [detectSupport] during
  /// repository startup: the `safe` build flavor removes the SMS permissions
  /// from its manifest (so Play Protect installs it), and Android reports
  /// that here. Everything else — the intro page, settings, the review page,
  /// the receiver — reads this flag instead of assuming every Android build
  /// is a full one.
  static bool _supported = isSmsCapable;

  /// Called when a new SMS arrives while the app is open.
  static void Function(SmsMessage message)? onSmsReceived;

  /// Called when the app is brought forward by tapping an arrival
  /// notification while the engine is already alive (the cold-start case is
  /// covered by [consumePendingRoute] instead).
  static void Function(String route, int? date, String? address)? onOpenRoute;

  /// Whether this build and platform can read SMS.
  static bool get isSupported => _supported;

  /// Ask the native side whether the merged manifest declares SMS access.
  ///
  /// The `safe` flavor answers false, which turns every automatic-SMS
  /// affordance off while keeping the rest of the ledger intact. A failure
  /// keeps the optimistic platform answer so an older native build — where
  /// the method does not exist yet — still behaves like the full app.
  static Future<void> detectSupport() async {
    if (!isSmsCapable) {
      _supported = false;
      return;
    }
    try {
      _supported = await _channel.invokeMethod<bool>('isSmsSupported') ?? true;
    } on PlatformException {
      _supported = true;
    } on MissingPluginException {
      _supported = true;
    }
  }

  static void init() {
    if (_inited) return;
    _inited = true;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onSms':
          final args = call.arguments;
          if (args is Map) {
            final msg = SmsMessage.fromMap(Map<dynamic, dynamic>.from(args));
            onSmsReceived?.call(msg);
          }
          break;
        case 'openRoute':
          final routeArgs = call.arguments;
          if (routeArgs is Map) {
            final m = Map<Object?, Object?>.from(routeArgs);
            onOpenRoute?.call(
              '${m['route'] ?? ''}',
              (m['date'] as num?)?.toInt(),
              m['address'] as String?,
            );
          }
          break;
      }
      return null;
    });
  }

  static Future<bool> hasPermission() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('hasPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> requestPermission() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPermission') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Read received SMS messages from [since] onward.
  static Future<List<SmsMessage>> readInbox({
    DateTime? since,
    int limit = 500,
  }) async {
    if (!isSupported) return const <SmsMessage>[];
    try {
      final res = await _channel.invokeMethod<List<dynamic>>(
        'readInbox',
        <String, dynamic>{
          'since': since?.millisecondsSinceEpoch ?? 0,
          'limit': limit,
        },
      );
      if (res == null) return const <SmsMessage>[];
      return res
          .whereType<Map<dynamic, dynamic>>()
          .map(SmsMessage.fromMap)
          .toList();
    } on PlatformException {
      return const <SmsMessage>[];
    } on MissingPluginException {
      return const <SmsMessage>[];
    }
  }

  /// Whether the native receiver should notify about arriving bank SMS,
  /// in which language, and which senders count as a bank.
  ///
  /// The receiver can run in a fresh process where the Flutter engine (and
  /// Hive) never started, so the whole preference set is mirrored into
  /// Android SharedPreferences on every change.
  static Future<void> syncNotificationPrefs({
    required bool enabled,
    required String language,
    required String rulesJson,
  }) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('syncSmsPrefs', <String, dynamic>{
        'enabled': enabled,
        'language': language,
        'rules': rulesJson,
      });
    } on PlatformException {
      // The preference stays at its previous value; the in-app queue still
      // receives every message, so nothing is lost.
    } on MissingPluginException {
      // Non-Android platform or an older native build: nothing to configure.
    }
  }

  /// Reports whether the app UI is currently visible to the user.
  static Future<void> setForeground(bool foreground) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('setForeground', foreground);
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }

  /// The route requested by tapping an arrival notification, consumed once.
  ///
  /// Returns `{'route': 'sms_review', 'date': …, 'address': …}` when the app
  /// was opened by the notification, and null otherwise. The message date and
  /// address let the UI open the review sheet of that exact SMS.
  static Future<Map<String, Object?>?> consumePendingRoute() async {
    if (!isSupported) return null;
    try {
      final res = await _channel.invokeMethod<Map<Object?, Object?>>(
        'consumePendingRoute',
      );
      if (res == null) return null;
      return Map<String, Object?>.from(res);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
