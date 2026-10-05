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
    expect('{count} customers'.trArgs({'count': 3}), '3 مشتری');
    expect(Fmt.monthName(1), 'فروردین');
    expect(Fmt.weekDayName(1), 'شنبه');
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
}
