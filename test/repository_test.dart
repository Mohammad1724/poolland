import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/core/jalali_utils.dart';
import 'package:poolland/data/models.dart';
import 'package:poolland/data/repository.dart';
import 'package:poolland/data/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late LocalStore store;
  late AppRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('vpnledger_test');
    store = await LocalStore.openAt(tmp.path);
    repo = AppRepository(store: store);
    await repo.reload();
  });

  tearDown(() async {
    await store.close();
    await tmp.delete(recursive: true);
  });

  test('داده‌های اولیه ساخته می‌شوند', () {
    expect(repo.categoriesOf(TxnKind.income), isNotEmpty);
    expect(repo.categoriesOf(TxnKind.expense), isNotEmpty);
    expect(repo.plans, isNotEmpty);
    expect(repo.settings.baseCurrency, 'IRT');
  });

  test('ثبت فروش: درآمد + بدهی مشتری + دریافت نقدی', () async {
    final customer = await repo.addCustomer(name: 'رضا');
    await repo.sellSubscription(
      customer: customer,
      title: 'یک ماهه ۵۰ گیگ',
      price: 500000,
      currencyCode: 'IRT',
      start: J.today,
      end: J.addDays(J.addMonths(J.today, 1), -1),
      received: 200000,
    );

    final fresh = repo.customerById(customer.id)!;
    expect(repo.balanceOf(fresh), 300000, reason: '۵۰۰ فروش نسیه − ۲۰۰ دریافت');
    expect(repo.transactions.length, 2);
    expect(repo.subsOfCustomer(customer.id).length, 1);

    final s = repo.summary();
    expect(s.income, 500000);
    expect(s.received, 200000);
    expect(s.profit, 500000);
    expect(s.cashIn, 200000);
  });

  test('تمدید اشتراک از فردای تاریخ پایان ساخته می‌شود', () async {
    final customer = await repo.addCustomer(name: 'مریم');
    final first = await repo.sellSubscription(
      customer: customer,
      title: 'یک ماهه',
      price: 300000,
      currencyCode: 'IRT',
      start: J.today,
      end: J.addDays(J.addMonths(J.today, 1), -1),
    );
    final renewed = await repo.renewSubscription(first, price: 350000, received: 350000);

    expect(renewed.startDate, J.addDays(first.endDate, 1));
    expect(repo.subsOfCustomer(customer.id).length, 2);
    expect(repo.balanceOf(repo.customerById(customer.id)!), 300000);
  });

  test('دریافت وجه بدهی را کم می‌کند', () async {
    final customer = await repo.addCustomer(name: 'حسین');
    await repo.sellSubscription(
      customer: customer,
      title: 'سرویس',
      price: 400000,
      currencyCode: 'IRT',
      start: J.today,
      end: J.addDays(J.today, 30),
    );
    await repo.addPayment(
        customer: repo.customerById(customer.id)!,
        amount: 150000,
        currencyCode: 'IRT',
        date: J.today);

    expect(repo.balanceOf(repo.customerById(customer.id)!), 250000);
    expect(repo.totals.receivable, 250000);
  });

  test('پشتیبان‌گیری و بازگردانی (JSON)', () async {
    final c = await repo.addCustomer(name: 'سارا', phone: '09120000000');
    await repo.sellSubscription(
      customer: c,
      title: 'اشتراک',
      price: 100000,
      currencyCode: 'IRT',
      start: J.today,
      end: J.addDays(J.today, 30),
    );
    final backup = repo.exportData();

    await repo.wipeAll();
    expect(repo.customers, isEmpty);

    await repo.importData(backup);
    expect(repo.customers.length, 1);
    expect(repo.transactions.length, 1);
    expect(repo.customerById(c.id)!.name, 'سارا');
    expect(repo.balanceOf(repo.customerById(c.id)!), 100000);
  });

  test('داده‌ی نمونه بارگذاری می‌شود', () async {
    await repo.loadDemoData();
    expect(repo.customers.length, greaterThan(5));
    expect(repo.transactions.length, greaterThan(20));
    expect(repo.summary().income, greaterThan(0));
    expect(repo.totals.receivable, greaterThan(0));
  });

  test('نرخ ارز در تنظیمات ذخیره می‌شود', () async {
    await repo.upsertCurrency(const CurrencyDef(
        code: 'AED', name: 'درهم', symbol: 'د.ا', rateToBase: 35000, decimals: 2));
    expect(repo.settings.currency('AED').rateToBase, 35000);

    final t = repo.buildTxn(
      kind: TxnKind.income,
      amount: 100,
      currency: 'AED',
      date: J.today,
    );
    expect(t.rateToBase, 35000);
  });

  // ---------------- دفترها (شخصی / کسب‌وکار) ----------------
  group('دفترها', () {
    test('دو دفتر پیش‌فرض وجود دارد و داده‌های قدیمی کسب‌وکار هستند', () {
      expect(repo.settings.books.length, 2);
      expect(repo.settings.defaultBookId, BookIds.business);
      // تراکنش قدیمی بدون bookId باید کسب‌وکار خوانده شود
      final old = Txn.fromMap({
        'id': 'x1',
        'kind': 'expense',
        'amount': 1000,
        'date': J.today.millisecondsSinceEpoch,
        'createdAt': J.today.millisecondsSinceEpoch,
      });
      expect(old.bookId, BookIds.business);
    });

    test('سود کسب‌وکار و شخصی از هم جدا می‌شود', () async {
      await repo.addTxn(repo.buildTxn(
        kind: TxnKind.income,
        amount: 1000000,
        currency: 'IRT',
        date: J.today,
        bookId: BookIds.business,
      ));
      await repo.addTxn(repo.buildTxn(
        kind: TxnKind.expense,
        amount: 250000,
        currency: 'IRT',
        date: J.today,
        bookId: BookIds.personal,
      ));

      expect(repo.summary().profit, 750000, reason: 'بدون فیلتر: هر دو دفتر');
      expect(repo.summary(bookId: BookIds.business).profit, 1000000);
      expect(repo.summary(bookId: BookIds.personal).profit, -250000);

      repo.setBookFilter(BookIds.personal);
      expect(repo.isBookFiltered, isTrue);
      expect(repo.visibleTxns.length, 1);
      expect(repo.summary().profit, -250000, reason: 'خلاصه باید از فیلتر دفتر پیروی کند');
      // تراکنش جدید در همان دفتر فعال ساخته می‌شود
      expect(repo.newTxnBookId, BookIds.personal);
      expect(repo.buildTxn(
              kind: TxnKind.expense, amount: 1, currency: 'IRT', date: J.today)
          .bookId, BookIds.personal);

      repo.setBookFilter(null);
      expect(repo.isBookFiltered, isFalse);
      expect(repo.visibleTxns.length, 2);
    });

    test('خلاصه‌ی هر دفتر و مجموع آن‌ها', () async {
      await repo.addTxn(repo.buildTxn(
          kind: TxnKind.income, amount: 500, currency: 'IRT', date: J.today, bookId: BookIds.business));
      await repo.addTxn(repo.buildTxn(
          kind: TxnKind.income, amount: 300, currency: 'IRT', date: J.today, bookId: BookIds.personal));

      final rows = repo.summaryByBook();
      expect(rows.length, 2);
      final total = rows.fold<double>(0, (a, e) => a + e.value.income);
      expect(total, 800);
      expect(repo.summary().income, 800, reason: 'مجموع دفترها = خلاصه‌ی کل');
    });

    test('افزودن، تغییر نام و حذف دفتر', () async {
      await repo.addBook('خانه', color: 0xFF2563EB);
      final home = repo.settings.books.firstWhere((b) => b.name == 'خانه');
      expect(repo.settings.books.length, 3);

      await repo.upsertBook(home.copyWith(name: 'خانه و زندگی'));
      expect(repo.bookName(home.id), 'خانه و زندگی');

      // دفتر پیش‌فرض قابل حذف نیست
      await repo.removeBook(BookIds.business);
      expect(repo.settings.books.length, 3);

      // تراکنش‌های دفتر حذف‌شده به دفتر پیش‌فرض می‌روند
      await repo.addTxn(repo.buildTxn(
          kind: TxnKind.expense, amount: 700, currency: 'IRT', date: J.today, bookId: home.id));
      await repo.removeBook(home.id);
      expect(repo.settings.books.length, 2);
      expect(repo.summary().expense, 700);
    });

    test('انتقال گروهی تراکنش به دفتر دیگر', () async {
      final t = await repo.addTxn(repo.buildTxn(
          kind: TxnKind.expense, amount: 900, currency: 'IRT', date: J.today));
      expect(t.bookId, BookIds.business);
      await repo.moveTxnsToBook([t.id], BookIds.personal);
      expect(repo.transactions.first.bookId, BookIds.personal);
    });

    test('پشتیبان‌گیری، دفترها را حفظ می‌کند', () async {
      await repo.addBook('خانه');
      final backup = repo.exportData();
      await repo.wipeAll();
      await repo.importData(backup);
      expect(repo.settings.books.length, 3);
      expect(repo.bookName(repo.settings.defaultBookId), 'کسب‌وکار');
    });
  });
}
