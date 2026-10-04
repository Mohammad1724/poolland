/// نسخه‌ی وب/پشتیبانی‌نشده — اعلان‌ها غیرفعال هستند.
const bool notifyIsSupported = false;

class ReminderService {
  const ReminderService();

  bool get supported => false;

  Future<void> init() async {}

  Future<bool> requestPermission() async => false;

  Future<void> scheduleDaily({
    required int hour,
    required int minute,
    String title = 'یادآوری ثبت هزینه',
    String body = 'هزینه‌ها و درآمد امروز رو ثبت کردی؟',
  }) async {}

  Future<void> cancelDaily() async {}

  Future<void> showNow({required String title, required String body}) async {}
}

const ReminderService reminder = ReminderService();
