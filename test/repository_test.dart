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
}
