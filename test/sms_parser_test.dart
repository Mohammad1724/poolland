import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/core/sms/sms_models.dart';
import 'package:poolland/core/sms/sms_parser.dart';

/// تست‌های موتور تجزیه‌ی پیامک بانکی
void main() {
  final now = DateTime(2026, 10, 4, 14, 30);

  SmsMessage msg(String body, {String address = '', DateTime? date}) =>
      SmsMessage(id: '1', address: address, body: body, date: date ?? now);

  ParsedSms p(String body, {String address = ''}) =>
      SmsParser.parse(msg(body, address: address));

  group('تشخیص بانک', () {
    test('بانک ملت از روی فرستنده', () {
      final r = p(
        'واریز\nمبلغ: 1,500,000 ریال\nکارت 6104********1234',
        address: 'BANKMELAT',
      );
      expect(r.bankName, 'بانک ملت');
    });

    test('بانک صادرات از روی فرستنده (BSI)', () {
      final r = p('برداشت مبلغ 100,000 ریال', address: 'BSI');
      expect(r.bankName, 'بانک صادرات');
    });

    test('تشخیص از روی متن وقتی فرستنده ناشناس است', () {
      final r = p('بانک سامان\nواریز مبلغ 50,000 ریال', address: '982000');
      expect(r.bankName, 'بانک سامان');
    });

    test('فرستنده‌ی ناشناس', () {
      final r = p('واریز مبلغ 50,000 ریال', address: '30001234');
      expect(r.bankName, isNull);
    });
  });

  group('مبلغ و واحد پول', () {
    test('ریال به تومان تبدیل می‌شود', () {
      final r = p(
        'بانک ملت\nواریز\nمبلغ: 15,000,000 ریال',
        address: 'BANKMELAT',
      );
      expect(r.amount, 1500000);
      expect(r.currency, 'IRT');
    });

    test('تومان دست‌نخورده می‌ماند', () {
      final r = p('واریز مبلغ 500,000 تومان به حساب شما');
      expect(r.amount, 500000);
    });

    test('وقتی واحد ذکر نشده، طبق قانون بانک ریال فرض می‌شود', () {
      final r = p('بانک ملت\nبرداشت\nمبلغ: 300,000', address: 'BANKMELAT');
      expect(r.amount, 30000);
    });

    test('ارقام فارسی و جداکننده‌ی فارسی', () {
      final r = p('واریز مبلغ ۱٬۵۰۰٬۰۰۰ ریال');
      expect(r.amount, 150000);
    });

    test('ارقام عربی و «ي» عربی', () {
      final r = p(
        'خريد\nمبلغ:250,000 ريال\nكارت:6037********5678',
        address: 'BSI',
      );
      expect(r.amount, 25000);
      expect(r.direction, SmsDirection.withdraw);
    });

    test('دلار', () {
      final r = p('واریز مبلغ 100 دلار به حساب شما');
      expect(r.amount, 100);
      expect(r.currency, 'USD');
    });

    test('پیامک انگلیسی', () {
      final r = p('Your account has been credited with 1,000,000 Rials');
      expect(r.direction, SmsDirection.deposit);
      expect(r.amount, 100000);
    });
  });

  group('جهت تراکنش', () {
    test('واریز', () {
      expect(p('واریز مبلغ 100,000 ریال').direction, SmsDirection.deposit);
    });
    test('برداشت', () {
      expect(p('برداشت مبلغ 100,000 ریال').direction, SmsDirection.withdraw);
    });
    test('خرید', () {
      expect(p('خرید مبلغ 100,000 ریال').direction, SmsDirection.withdraw);
    });
    test('انتقال خروجی = برداشت', () {
      expect(
        p('انتقال وجه مبلغ 100,000 ریال').direction,
        SmsDirection.withdraw,
      );
    });
    test('پیامکِ بی‌ربط نامشخص است', () {
      expect(p('سلام، وقت بخیر').direction, SmsDirection.unknown);
    });
  });

  group('فیلتر پیامک‌های غیرمالی', () {
    test('رمز یک‌بار مصرف تراکنش نیست', () {
      final r = p('رمز یکبار مصرف شما 12345 می‌باشد');
      expect(r.isTransaction, isFalse);
      expect(r.amount, 0);
    });

    test('کد تایید تراکنش نیست', () {
      expect(p('کد تایید شما: 998877').isTransaction, isFalse);
    });

    test('اعلام موجودی تراکنش نیست (جهت نامشخص)', () {
      expect(p('موجودی حساب شما 5,000,000 ریال است').isTransaction, isFalse);
    });
  });

  group('استخراج کارت، مانده و پیگیری', () {
    test('کارتِ ماسک‌شده و مانده', () {
      final r = p(
        'بانک ملت\nواریز\nمبلغ: 15,000,000 ریال\n'
        'به کارت 6104********1234\nمانده: 20,000,000 ریال\n1405/07/12 14:30',
        address: 'BANKMELAT',
      );
      expect(r.cardMask, '6104********1234');
      expect(r.cardDigits, '61041234');
      expect(r.balance, 2000000);
    });

    test('تاریخِ داخل پیامک به‌جای مبلغ گرفته نمی‌شود', () {
      final r = p(
        'بانک تجارت\nبرداشت\nمبلغ: 1,250,000 ریال\nتاریخ: 1405/07/12',
        address: 'TEJARAT',
      );
      expect(r.amount, 125000);
    });

    test('شماره پیگیری', () {
      final r = p(
        'بانک پارسیان\nخرید\nمبلغ 89,000 ریال\n'
        'کارت 6221********9988\nپیگیری 123456789',
        address: 'PARSIAN',
      );
      expect(r.bankName, 'بانک پارسیان');
      expect(r.amount, 8900);
      expect(r.cardMask, '6221********9988');
      expect(r.reference, '123456789');
    });
  });

  group('تطبیق با مشتری', () {
    test('۴ رقم آخر کارت مشتری پیدا می‌شود', () {
      final sms = p('واریز مبلغ 1,000,000 ریال\nکارت 6104********1234');
      expect(SmsParser.matchesIdentifiers(sms, ['1234']), isTrue);
      expect(SmsParser.matchesIdentifiers(sms, ['9999']), isFalse);
    });

    test('شناسه‌ی کوتاه نادیده گرفته می‌شود', () {
      final sms = p('واریز مبلغ 1,000,000 ریال\nکارت 6104********1234');
      expect(SmsParser.matchesIdentifiers(sms, ['12']), isFalse);
    });
  });

  group('سناریوی کامل', () {
    test('پیامک واریزِ مشتری: مبلغ، جهت، بانک و اطمینان', () {
      final r = p(
        'بانک ملت\nواریز\nمبلغ: 4,500,000 ریال\n'
        'از کارت 6037********8888 به کارت 6104********1234\n'
        'مانده: 12,300,000 ریال',
        address: 'BANKMELAT',
      );
      expect(r.isTransaction, isTrue);
      expect(r.confident, isTrue);
      expect(r.amount, 450000);
      expect(r.direction, SmsDirection.deposit);
      expect(r.bankName, 'بانک ملت');
      expect(r.cardDigits, '60378888');
    });
  });
}
