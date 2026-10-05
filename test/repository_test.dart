import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/core/jalali_utils.dart';
import 'package:poolland/core/sms/bank_rules.dart';
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

  test('Initial data is seeded', () {
    expect(repo.categoriesOf(TxnKind.income), isNotEmpty);
    expect(repo.categoriesOf(TxnKind.expense), isNotEmpty);
    expect(repo.plans, isNotEmpty);
    expect(repo.settings.baseCurrency, 'IRT');
  });

  test('Sale records income, customer debt, and cash received', () async {
    final customer = await repo.addCustomer(name: 'Reza');
    await repo.sellSubscription(
      customer: customer,
      title: 'One month, 50 GB',
      price: 500000,
      currencyCode: 'IRT',
      start: J.today,
      end: J.addDays(J.addMonths(J.today, 1), -1),
      received: 200000,
    );

    final fresh = repo.customerById(customer.id)!;
    expect(repo.balanceOf(fresh), 300000, reason: '500 credit sale − 200 received');
    expect(repo.transactions.length, 2);
    expect(repo.subsOfCustomer(customer.id).length, 1);

    final s = repo.summary();
    expect(s.income, 500000);
    expect(s.received, 200000);
    expect(s.profit, 500000);
    expect(s.cashIn, 200000);
  });

  test('Renewal starts the day after the previous subscription ends', () async {
    final customer = await repo.addCustomer(name: 'Maryam');
    final first = await repo.sellSubscription(
      customer: customer,
      title: 'One month',
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

  test('A customer payment reduces their balance', () async {
    final customer = await repo.addCustomer(name: 'Hossein');
    await repo.sellSubscription(
      customer: customer,
      title: 'Service',
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

  test('JSON backup and restore', () async {
    final c = await repo.addCustomer(name: 'Sara', phone: '09120000000');
    await repo.sellSubscription(
      customer: c,
      title: 'Subscription',
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
    expect(repo.customerById(c.id)!.name, 'Sara');
    expect(repo.balanceOf(repo.customerById(c.id)!), 100000);
  });

  test('Custom plans survive backup restoration', () async {
    final plan = await repo.addPlan(const Plan(
        id: 'x', name: 'Custom plan', price: 123456, durationValue: 2));
    expect(repo.plans.any((p) => p.id == plan.id), isTrue);

    final backup = repo.exportData();
    await repo.wipeAll();
    await repo.importData(backup);

    expect(repo.plans.any((p) => p.id == plan.id), isTrue,
        reason: 'User plans should not be lost during restoration');
  });

  test('Custom SMS rules are saved and restored', () async {
    await repo.addSmsRule(const BankRule(
        id: 'r1', bankName: 'My Bank', senderHints: ['MYBANK']));
    expect(repo.smsRules.length, 1);

    final backup = repo.exportData();
    await repo.wipeAll();
    await repo.importData(backup);
    expect(repo.smsRules.length, 1);
    expect(repo.smsRules.first.bankName, 'My Bank');

    await repo.deleteSmsRule('r1');
    expect(repo.smsRules, isEmpty);
  });

  test('Sample data references are valid (no orphan records)', () async {
    await repo.loadDemoData();

    final customerIds = repo.customers.map((c) => c.id).toSet();
    final orphans = repo.transactions
        .where((t) => t.customerId != null && !customerIds.contains(t.customerId))
        .length;
    expect(orphans, 0,
        reason: 'No transaction should reference a deleted customer');

    final planIds = repo.plans.map((p) => p.id).toSet();
    final badPlans = repo.subscriptions
        .where((s) => s.planId != null && !planIds.contains(s.planId))
        .length;
    expect(badPlans, 0,
        reason: 'Every subscription should reference a valid plan '
            '(otherwise one-tap renewal will fail)');

    final categoryIds = repo.categories.map((c) => c.id).toSet();
    final badCategories = repo.transactions
        .where((t) => t.categoryId != null && !categoryIds.contains(t.categoryId))
        .length;
    expect(badCategories, 0,
        reason: 'Sample transactions should reference valid categories');
  });

  test('Sample data loads', () async {
    await repo.loadDemoData();
    expect(repo.customers.length, greaterThan(5));
    expect(repo.transactions.length, greaterThan(20));
    expect(repo.summary().income, greaterThan(0));
    expect(repo.totals.receivable, greaterThan(0));
  });

  test('Exchange rates are saved in settings', () async {
    await repo.upsertCurrency(const CurrencyDef(
        code: 'AED', name: 'UAE Dirham', symbol: 'AED', rateToBase: 35000, decimals: 2));
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
