import 'package:flutter/services.dart';

import '../platform_info.dart';
import 'sms_models.dart';

/// Android inbox access behind the app's explicit READ_SMS permission.
///
/// Poolland only reads recent inbox messages after the user grants permission
/// and taps Sync (or opens the SMS review page with permission already granted).
/// It does not listen for incoming SMS in the background.
class SmsAccess {
  const SmsAccess();

  static const MethodChannel _channel = MethodChannel('poolland/sms');

  bool get supported => isAndroidPlatform;

  /// Checks permission without showing a system dialog.
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
