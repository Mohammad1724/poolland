import 'dart:convert';
import 'dart:io' show Platform;

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../localization.dart';

/// Whether notifications are supported on this platform.
const bool notifyIsSupported = true;

const int _dailyReminderId = 14040101;

/// Daily reminder service (Android/iOS/macOS/desktop).
class ReminderService {
  ReminderService();

  /// flutter_local_notifications only registers a platform implementation
  /// on Android/iOS/macOS; touching it on any other dart:io host (Linux or
  /// Windows desktop, and widget tests running on them) throws a
  /// LateInitializationError, so every entry point no-ops there instead.
  static bool get _available =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  bool get supported => _available;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const DarwinNotificationDetails _darwinDetails =
      DarwinNotificationDetails();

  AndroidNotificationDetails _androidDetailsFor(
    String? soundUri,
    String? soundName,
  ) {
    final normalizedUri = soundUri?.trim();

    // Android caches channel settings, so a sound change needs a new channel
    // id. Derive it from the URI hash and build the sound in the same branch
    // to keep the non-null narrowing local and explicit.
    final String soundHash;
    final UriAndroidNotificationSound? customSound;
    if (normalizedUri == null || normalizedUri.isEmpty) {
      soundHash = '';
      customSound = null;
    } else {
      soundHash = sha256
          .convert(utf8.encode(normalizedUri))
          .toString()
          .substring(0, 12);
      customSound = UriAndroidNotificationSound(normalizedUri);
    }

    final hasCustomSound = customSound != null;
    final channelId = hasCustomSound
        ? 'daily_reminder_$soundHash'
        : 'daily_reminder';
    final channelName = hasCustomSound && soundName != null
        ? '${'Daily reminder'.tr} — $soundName'
        : 'Daily reminder'.tr;

    return AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription:
          'Reminder to record daily expenses and income'.tr,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      ticker: 'Poolland reminder'.tr,
      icon: '@drawable/ic_sms_notification',
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      color: const Color(0xFF0D9488),
      playSound: true,
      sound: customSound,
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
    if (_inited || !_available) {
      _inited = true;
      return;
    }
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('Asia/Tehran'));
    } catch (_) {
      // Keep the system default if the time zone is unavailable.
    }
    const android = AndroidInitializationSettings('@drawable/ic_sms_notification');
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
    if (!_available) return false;
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

  /// Whether the OS currently allows posting notifications, without
  /// showing any dialog (Android 13+ tracks this as a runtime permission).
  Future<bool> notificationsEnabled() async {
    if (!_available) return false;
    try {
      await init();
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.areNotificationsEnabled() ?? false;
      }
      // iOS/macOS grant per notification style at request time; there is no
      // quiet probe, and desktop needs no permission at all.
      return true;
    } on MissingPluginException {
      // No notification plugin in this environment (tests, odd builds):
      // never crash a quiet state probe.
      return false;
    } on PlatformException {
      return false;
    }
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
    if (!_available) return;
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
    if (!_available) return;
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
    if (!_available) return;
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
