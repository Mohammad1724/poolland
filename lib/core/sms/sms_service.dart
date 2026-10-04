import 'package:flutter/services.dart';

import '../platform_info.dart';
import 'sms_models.dart';

/// ============================================================
///  ارتباط با بخش بومی اندروید برای خواندن پیامک‌ها
///
///  طرف اندروید: MainActivity.kt و SmsReceiver.kt
///  · hasPermission      → آیا مجوز پیامک داده شده؟
///  · requestPermission  → درخواست مجوز
///  · readInbox          → خواندن پیامک‌های دریافتی
///  · onSms              → فراخوانی از اندروید هنگام دریافت پیامک جدید
/// ============================================================
class SmsService {
  static const MethodChannel _channel = MethodChannel('poolland/sms');

  static bool _inited = false;

  /// وقتی پیامک جدید می‌رسد (در حالی که برنامه باز است)
  static void Function(SmsMessage message)? onSmsReceived;

  /// آیا این پلتفرم اصلاً پیامک دارد؟ (فقط اندروید)
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

  /// خواندن پیامک‌های دریافتی از [since] به بعد
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
