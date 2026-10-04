import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// آیا اعلان روی این پلتفرم پشتیبانی می‌شود؟
const bool notifyIsSupported = true;

const int _dailyReminderId = 14040101;

/// سرویس یادآور روزانه (اندروید/iOS/macOS/دسکتاپ)
class ReminderService {
  ReminderService();

  bool get supported => true;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
    'daily_reminder',
    'یادآور روزانه',
    channelDescription: 'یادآوریِ ثبت هزینه و درآمد روزانه',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    ticker: 'یادآور پول‌لند',
  );

  static const DarwinNotificationDetails _darwinDetails =
      DarwinNotificationDetails();

  static const NotificationDetails _details = NotificationDetails(
    android: _androidDetails,
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
      // اگر منطقه‌ی زمانی در دسترس نبود، همان مقدار پیش‌فرض سیستم می‌ماند
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

  /// اجازه‌ی نمایش اعلان را می‌گیرد (اندروید ۱۳+ و iOS/macOS)
  Future<bool> requestPermission() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission();
      return granted ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final ok =
          await ios.requestPermissions(alert: true, badge: true, sound: true);
      return ok ?? false;
    }
    final macos = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin>();
    if (macos != null) {
      final ok =
          await macos.requestPermissions(alert: true, badge: true, sound: true);
      return ok ?? false;
    }
    return true; // دسکتاپ: نیازی به اجازه نیست
  }

  /// زمان‌بندی یادآورِ روزانه در ساعت و دقیقه‌ی مشخص
  Future<void> scheduleDaily({
    required int hour,
    required int minute,
    String title = 'یادآوری ثبت هزینه',
    String body = 'هزینه‌ها و درآمد امروز رو ثبت کردی؟',
  }) async {
    await init();
    await _plugin.cancel(id: _dailyReminderId);
    await _plugin.zonedSchedule(
      id: _dailyReminderId,
      title: title,
      body: body,
      scheduledDate: _nextInstanceOf(hour, minute),
      notificationDetails: _details,
      // «نادقیق» انتخاب شده تا نیازی به اجازه‌ی SCHEDULE_EXACT_ALARM نباشد
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelDaily() async {
    await init();
    await _plugin.cancel(id: _dailyReminderId);
  }

  /// نمایش فوری (برای تستِ اعلان از صفحه‌ی تنظیمات)
  Future<void> showNow({required String title, required String body}) async {
    await init();
    await _plugin.show(
      id: _dailyReminderId + 1,
      title: title,
      body: body,
      notificationDetails: _details,
    );
  }

  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var next =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (next.isBefore(now) || next.isAtSameMomentAs(now)) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }
}

final ReminderService reminder = ReminderService();
