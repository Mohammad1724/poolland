import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Whether notifications are supported on this platform.
const bool notifyIsSupported = true;

const int _dailyReminderId = 14040101;

/// Daily reminder service (Android/iOS/macOS/desktop).
class ReminderService {
  ReminderService();

  bool get supported => true;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const DarwinNotificationDetails _darwinDetails =
      DarwinNotificationDetails();

  AndroidNotificationDetails _androidDetailsFor(
    String? soundUri,
    String? soundName,
  ) {
    final normalizedUri = soundUri?.trim();
    final hasCustomSound = normalizedUri != null && normalizedUri.isNotEmpty;
    final soundHash = normalizedUri == null
        ? ''
        : sha256.convert(utf8.encode(normalizedUri)).toString().substring(0, 12);
    final channelId = hasCustomSound
        ? 'daily_reminder_$soundHash'
        : 'daily_reminder';
    final channelName = hasCustomSound && soundName != null
        ? 'Daily reminder — $soundName'
        : 'Daily reminder';

    return AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Reminder to record daily expenses and income',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ticker: 'Poolland reminder',
      playSound: true,
      sound: hasCustomSound
          ? UriAndroidNotificationSound(normalizedUri!)
          : null,
    );
  }

  NotificationDetails _detailsFor(String? soundUri, String? soundName) =>
      NotificationDetails(
        android: _androidDetailsFor(soundUri, soundName),
        iOS: _darwinDetails,
        macOS: _darwinDetails,
      );

  bool _inited = false;

  Future<void> init() async {
    if (_inited) return;
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Tehran'));
    } catch (_) {
      // Keep the system default if the time zone is unavailable.
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwin = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );
    await _plugin.initialize(settings: settings);
    _inited = true;
  }

  /// Request permission to show notifications (Android 13+, iOS, and macOS).
  Future<bool> requestPermission() async {
    await init();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }
    final ios = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      final ok = await ios.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return ok ?? false;
    }
    final macos = _plugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();
    if (macos != null) {
      final ok = await macos.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      return ok ?? false;
    }
    return true; // Desktop does not require permission.
  }

  /// Schedule a daily reminder at the specified hour and minute.
  Future<void> scheduleDaily({
    required int hour,
    required int minute,
    String title = 'Expense reminder',
    String body = 'Have you recorded today’s expenses and income?',
    String? soundUri,
    String? soundName,
  }) async {
    await init();
    await _plugin.cancel(id: _dailyReminderId);
    await _plugin.zonedSchedule(
      id: _dailyReminderId,
      title: title,
      body: body,
      scheduledDate: _nextInstanceOf(hour, minute),
      notificationDetails: _detailsFor(soundUri, soundName),
      // Inexact scheduling avoids requiring SCHEDULE_EXACT_ALARM permission.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelDaily() async {
    await init();
    await _plugin.cancel(id: _dailyReminderId);
  }

  /// Show a notification immediately (used by the settings test action).
  Future<void> showNow({
    required String title,
    required String body,
    String? soundUri,
    String? soundName,
  }) async {
    await init();
    await _plugin.show(
      id: _dailyReminderId + 1,
      title: title,
      body: body,
      notificationDetails: _detailsFor(soundUri, soundName),
    );
  }

  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (next.isBefore(now) || next.isAtSameMomentAs(now)) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }
}

final ReminderService reminder = ReminderService();
