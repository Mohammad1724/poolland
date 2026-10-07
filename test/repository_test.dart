import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/core/jalali_utils.dart';
import 'package:poolland/core/sms/bank_rules.dart';
import 'package:poolland/core/sms/sms_models.dart';
import 'package:poolland/core/sms/sms_parser.dart';
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
    expect(repo.settings.languageCode, 'fa');
    expect(repo.scopeFilter, TxnScope.business);
  });

  test('SMS rule enablement defaults on and persists per rule', () async {
    expect(repo.isSmsRuleEnabled('melat'), isTrue);
    expect(
      AppSettings.fromMap({'smsEnabled': true}).disabledSmsRuleIds,
      isEmpty,
      reason: 'Legacy settings keep every built-in rule enabled',
    );

    final sms = SmsParser.parse(
      SmsMessage(
        id: 'mellat-pending',
        address: 'BANKMELAT',
        body: 'واریز مبلغ 100,000 ریال',
        date: J.today,
      ),
    );
    repo.smsSuggestions = [sms];

    await repo.setSmsRuleEnabled('melat', false);
    expect(repo.isSmsRuleEnabled('melat'), isFalse);
    expect(repo.settings.disabledSmsRuleIds, contains('melat'));
    expect(repo.smsSuggestions, isEmpty);
    expect(
      repo.transactions,
      isEmpty,
      reason: 'Changing a rule never records a transaction',
    );

    await repo.reload();
    expect(repo.isSmsRuleEnabled('melat'), isFalse);
    await repo.setSmsRuleEnabled('melat', true);
    expect(repo.isSmsRuleEnabled('melat'), isTrue);
    expect(repo.settings.disabledSmsRuleIds, isNot(contains('melat')));
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
    expect(
      repo.balanceOf(fresh),
      300000,
      reason: '500 credit sale − 200 received',
    );
    expect(repo.transactions.length, 2);
    expect(repo.subsOfCustomer(customer.id).length, 1);

    final s = repo.summary();
    expect(s.income, 200000);
    expect(s.sales, 500000);
    expect(s.received, 200000);
    expect(s.profit, 200000);
    expect(s.cashIn, 200000);
  });

  test('An unrecognized SMS cannot be approved as a transaction', () async {
    final sms = SmsParser.parse(
      SmsMessage(
        id: 'unknown-sms',
        address: 'UNKNOWN-SENDER',
        body: 'واریز مبلغ 100,000 تومان',
        date: J.today,
      ),
    );

    expect(sms.isTransaction, isFalse);
    expect(
      await repo.approveSms(sms, scope: TxnScope.business),
      isNull,
    );
    expect(repo.transactions, isEmpty);
  });

  test('A received SMS is recorded in the selected personal scope', () async {
    final incomeCategory = repo
        .categoriesOf(TxnKind.income, scope: TxnScope.personal)
        .first;
    final businessCategory = repo.categoriesOf(TxnKind.income).first;
    final sms = SmsParser.parse(
      SmsMessage(
        id: 'personal-sms',
        address: 'BANKMELAT',
        body: 'واریز مبلغ 100,000 تومان',
        date: J.today,
      ),
    );

    final txn = (await repo.approveSms(
      sms,
      kind: TxnKind.income,
      categoryId: businessCategory.id,
      scope: TxnScope.personal,
    ))!;

    expect(txn.scope, TxnScope.personal);
    expect(txn.kind, TxnKind.income);
    expect(txn.categoryId, incomeCategory.id);
    expect(repo.summary(scope: TxnScope.personal).income, 100000);
    expect(repo.summary(scope: TxnScope.business).income, 0);
    expect(store.loadSmsState(), containsPair(sms.key, 'approved'));
    expect(repo.smsHistory, hasLength(1));
    expect(repo.smsHistory.single.wasRecorded, isTrue);
    expect(repo.smsHistory.single.message.body, sms.message.body);
    expect(repo.smsHistory.single.transactionId, txn.id);
    expect(sms.key, matches(RegExp(r'^v2:[0-9a-f]{64}$')));
  });

  test('Rejected SMS remains in review history but creates no transaction', () async {
    final sms = SmsParser.parse(
      SmsMessage(
        id: 'rejected-sms',
        address: 'BANKMELAT',
        body: 'برداشت مبلغ 75,000 تومان',
        date: J.today,
      ),
    );
    repo.smsSuggestions = [sms];

    await repo.rejectSms(sms);

    expect(repo.smsSuggestions, isEmpty);
    expect(repo.smsHistory, hasLength(1));
    expect(repo.smsHistory.single.wasRejected, isTrue);
    expect(repo.smsHistory.single.message.body, sms.message.body);
    expect(repo.transactions, isEmpty);
    expect(
      store.exportAll().keys,
      isNot(contains('smsState')),
      reason: 'Review history stays on the device and out of backups',
    );
  });

  test('A customer SMS receipt clears debt and is recognized as income', () async {
    final customer = await repo.addCustomer(
      name: 'SMS customer',
      bankIdentifiers: ['1234'],
    );
    await repo.sellSubscription(
      customer: customer,
      title: 'One month VPN',
      price: 500000,
      currencyCode: 'IRT',
      start: J.today,
      end: J.addDays(J.today, 30),
    );
    final incomeCategory = repo.categoriesOf(TxnKind.income).first;
    final sms = SmsParser.parse(
      SmsMessage(
        id: 'business-sms',
        address: 'BANKMELAT',
        body: 'واریز مبلغ 200,000 تومان کارت 6104********1234',
        date: J.today,
      ),
    );

    final txn = (await repo.approveSms(
      sms,
      categoryId: incomeCategory.id,
      amount: 200000,
      scope: TxnScope.business,
    ))!;

    expect(txn.kind, TxnKind.receive);
    expect(txn.scope, TxnScope.business);
    expect(txn.categoryId, incomeCategory.id);
    expect(repo.balanceOf(repo.customerById(customer.id)!), 300000);
    expect(repo.summary(scope: TxnScope.business).income, 200000);
    expect(repo.summary(scope: TxnScope.business).sales, 500000);
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
    final renewed = await repo.renewSubscription(
      first,
      price: 350000,
      received: 350000,
    );

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
      date: J.today,
    );

    expect(repo.balanceOf(repo.customerById(customer.id)!), 250000);
    expect(repo.totals.receivable, 250000);
  });

  test('Partial payment of a credit expense reduces payable without double expense', () async {
    final vendor = await repo.addCustomer(name: 'Server vendor');
    await repo.addTxn(
      repo.buildTxn(
        kind: TxnKind.expense,
        amount: 100000,
        currency: 'IRT',
        date: J.today,
        customerId: vendor.id,
        credit: true,
        categoryId: repo.defaultExpenseCategoryId,
        note: 'Server invoice',
      ),
    );
    await repo.addPayment(
      customer: repo.customerById(vendor.id)!,
      amount: 40000,
      currencyCode: 'IRT',
      date: J.today,
      isReceive: false,
    );

    final current = repo.customerById(vendor.id)!;
    final summary = repo.summary();
    expect(repo.balanceOf(current), -60000);
    expect(summary.expense, 100000);
    expect(summary.profit, -100000);
    expect(summary.cashOut, 40000);
    expect(
      repo.transactions.any((t) => t.kind == TxnKind.payablePayment),
      isTrue,
    );
  });

  test('Language preference survives backup restoration', () async {
    await repo.updateSettings(repo.settings.copyWith(languageCode: 'en'));
    final backup = repo.exportData();
    await repo.wipeAll();
    await repo.importData(backup);

    expect(repo.settings.languageCode, 'en');
  });

  test('Device notification sound is saved locally but omitted from backups', () async {
    const soundUri = 'content://media/external/audio/media/123';
    await repo.updateSettings(
      repo.settings.copyWith(
        notificationSoundUri: soundUri,
        notificationSoundName: 'Custom tone',
      ),
    );

    expect(repo.settings.notificationSoundUri, soundUri);
    final backup = repo.exportData();
    final backupSettings = Map<String, dynamic>.from(backup['settings'] as Map);
    expect(backupSettings.containsKey('notificationSoundUri'), isFalse);
    expect(backupSettings.containsKey('notificationSoundName'), isFalse);

    await repo.reload();
    expect(repo.settings.notificationSoundUri, soundUri);
  });

  test('Invalid backup is rejected without erasing current data', () async {
    final customer = await repo.addCustomer(name: 'Keep me');
    await expectLater(
      repo.importData({'app': 'not_poolland', 'schema': 1}),
      throwsFormatException,
    );
    expect(repo.customerById(customer.id)?.name, 'Keep me');
  });

  test(
    'Deleting a customer without data keeps history but detaches references',
    () async {
      final customer = await repo.addCustomer(name: 'Archive customer');
      final subscription = await repo.sellSubscription(
        customer: customer,
        title: 'One month',
        price: 250000,
        currencyCode: 'IRT',
        start: J.today,
        end: J.addDays(J.today, 30),
        received: 100000,
      );
      await repo.deleteCustomer(customer.id, withData: false);

      expect(repo.customerById(customer.id), isNull);
      expect(repo.subscriptions.any((s) => s.id == subscription.id), isFalse);
      expect(repo.transactions, hasLength(2));
      expect(repo.transactions.every((t) => t.customerId == null), isTrue);
      expect(repo.transactions.every((t) => t.subscriptionId == null), isTrue);
    },
  );

  test(
    'Deleting a subscription preserves and unlinks financial history',
    () async {
      final customer = await repo.addCustomer(name: 'Keep the sale');
      final subscription = await repo.sellSubscription(
        customer: customer,
        title: 'One month',
        price: 250000,
        currencyCode: 'IRT',
        start: J.today,
        end: J.addDays(J.today, 30),
        received: 100000,
      );
      final originalTransactionCount = repo.transactions.length;

      await repo.deleteSubscription(subscription.id);

      expect(repo.subscriptions.any((s) => s.id == subscription.id), isFalse);
      expect(repo.transactions, hasLength(originalTransactionCount));
      expect(repo.transactions.every((t) => t.subscriptionId == null), isTrue);
      expect(repo.balanceOf(repo.customerById(customer.id)!), 150000);
    },
  );

  test(
    'Deleting a plan in use archives it so renewals retain the duration',
    () async {
      final plan = await repo.addPlan(
        const Plan(
          id: 'archive-plan',
          name: 'Three months',
          price: 300000,
          durationValue: 3,
        ),
      );
      final customer = await repo.addCustomer(name: 'Renewal customer');
      final subscription = await repo.sellSubscription(
        customer: customer,
        plan: plan,
        title: plan.name,
        price: plan.price,
        currencyCode: plan.currency,
        start: J.today,
        end: plan.endFrom(J.today),
      );

      await repo.deletePlan(plan.id);
      expect(repo.planById(plan.id)?.archived, isTrue);
      final renewed = await repo.renewSubscription(subscription);
      expect(renewed.durationDays, greaterThan(85));
    },
  );

  test(
    'Recurring posting is idempotent after a stale last-posted marker',
    () async {
      final now = DateTime(2026, 10, 3);
      final rule = RecurringRule(
        id: 'daily-test-rule',
        title: 'Daily expense',
        kind: TxnKind.expense,
        amount: 1000,
        scope: TxnScope.personal,
        period: RecurringPeriod.daily,
        startDate: DateTime(2026, 10, 1),
      );
      await repo.addRecurring(rule);

      expect(await repo.postDueRecurring(now: now), 3);
      await repo.updateRecurring(
        rule,
      ); // Simulate a crash before lastPosted was saved.
      expect(await repo.postDueRecurring(now: now), 0);
      expect(
        repo.transactions.where((t) => t.note == 'Daily expense'),
        hasLength(3),
      );
    },
  );

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
    final plan = await repo.addPlan(
      const Plan(id: 'x', name: 'Custom plan', price: 123456, durationValue: 2),
    );
    expect(repo.plans.any((p) => p.id == plan.id), isTrue);

    final backup = repo.exportData();
    await repo.wipeAll();
    await repo.importData(backup);

    expect(
      repo.plans.any((p) => p.id == plan.id),
      isTrue,
      reason: 'User plans should not be lost during restoration',
    );
  });

  test('Custom SMS rules are saved and restored', () async {
    await repo.addSmsRule(
      const BankRule(id: 'r1', bankName: 'My Bank', senderHints: ['MYBANK']),
    );
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
        .where(
          (t) => t.customerId != null && !customerIds.contains(t.customerId),
        )
        .length;
    expect(
      orphans,
      0,
      reason: 'No transaction should reference a deleted customer',
    );

    final planIds = repo.plans.map((p) => p.id).toSet();
    final badPlans = repo.subscriptions
        .where((s) => s.planId != null && !planIds.contains(s.planId))
        .length;
    expect(
      badPlans,
      0,
      reason:
          'Every subscription should reference a valid plan '
          '(otherwise one-tap renewal will fail)',
    );

    final categoryIds = repo.categories.map((c) => c.id).toSet();
    final badCategories = repo.transactions
        .where(
          (t) => t.categoryId != null && !categoryIds.contains(t.categoryId),
        )
        .length;
    expect(
      badCategories,
      0,
      reason: 'Sample transactions should reference valid categories',
    );
  });

  test('Sample data loads', () async {
    await repo.loadDemoData();
    expect(repo.customers.length, greaterThan(5));
    expect(repo.transactions.length, greaterThan(20));
    expect(repo.summary().income, greaterThan(0));
    expect(repo.totals.receivable, greaterThan(0));
  });

  test('Exchange rates are saved in settings', () async {
    await repo.upsertCurrency(
      const CurrencyDef(
        code: 'AED',
        name: 'UAE Dirham',
        symbol: 'AED',
        rateToBase: 35000,
        decimals: 2,
      ),
    );
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
