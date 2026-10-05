import 'package:flutter/services.dart';

import '../platform_info.dart';
import 'sms_models.dart';

/// ============================================================
///  Bridge to native Android code for reading SMS messages.
///
///  Android side: MainActivity.kt and SmsReceiver.kt.
///  · hasPermission      → Check whether SMS permission is granted.
///  · requestPermission  → Request permission.
///  · readInbox          → Read received SMS messages.
///  · onSms              → Called by Android when a new SMS arrives.
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
}
