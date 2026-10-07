/// Web and unsupported platforms do not provide notifications.
const bool notifyIsSupported = false;

class ReminderService {
  const ReminderService();

  bool get supported => false;

  Future<void> init() async {}

  Future<bool> requestPermission() async => false;

  Future<void> scheduleDaily({
    required int hour,
    required int minute,
    String title = 'Expense reminder',
    String body = 'Have you recorded today’s expenses and income?',
    String? soundUri,
    String? soundName,
  }) async {}

  Future<void> cancelDaily() async {}

  Future<void> showNow({
    required String title,
    required String body,
    String? soundUri,
    String? soundName,
  }) async {}
}

const ReminderService reminder = ReminderService();
