import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/core/format_utils.dart';
import 'package:poolland/core/jalali_utils.dart';
import 'package:poolland/data/ledger.dart';
import 'package:poolland/data/models.dart';

/// تست‌های منطق حسابداری — بدون نیاز به دیتابیس
void main() {
  final now = DateTime(2026, 10, 4); // ۱۴۰۵/۰۷/۱۲

  Customer customer(
          {String id = 'c1',
          double opening = 0,
          String name = 'علی'}) =>
      Customer(id: id, name: name, createdAt: now, openingBalance: opening);

  Txn txn({
    required TxnKind kind,
    required double amount,
    DateTime? date,
    String? customerId = 'c1',
    bool credit = false,
    String currency = 'IRT',
    double rate = 1,
  }) =>
      Txn(
        id: 't${DateTime.now().microsecondsSinceEpoch}${amount.hashCode}',
        kind: kind,
        amount: amount,
        currency: currency,
        rateToBase: rate,
        date: date ?? now,
        customerId: customerId,
        credit: credit,
        createdAt: now,
      );

  group('خلاصه‌ی دوره', () {
    test('درآمد، هزینه و سود درست محاسبه می‌شود', () {
      final txns = [
        txn(kind: TxnKind.income, amount: 1000000, credit: true),
        txn(kind: TxnKind.income, amount: 500000, credit: false),
        txn(kind: TxnKind.expense, amount: 300000, credit: false),
        txn(kind: TxnKind.receive, amount: 200000),
      ];
      final s = Ledger.summarize(txns);

      expect(s.income, 1500000);
      expect(s.expense, 300000);
      expect(s.profit, 1200000);
      expect(s.received, 200000);
      expect(s.incomeCash, 500000);
      expect(s.cashIn, 700000); // ۵۰۰ نقدی + ۲۰۰ وصولی
      expect(s.cashOut, 300000);
      expect(s.netCash, 400000);
      expect(s.txnCount, 4);
    });

    test('برگشت وجه از سود کم می‌شود', () {
      final s = Ledger.summarize([
        txn(kind: TxnKind.income, amount: 1000000),
        txn(kind: TxnKind.refund, amount: 400000),
      ]);
      expect(s.profit, 600000);
      expect(s.cashOut, 400000);
    });

    test('تبدیل ارز با نرخ ثبت‌شده انجام می‌شود', () {
      final s = Ledger.summarize([
        txn(kind: TxnKind.income, amount: 10, currency: 'USD', rate: 130000),
      ]);
      expect(s.income, 1300000);
    });

    test('فیلتر بازه‌ی تاریخ', () {
      final outOfRange = txn(kind: TxnKind.income, amount: 999, date: DateTime(2026, 5, 1));
      final s = Ledger.summarize(
        [outOfRange, txn(kind: TxnKind.income, amount: 1000)],
        from: J.startOfMonth(now),
        to: J.endOfMonth(now),
      );
      expect(s.income, 1000);
    });
  });

  group('مانده حساب طرف حساب', () {
    test('فروش نسیه بدهی می‌سازد و دریافت آن را کم می‌کند', () {
      final c = customer();
      final txns = [
        txn(kind: TxnKind.income, amount: 800000, credit: true),
        txn(kind: TxnKind.receive, amount: 300000),
      ];
      expect(Ledger.customerBalance(c, txns), 500000);
    });

    test('فروش نقدی روی مانده اثر ندارد', () {
      final c = customer();
      expect(
        Ledger.customerBalance(c, [txn(kind: TxnKind.income, amount: 800000)]),
        0,
      );
    });

    test('بدهی اولیه + خرید نسیه + پرداخت ما به مشتری', () {
      final c = customer(opening: 200000);
      final txns = [
        txn(kind: TxnKind.income, amount: 1000000, credit: true),
        txn(kind: TxnKind.receive, amount: 500000),
        txn(kind: TxnKind.refund, amount: 100000),
      ];
      expect(Ledger.customerBalance(c, txns), 600000);
    });

    test('پرداخت بیشتر از بدهی، مانده را منفی (بستانکار) می‌کند', () {
      final c = customer();
      final txns = [
        txn(kind: TxnKind.income, amount: 100000, credit: true),
        txn(kind: TxnKind.receive, amount: 250000),
      ];
      expect(Ledger.customerBalance(c, txns), -150000);
    });

    test('مجموع طلب و بدهی', () {
      final a = customer(id: 'a', name: 'A');
      final b = customer(id: 'b', name: 'B');
      final txns = [
        txn(kind: TxnKind.income, amount: 500000, credit: true, customerId: 'a'),
        txn(kind: TxnKind.expense, amount: 200000, credit: true, customerId: 'b'),
      ];
      final totals = Ledger.totals([a, b], txns);
      expect(totals.receivable, 500000);
      expect(totals.payable, 200000);
      expect(totals.net, 300000);
      expect(totals.debtorsCount, 1);
      expect(totals.creditorsCount, 1);
    });

    test('خلاصه به تفکیک ارز', () {
      final c = customer();
      final txns = [
        txn(kind: TxnKind.income, amount: 20, currency: 'USD', rate: 130000, credit: true),
        txn(kind: TxnKind.receive, amount: 10, currency: 'USDT', rate: 129000),
      ];
      final map = Ledger.customerCurrencyTotals(c, txns);
      expect(map['USD'], 20);
      expect(map['USDT'], -10);
    });
  });

  group('سری ماهانه', () {
    test('۶ ماه با احتساب ماه‌های شمسی', () {
      final txns = [
        txn(kind: TxnKind.income, amount: 100, date: now),
        txn(kind: TxnKind.income, amount: 50, date: J.addMonths(now, -2)),
        txn(kind: TxnKind.expense, amount: 30, date: J.addMonths(now, -5)),
      ];
      final series = Ledger.monthlySeries(txns, months: 6, endMonth: now);
      expect(series.length, 6);
      expect(series.last.income, 100);
      expect(series[3].income, 50);
      expect(series.first.expense, 30);
    });
  });

  group('وضعیت اشتراک', () {
    Subscription sub({required int daysFromNow}) => Subscription(
          id: 's1',
          customerId: 'c1',
          planName: 'تست',
          startDate: J.addDays(now, -30),
          endDate: J.addDays(now, daysFromNow),
          createdAt: now,
        );

    test('فعال / نزدیک انقضا / منقضی', () {
      expect(Ledger.subStatus(sub(daysFromNow: 30), now: now),
          SubStatus.active);
      expect(Ledger.subStatus(sub(daysFromNow: 2), now: now),
          SubStatus.expiringSoon);
      expect(Ledger.subStatus(sub(daysFromNow: -1), now: now),
          SubStatus.expired);
    });

    test('شمارش روزهای باقی‌مانده', () {
      expect(Ledger.daysLeft(sub(daysFromNow: 5), now: now), 5);
      expect(Ledger.daysLeft(sub(daysFromNow: -3), now: now), -3);
    });

    test('هشدارها شامل نزدیک‌انقضا و تازه‌منقضی می‌شود', () {
      final alerts = Ledger.alerts(
        [
          sub(daysFromNow: 40),
          sub(daysFromNow: 1),
          sub(daysFromNow: -5),
          sub(daysFromNow: -60),
        ],
        now: now,
        reminderDays: 3,
      );
      expect(alerts.length, 2);
    });
  });

  group('پلن‌ها', () {
    test('پایان پلن ماهانه با تقویم شمسی', () {
      final p = Plan(
        id: 'p1',
        name: 'یک ماهه',
        price: 250000,
        durationValue: 1,
        durationUnit: PlanDurationUnit.month,
      );
      final start = J.toDate(1405, 7, 12);
      final end = p.endFrom(start);
      final endJ = J.of(end);
      expect([endJ.year, endJ.month, endJ.day], [1405, 8, 11]);
    });

    test('پایان پلن سه‌ماهه', () {
      final p = Plan(
        id: 'p1',
        name: 'سه ماهه',
        durationValue: 3,
        durationUnit: PlanDurationUnit.month,
      );
      final end = J.of(p.endFrom(J.toDate(1405, 7, 12)));
      expect([end.year, end.month, end.day], [1405, 10, 11]);
    });

    test('پلن روزانه', () {
      final p = Plan(
          id: 'p1', name: 'یک هفته', durationValue: 7, durationUnit: PlanDurationUnit.day);
      final end = J.of(p.endFrom(J.toDate(1405, 7, 12)));
      expect([end.year, end.month, end.day], [1405, 7, 18]);
    });
  });

  group('گزارش دسته‌بندی', () {
    test('جمع هزینه‌ها بر اساس دسته', () {
      const cats = [Category(id: 'k1', name: 'سرور', kind: TxnKind.expense)];
      final withCat = [
        txn(kind: TxnKind.expense, amount: 400000).copyWith(categoryId: 'k1'),
        txn(kind: TxnKind.expense, amount: 100000),
      ];
      final byCat = Ledger.byCategory(withCat, cats);
      expect(byCat['سرور'], 400000);
      expect(byCat['بدون دسته'], 100000);
    });
  });

  group('رفع اشکالات', () {
    test('برگشت وجه نسیه نباید موجودی صندوق را کم کند', () {
      final cash = Ledger.summarize([
        txn(kind: TxnKind.income, amount: 1000000),
        txn(kind: TxnKind.refund, amount: 400000), // نقدی: از صندوق خارج شده
      ]);
      expect(cash.cashOut, 400000);

      final credit = Ledger.summarize([
        txn(kind: TxnKind.income, amount: 1000000, credit: true),
        txn(kind: TxnKind.refund, amount: 400000, credit: true), // نسیه: پولی جابه‌جا نشده
      ]);
      expect(credit.refunds, 400000, reason: 'سود از برگشت وجه کم می‌شود');
      expect(credit.cashOut, 0, reason: 'ولی از صندوق کم نمی‌شود');
      expect(credit.netCash, 0);
    });

    test('جست‌وجو با ارقام فارسی و گروه‌بندی کار می‌کند', () {
      final txns = [txn(kind: TxnKind.income, amount: 250000, note: 'فروش اشتراک')];
      expect(Ledger.filter(txns, search: '۲۵۰'), hasLength(1));
      expect(Ledger.filter(txns, search: '250'), hasLength(1));
      expect(Ledger.filter(txns, search: 'اشتراک'), hasLength(1));
      expect(Ledger.filter(txns, search: 'ناموجود'), isEmpty);
    });

    test('جست‌وجوی مبلغ اعشاری ارز', () {
      final txns = [txn(kind: TxnKind.income, amount: 15.5, currency: 'USDT', rate: 130000)];
      expect(Ledger.filter(txns, search: '15.5'), hasLength(1));
      expect(Ledger.filter(txns, search: '15'), hasLength(1));
    });

    test('بدهی اولیه در تفکیک ارز دیده می‌شود', () {
      final c = customer(opening: 100000);
      final txns = [
        txn(kind: TxnKind.income, amount: 20, currency: 'USD', rate: 130000, credit: true),
      ];
      final map = Ledger.customerCurrencyTotals(c, txns);
      expect(map['IRT'], 100000, reason: 'بدهی اولیه به تومان');
      expect(map['USD'], 20);
    });

    test('parseAmount با چند نقطه صفر نمی‌شود', () {
      expect(parseAmount('1.234.567'), 1234567);
      expect(parseAmount('۱۲٬۵۰۰'), 12500);
      expect(parseAmount('10.5'), 10.5);
      expect(parseAmount(''), 0);
    });
  });

  group('تفکیک دفترها', () {
    Txn inBook(Txn t, String bookId) => t.copyWith(bookId: bookId);

    test('خلاصه و فیلتر بر اساس دفتر', () {
      final txns = [
        inBook(txn(kind: TxnKind.income, amount: 1000000), BookIds.business),
        inBook(txn(kind: TxnKind.expense, amount: 300000), BookIds.personal),
        inBook(txn(kind: TxnKind.income, amount: 200000), BookIds.personal),
      ];

      expect(Ledger.summarize(txns).income, 1200000, reason: 'بدون فیلتر = همه');
      expect(Ledger.summarize(txns, bookId: BookIds.personal).income, 200000);
      expect(Ledger.summarize(txns, bookId: BookIds.personal).profit, -100000);
      expect(
        Ledger.filter(txns, bookId: BookIds.business).length,
        1,
      );
    });

    test('نمودار ماهانه هر دفتر جدا حساب می‌شود', () {
      final txns = [
        inBook(txn(kind: TxnKind.income, amount: 111, date: now), BookIds.business),
        inBook(txn(kind: TxnKind.income, amount: 222, date: now), BookIds.personal),
      ];
      final biz = Ledger.monthlySeries(txns, months: 2, endMonth: now, bookId: BookIds.business);
      final per = Ledger.monthlySeries(txns, months: 2, endMonth: now, bookId: BookIds.personal);
      expect(biz.last.income, 111);
      expect(per.last.income, 222);
    });

    test('ساختار دفترها در پشتیبان حفظ می‌شود', () {
      const s = AppSettings();
      expect(s.books.length, 2);
      expect(s.book(BookIds.personal).name, 'شخصی');
      expect(s.book('ناموجود').id, BookIds.business, reason: 'دفتر ناشناخته → دفتر پیش‌فرض');

      final restored = AppSettings.fromMap(s.toMap());
      expect(restored.books.length, 2);
      expect(restored.defaultBookId, BookIds.business);

      // تنظیمات قدیمی بدون فیلد books نباید خطا بدهد
      final legacy = AppSettings.fromMap({'businessName': 'قبلی'});
      expect(legacy.books.length, 2);
      expect(legacy.defaultBook, legacy.books.first);
    });

    test('تراکنش بدون bookId به کسب‌وکار نسبت داده می‌شود', () {
      final t = Txn.fromMap({
        'id': 't1',
        'kind': 'income',
        'amount': 10,
        'date': now.millisecondsSinceEpoch,
        'createdAt': now.millisecondsSinceEpoch,
      });
      expect(t.bookId, BookIds.business);
      expect(t.toMap()['bookId'], BookIds.business);
    });
  });
}
