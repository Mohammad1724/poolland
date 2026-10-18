import 'dart:async';

import 'package:flutter/services.dart';

import '../platform_info.dart';
import 'sms_models.dart';

/// Android SMS access and opt-in arrival alerts behind separate permissions.
///
/// READ_SMS is used for an explicit recent-inbox sync. RECEIVE_SMS is requested
/// only if the user enables arrival notifications; the native receiver filters
/// matching bank transaction messages on-device and a notification tap returns
/// the message here for the same review-before-recording flow.
class SmsAccess {
  const SmsAccess();

  static const MethodChannel _channel = MethodChannel('poolland/sms');
  static final StreamController<SmsMessage> _notificationTaps =
      StreamController<SmsMessage>.broadcast();
  static final List<SmsMessage> _bufferedNotificationTaps = [];
  static bool _tapHandlerRegistered = false;

  bool get supported => isAndroidPlatform;

  Stream<SmsMessage> get notificationTaps => _notificationTaps.stream;

  /// Installs the native notification-tap handler before the app's first frame.
  /// Taps received before the HomeShell is ready are buffered for it.
  void initializeNotificationTapHandler() {
    if (!supported || _tapHandlerRegistered) return;
    _tapHandlerRegistered = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'smsNotificationTapped' || call.arguments is! Map) {
        return;
      }
      final message = SmsMessage.fromMap(
        Map<dynamic, dynamic>.from(call.arguments as Map),
      );
      if (message.body.trim().isEmpty) return;

      if (_notificationTaps.hasListener) {
        _notificationTaps.add(message);
      } else if (!_bufferedNotificationTaps.any(
        (queued) => queued.key == message.key,
      )) {
        _bufferedNotificationTaps.add(message);
        _notificationTaps.add(message);
      }
      // The Android Activity keeps the launch Intent until this ack, so a tap
      // during cold startup can still be recovered by takePendingNotification.
      try {
        await _channel.invokeMethod<void>(
          'ackSmsNotification',
          message.toMap(),
        );
      } on MissingPluginException {
        // The pending Activity intent remains available as a startup fallback.
      } on PlatformException {
        // A duplicate tap can still be safely deduplicated by the repository.
      }
    });
  }

  /// Messages delivered before the HomeShell subscribed to [notificationTaps].
  List<SmsMessage> takeBufferedNotificationTaps() {
    final pending = List<SmsMessage>.of(_bufferedNotificationTaps);
    _bufferedNotificationTaps.clear();
    return pending;
  }

  /// Checks READ_SMS permission without showing a system dialog.
  Future<bool> hasReadPermission() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('hasReadPermission') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Requests Android's runtime READ_SMS permission.
  Future<bool> requestReadPermission() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('requestReadPermission') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Checks the separate runtime permission for opt-in incoming-SMS alerts.
  Future<bool> hasReceivePermission() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('hasReceivePermission') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Requests RECEIVE_SMS only after the user explicitly enables
  /// arrival alerts.
  Future<bool> requestReceivePermission() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>('requestReceivePermission') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Reads a bounded window of recent inbox messages from the device.
  ///
  /// The default is the last 30 days, capped to 500 messages. Message bodies
  /// remain on-device and are only passed to the local bank-SMS parser.
  Future<List<SmsMessage>> readInbox({
    DateTime? since,
    int limit = 500,
  }) async {
    if (!supported) return const [];
    final safeLimit = limit.clamp(1, 1000).toInt();
    final cutoff = since ?? DateTime.now().subtract(const Duration(days: 30));
    final rows = await _channel.invokeMethod<List<dynamic>>('readInbox', {
      'sinceMillis': cutoff.millisecondsSinceEpoch,
      'limit': safeLimit,
    });
    if (rows == null || rows.isEmpty) return const [];

    final messages = <SmsMessage>[];
    for (final row in rows) {
      if (row is! Map) continue;
      try {
        final message = SmsMessage.fromMap(Map<dynamic, dynamic>.from(row));
        if (message.body.trim().isNotEmpty) messages.add(message);
      } catch (_) {
        // Ignore malformed provider rows rather than failing the whole sync.
      }
    }
    return messages;
  }

  /// Whether the user has enabled the receiver in this Android installation.
  Future<bool> arrivalNotificationsEnabled() async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'arrivalNotificationsEnabled',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Saves the opt-in switch. Native code refuses to enable it without both
  /// RECEIVE_SMS and, on Android 13+, POST_NOTIFICATIONS.
  Future<bool> setArrivalNotificationsEnabled(bool enabled) async {
    if (!supported) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'setArrivalNotificationsEnabled',
            {'enabled': enabled},
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Keeps the native pre-filter aligned with the app's currently active rules.
  Future<void> syncArrivalRules({
    required List<String> senderHints,
    required List<String> bodyHints,
  }) async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('syncArrivalRules', {
        'senderHints': senderHints,
        'bodyHints': bodyHints,
      });
    } on MissingPluginException {
      // Inbox sync and paste still work if this optional native handler is
      // absent.
    } on PlatformException {
      // Never let an optional notification filter block app startup or editing.
    }
  }

  /// Takes a notification's SMS payload when Android cold-started the app.
  Future<SmsMessage?> takePendingNotification() async {
    if (!supported) return null;
    try {
      final row = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'takePendingSmsNotification',
      );
      if (row == null) return null;
      final message = SmsMessage.fromMap(row);
      return message.body.trim().isEmpty ? null : message;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Opens Android's app-details screen so the user can re-enable a permission
  /// after choosing "Don't ask again" in the runtime prompt.
  Future<void> openAppSettings() async {
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('openAppSettings');
    } on MissingPluginException {
      // A missing native handler should not crash the review page.
    } on PlatformException {
      // The permission can still be changed manually in Android settings.
    }
  }
}

const SmsAccess smsAccess = SmsAccess();
