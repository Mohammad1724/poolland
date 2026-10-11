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
///  · setNotificationEnabled   → Let the native receiver post (or not post)
///                                an arrival notification while the app is
///                                closed or in the background.
///  · setForeground            → Tell the receiver whether the UI is visible,
///                                so an open app is not doubled by a
///                                notification for the same message.
///  · consumePendingRoute      → The route the app was launched from by
///                                tapping an arrival notification, if any.
/// ============================================================
class SmsService {
  static const MethodChannel _channel = MethodChannel('poolland/sms');

  static bool _inited = false;

  /// Called when a new SMS arrives while the app is open.
  static void Function(SmsMessage message)? onSmsReceived;

  /// Whether SMS is available on this platform (Android only).
  static bool get isSupported => isSmsCapable;

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

  /// Whether the native receiver should notify about arriving bank SMS.
  ///
  /// The receiver cannot read the Hive database, so the preference is
  /// mirrored into Android SharedPreferences on every change.
  static Future<void> setNotificationEnabled(bool enabled) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('setNotificationEnabled', enabled);
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
  /// Returns `'sms_review'` when the app was opened (or brought forward) by
  /// the notification, and null otherwise.
  static Future<String?> consumePendingRoute() async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('consumePendingRoute');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
