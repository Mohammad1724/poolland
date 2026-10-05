import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/core/sms/bank_rules.dart';
import 'package:poolland/core/sms/sms_models.dart';
import 'package:poolland/core/sms/sms_parser.dart';

/// Bank SMS parser tests.
void main() {
  final now = DateTime(2026, 10, 4, 14, 30);

  SmsMessage msg(String body, {String address = '', DateTime? date}) =>
      SmsMessage(id: '1', address: address, body: body, date: date ?? now);

  ParsedSms p(String body, {String address = ''}) =>
      SmsParser.parse(msg(body, address: address));

  group('Bank identification', () {
    test('Identify Mellat Bank from the sender', () {
      final r = p(
        'واریز\nمبلغ: 1,500,000 ریال\nکارت 6104********1234',
        address: 'BANKMELAT',
      );
      expect(r.bankName, 'Mellat Bank');
    });

    test('Identify Saderat Bank from the sender (BSI)', () {
      final r = p('برداشت مبلغ 100,000 ریال', address: 'BSI');
      expect(r.bankName, 'Saderat Bank');
    });

    test('Identify a bank from the body when the sender is unknown', () {
      final r = p('بانک سامان\nواریز مبلغ 50,000 ریال', address: '982000');
      expect(r.bankName, 'Saman Bank');
      expect(r.isTransaction, isTrue);
    });

    test('A custom sender rule is accepted as a recognized bank', () {
      final r = SmsParser.parse(
        msg('واریز مبلغ 250,000 تومان', address: 'MYBANK'),
        extraRules: const [
          BankRule(
            id: 'my_bank',
            bankName: 'My Bank',
            senderHints: ['MYBANK'],
          ),
        ],
      );
      expect(r.bankName, 'My Bank');
      expect(r.isTransaction, isTrue);
      expect(r.confident, isTrue);
    });

    test('Unknown sender', () {
      final r = p('واریز مبلغ 50,000 ریال', address: '30001234');
      expect(r.bankName, isNull);
    });
  });

  group('Amount and currency unit', () {
    test('Rials are converted to Tomans', () {
      final r = p(
        'بانک ملت\nواریز\nمبلغ: 15,000,000 ریال',
        address: 'BANKMELAT',
      );
      expect(r.amount, 1500000);
      expect(r.currency, 'IRT');
    });

    test('Tomans are left unchanged', () {
      final r = p('واریز مبلغ 500,000 تومان به حساب شما');
      expect(r.amount, 500000);
    });

    test('Assume Rials when the bank rule specifies the default unit', () {
      final r = p('بانک ملت\nبرداشت\nمبلغ: 300,000', address: 'BANKMELAT');
      expect(r.amount, 30000);
    });

    test('Persian digits and separators are parsed', () {
      final r = p('واریز مبلغ ۱٬۵۰۰٬۰۰۰ ریال');
      expect(r.amount, 150000);
    });

    test('Arabic digits and Arabic Yeh are normalized', () {
      final r = p(
        'خريد\nمبلغ:250,000 ريال\nكارت:6037********5678',
        address: 'BSI',
      );
      expect(r.amount, 25000);
      expect(r.direction, SmsDirection.withdraw);
    });

    test('US dollars', () {
      final r = p('واریز مبلغ 100 دلار به حساب شما');
      expect(r.amount, 100);
      expect(r.currency, 'USD');
    });

    test('English SMS', () {
      final r = p('Your account has been credited with 1,000,000 Rials');
      expect(r.direction, SmsDirection.deposit);
      expect(r.amount, 100000);
    });
  });

  group('Transaction direction', () {
    test('Deposit', () {
      expect(p('واریز مبلغ 100,000 ریال').direction, SmsDirection.deposit);
    });
    test('Withdrawal', () {
      expect(p('برداشت مبلغ 100,000 ریال').direction, SmsDirection.withdraw);
    });
    test('Purchase', () {
      expect(p('خرید مبلغ 100,000 ریال').direction, SmsDirection.withdraw);
    });
    test('Outgoing transfer is a withdrawal', () {
      expect(
        p('انتقال وجه مبلغ 100,000 ریال').direction,
        SmsDirection.withdraw,
      );
    });
    test('Unrelated SMS has unknown direction', () {
      expect(p('سلام، وقت بخیر').direction, SmsDirection.unknown);
    });
  });

  group('Non-financial SMS filtering', () {
    test('A one-time password is not a transaction', () {
      final r = p('رمز یکبار مصرف شما 12345 می‌باشد');
      expect(r.isTransaction, isFalse);
      expect(r.amount, 0);
    });

    test('A verification code is not a transaction', () {
      expect(p('کد تایید شما: 998877').isTransaction, isFalse);
    });

    test('A balance notification is not a transaction', () {
      expect(p('موجودی حساب شما 5,000,000 ریال است').isTransaction, isFalse);
    });

    test('A payment-like message from an unknown sender is not a bank SMS', () {
      final r = p(
        'پرداخت مبلغ 250,000 تومان بابت خرید اشتراک اینترنت',
        address: '30001234',
      );
      // The parser may understand its amount and direction, but it must not
      // enter the bank review queue without a matching bank rule.
      expect(r.amount, 250000);
      expect(r.direction, SmsDirection.withdraw);
      expect(r.bankName, isNull);
      expect(r.isTransaction, isFalse);
      expect(r.confident, isFalse);
    });
  });

  group('Card, balance, and reference extraction', () {
    test('Masked card and balance', () {
      final r = p(
        'بانک ملت\nواریز\nمبلغ: 15,000,000 ریال\n'
        'به کارت 6104********1234\nمانده: 20,000,000 ریال\n1405/07/12 14:30',
        address: 'BANKMELAT',
      );
      expect(r.cardMask, '6104********1234');
      expect(r.cardDigits, '61041234');
      expect(r.balance, 2000000);
    });

    test('A date in the SMS is not parsed as the amount', () {
      final r = p(
        'بانک تجارت\nبرداشت\nمبلغ: 1,250,000 ریال\nتاریخ: 1405/07/12',
        address: 'TEJARAT',
      );
      expect(r.amount, 125000);
    });

    test('Reference number', () {
      final r = p(
        'بانک پارسیان\nخرید\nمبلغ 89,000 ریال\n'
        'کارت 6221********9988\nپیگیری 123456789',
        address: 'PARSIAN',
      );
      expect(r.bankName, 'Parsian Bank');
      expect(r.amount, 8900);
      expect(r.cardMask, '6221********9988');
      expect(r.reference, '123456789');
    });
  });

  group('Customer matching', () {
    test('Match a customer by the last four card digits', () {
      final sms = p('واریز مبلغ 1,000,000 ریال\nکارت 6104********1234');
      expect(SmsParser.matchesIdentifiers(sms, ['1234']), isTrue);
      expect(SmsParser.matchesIdentifiers(sms, ['9999']), isFalse);
    });

    test('Short identifiers are ignored', () {
      final sms = p('واریز مبلغ 1,000,000 ریال\nکارت 6104********1234');
      expect(SmsParser.matchesIdentifiers(sms, ['12']), isFalse);
    });
  });

  group('End-to-end scenario', () {
    test('Customer deposit SMS: amount, direction, bank, and confidence', () {
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
      expect(r.bankName, 'Mellat Bank');
      expect(r.cardDigits, '60378888');
    });
  });
}
