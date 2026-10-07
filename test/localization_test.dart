import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/core/format_utils.dart';
import 'package:poolland/core/localization.dart';
import 'package:poolland/data/models.dart';

void main() {
  tearDown(() => AppLocalization.languageCode = 'fa');

  test('Persian is the default and key labels are translated', () {
    expect(const AppSettings().languageCode, 'fa');
    AppLocalization.languageCode = 'fa';
    expect('Dashboard'.tr, 'داشبورد');
    expect('Reports'.tr, 'گزارش‌ها');
    expect(
      'Set up VPN business (optional)'.tr,
      'راه‌اندازی کسب‌وکار VPN (اختیاری)',
    );
    expect(
      'You can also do this later in Settings.'.tr,
      'می‌توانید این کار را بعداً از تنظیمات انجام دهید.',
    );
    expect('Add personal entry'.tr, 'ثبت مورد شخصی');
    expect('Monthly net'.tr, 'ماندهٔ خالص ماه');
    expect('{count} customers'.trArgs({'count': 3}), '3 مشتری');
    expect(Fmt.monthName(1), 'فروردین');
    expect(Fmt.weekDayName(1), 'شنبه');
  });

  test('Search normalization accepts Persian and Arabic keyboard forms', () {
    expect(Fmt.normalizeSearchText('  كیف ۱۲٣ ي '), 'کیف 123 ی');
  });

  test('English can be selected and is restored from settings', () {
    AppLocalization.languageCode = 'en';
    expect('Dashboard'.tr, 'Dashboard');
    expect(Fmt.monthName(1), 'Farvardin');

    final english = AppSettings.fromMap(
      const AppSettings().copyWith(languageCode: 'en').toMap(),
    );
    expect(english.languageCode, 'en');
    expect(AppSettings.fromMap(const AppSettings().toMap()).languageCode, 'fa');
  });

  test('Notification sound settings persist locally but stay out of backups', () {
    const uri = 'content://media/external/audio/media/123';
    const name = 'My notification tone';
    final settings = const AppSettings().copyWith(
      notificationSoundUri: uri,
      notificationSoundName: name,
    );

    final restored = AppSettings.fromMap(settings.toMap());
    expect(restored.notificationSoundUri, uri);
    expect(restored.notificationSoundName, name);

    final backupSettings = settings.toMap(
      includeDeviceNotificationSound: false,
    );
    expect(backupSettings.containsKey('notificationSoundUri'), isFalse);
    expect(backupSettings.containsKey('notificationSoundName'), isFalse);
  });
}
