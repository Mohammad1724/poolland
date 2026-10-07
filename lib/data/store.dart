import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/sms/bank_rules.dart';
import '../core/sms/sms_models.dart';
import 'models.dart';

/// Local storage layer built on Hive.
/// Three primary boxes plus the settings box.
class LocalStore {
  static const boxCustomers = 'customers';
  static const boxSubscriptions = 'subscriptions';
  static const boxTransactions = 'transactions';
  static const boxCategories = 'categories';
  static const boxPlans = 'plans';
  static const boxMeta = 'meta';
  // The v2 box uses compact SHA-256 message keys. The legacy box is left
  // untouched so a damaged review cache cannot block the ledger database.
  static const boxSmsState = 'sms_state_v2';
  static const boxSmsRules = 'sms_rules';
  static const boxBudgets = 'budgets';
  static const boxRecurring = 'recurring';
  static const boxQuick = 'quick_expenses';

  final Box customers;
  final Box subscriptions;
  final Box transactions;
  final Box categories;
  final Box plans;
  final Box meta;
  final Box smsState;
  final Box smsRules;
  final Box budgets;
  final Box recurring;
  final Box quickExpenses;

  LocalStore._({
    required this.customers,
    required this.subscriptions,
    required this.transactions,
    required this.categories,
    required this.plans,
    required this.meta,
    required this.smsState,
    required this.smsRules,
    required this.budgets,
    required this.recurring,
    required this.quickExpenses,
  });

  static const _uuid = Uuid();

  static String newId() => _uuid.v4();

  static Future<Box> _openBox(String name) async {
    try {
      return await Hive.openBox(name);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        StateError('Opening Hive box "$name" failed: $error'),
        stackTrace,
      );
    }
  }

  static Future<void> _ensureSeeded(LocalStore store) async {
    try {
      await store.ensureSeeded();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        StateError('Initializing local Hive data failed: $error'),
        stackTrace,
      );
    }
  }

  /// Open storage boxes on mobile or web.
  static Future<LocalStore> open() async {
    await Hive.initFlutter('vpn_ledger');
    final store = LocalStore._(
      customers: await _openBox(boxCustomers),
      subscriptions: await _openBox(boxSubscriptions),
      transactions: await _openBox(boxTransactions),
      categories: await _openBox(boxCategories),
      plans: await _openBox(boxPlans),
      meta: await _openBox(boxMeta),
      smsState: await _openBox(boxSmsState),
      smsRules: await _openBox(boxSmsRules),
      budgets: await _openBox(boxBudgets),
      recurring: await _openBox(boxRecurring),
      quickExpenses: await _openBox(boxQuick),
    );
    await _ensureSeeded(store);
    return store;
  }

  /// Open storage boxes at a specific path (for tests).
  static Future<LocalStore> openAt(String path) async {
    Hive.init(path);
    final store = LocalStore._(
      customers: await _openBox(boxCustomers),
      subscriptions: await _openBox(boxSubscriptions),
      transactions: await _openBox(boxTransactions),
      categories: await _openBox(boxCategories),
      plans: await _openBox(boxPlans),
      meta: await _openBox(boxMeta),
      smsState: await _openBox(boxSmsState),
      smsRules: await _openBox(boxSmsRules),
      budgets: await _openBox(boxBudgets),
      recurring: await _openBox(boxRecurring),
      quickExpenses: await _openBox(boxQuick),
    );
    await _ensureSeeded(store);
    return store;
  }

  /// Seed default categories, plans, settings, and quick buttons.
  Future<void> ensureSeeded() async {
    if (categories.isEmpty) {
      for (final c in defaultCategories()) {
        await categories.put(c.id, c.toMap());
      }
    }
    if (plans.isEmpty) {
      for (final p in defaultPlans()) {
        await plans.put(p.id, p.toMap());
      }
    }
    if (quickExpenses.isEmpty) {
      for (final q in QuickExpense.defaults()) {
        await quickExpenses.put(q.id, q.toMap());
      }
    }
    // Migration: add personal categories to existing databases.
    await _seedPersonalCategoriesOnce();
    if (!meta.containsKey('settings')) {
      await meta.put('settings', const AppSettings().toMap());
    }
    if (!meta.containsKey('createdAt')) {
      await meta.put('createdAt', DateTime.now().millisecondsSinceEpoch);
    }
  }

  static List<Category> defaultCategories() {
    final income = [
      'Subscription sales',
      'Single-user configuration sales',
      'Subscription renewals',
      'Support and setup',
      'Account and license sales',
    ];
    final expense = [
      'Server / VPS purchase',
      'Domain and SSL',
      'Control panel and license',
      'Advertising and marketing',
      'Payment gateway fees',
      'Internet and work tools',
      'Salaries and wages',
      'Other expenses',
    ];
    final out = <Category>[];
    var i = 0;
    for (final name in income) {
      out.add(
        Category(id: newId(), name: name, kind: TxnKind.income, sortOrder: i++),
      );
    }
    i = 0;
    for (final name in expense) {
      out.add(
        Category(
          id: newId(),
          name: name,
          kind: TxnKind.expense,
          sortOrder: i++,
        ),
      );
    }
    return out;
  }

  /// Categories for personal finance.
  static List<Category> personalCategories() {
    const expense = <String>[
      'Food and dining',
      'Transport and fuel',
      'Housing and rent',
      'Utilities (water, electricity, gas)',
      'Internet and mobile top-up',
      'Health and medical',
      'Education',
      'Leisure and entertainment',
      'Personal shopping and clothing',
      'Gifts and occasions',
      'Sports and gym',
      'Travel and trips',
      'Other personal expenses',
    ];
    const income = <String>[
      'Salary',
      'Freelance income',
      'Investment returns',
      'Gifts and support',
      'Refunds and reimbursements',
      'Other personal income',
    ];
    final out = <Category>[];
    var i = 0;
    for (final name in income) {
      out.add(
        Category(
          id: newId(),
          name: name,
          kind: TxnKind.income,
          sortOrder: i++,
          scope: TxnScope.personal,
        ),
      );
    }
    i = 0;
    for (final name in expense) {
      out.add(
        Category(
          id: newId(),
          name: name,
          kind: TxnKind.expense,
          sortOrder: i++,
          scope: TxnScope.personal,
        ),
      );
    }
    return out;
  }

  /// Add personal categories to an existing database once.
  Future<void> _seedPersonalCategoriesOnce() async {
    if (meta.get('personalCategoriesSeeded') == true) return;
    final existing = categories.values
        .map((e) => Category.fromMap(Map<String, dynamic>.from(e as Map)).name)
        .toSet();
    for (final c in personalCategories()) {
      if (existing.contains(c.name)) continue;
      await categories.put(c.id, c.toMap());
    }
    await meta.put('personalCategoriesSeeded', true);
  }

  /// Default sales plans.
  static List<Plan> defaultPlans() => [
    Plan(id: newId(), name: '1 month, 50 GB', price: 250000),
    Plan(id: newId(), name: '1 month, unlimited', price: 350000),
    Plan(
      id: newId(),
      name: '3 months, unlimited',
      price: 900000,
      durationValue: 3,
    ),
  ];

  // ---------- Read ----------
  List<Customer> loadCustomers() => customers.values
      .map((e) => Customer.fromMap(Map<String, dynamic>.from(e as Map)))
      .toList();

  List<Subscription> loadSubscriptions() => subscriptions.values
      .map((e) => Subscription.fromMap(Map<String, dynamic>.from(e as Map)))
      .toList();

  List<Txn> loadTxns() => transactions.values
      .map((e) => Txn.fromMap(Map<String, dynamic>.from(e as Map)))
      .toList();

  List<Category> loadCategories() =>
      categories.values
          .map((e) => Category.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList()
        ..sort((a, b) {
          final k = a.kind.index.compareTo(b.kind.index);
          return k != 0 ? k : a.sortOrder.compareTo(b.sortOrder);
        });

  List<Plan> loadPlans() =>
      plans.values
          .map((e) => Plan.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));

  AppSettings loadSettings() {
    final raw = meta.get('settings');
    if (raw is Map) return AppSettings.fromMap(Map<String, dynamic>.from(raw));
    return const AppSettings();
  }

  // ---------- Write ----------
  Future<void> putCustomer(Customer c) => customers.put(c.id, c.toMap());
  Future<void> deleteCustomer(String id) => customers.delete(id);

  Future<void> putSubscription(Subscription s) =>
      subscriptions.put(s.id, s.toMap());
  Future<void> deleteSubscription(String id) => subscriptions.delete(id);

  Future<void> putTxn(Txn t) => transactions.put(t.id, t.toMap());
  Future<void> deleteTxn(String id) => transactions.delete(id);

  Future<void> putCategory(Category c) => categories.put(c.id, c.toMap());
  Future<void> deleteCategory(String id) => categories.delete(id);

  Future<void> putPlan(Plan p) => plans.put(p.id, p.toMap());
  Future<void> deletePlan(String id) => plans.delete(id);

  Future<void> saveSettings(AppSettings s) => meta.put('settings', s.toMap());

  Future<void> clearAll() async {
    await customers.clear();
    await subscriptions.clear();
    await transactions.clear();
    await categories.clear();
    await plans.clear();
    await meta.clear();
    await smsState.clear();
    await smsRules.clear();
    await budgets.clear();
    await recurring.clear();
    await quickExpenses.clear();
    await ensureSeeded();
  }

  // ---------- Backups ----------
  /// All data as a Map (for JSON export).
  Map<String, dynamic> exportAll() => {
    'app': 'vpn_ledger',
    'schema': 1,
    'exportedAt': DateTime.now().toIso8601String(),
    'settings': loadSettings().toMap(
      includeDeviceNotificationSound: false,
      includePin: false,
    ),
    'customers': loadCustomers().map((e) => e.toMap()).toList(),
    'subscriptions': loadSubscriptions().map((e) => e.toMap()).toList(),
    'transactions': loadTxns().map((e) => e.toMap()).toList(),
    'categories': loadCategories().map((e) => e.toMap()).toList(),
    'plans': loadPlans().map((e) => e.toMap()).toList(),
    'smsRules': loadSmsRules().map((e) => e.toMap()).toList(),
    'budgets': loadBudgets().map((e) => e.toMap()).toList(),
    'recurring': loadRecurring().map((e) => e.toMap()).toList(),
    'quickExpenses': loadQuickExpenses().map((e) => e.toMap()).toList(),
  };

  /// Restore from a backup file. All records are parsed before existing data
  /// is touched, so an invalid file cannot leave the local ledger half-erased.
  Future<void> importAll(Map<String, dynamic> data) async {
    if (data['app'] != 'vpn_ledger') {
      throw const FormatException('This file is not a Poolland backup.');
    }
    final schema = (data['schema'] as num?)?.toInt() ?? 1;
    if (schema != 1) {
      throw FormatException('Unsupported backup schema: $schema.');
    }

    List<Map<String, dynamic>> parseRecords(String key) {
      final rawList = data[key];
      if (rawList == null) return <Map<String, dynamic>>[];
      if (rawList is! List) throw FormatException('Invalid "$key" data.');
      final records = <Map<String, dynamic>>[];
      final ids = <String>{};
      for (var i = 0; i < rawList.length; i++) {
        final raw = rawList[i];
        if (raw is! Map) {
          throw FormatException('Invalid "$key" record at index $i.');
        }
        final record = Map<String, dynamic>.from(raw);
        final id = '${record['id'] ?? ''}'.trim();
        if (id.isEmpty || !ids.add(id)) {
          throw FormatException(
            'Missing or duplicate ID in "$key" at index $i.',
          );
        }
        records.add(record);
      }
      return records;
    }

    List<T> decode<T>(String key, T Function(Map<String, dynamic>) fromMap) {
      final out = <T>[];
      for (final record in parseRecords(key)) {
        try {
          out.add(fromMap(record));
        } catch (error) {
          throw FormatException('Invalid "$key" record: $error');
        }
      }
      return out;
    }

    // The app lock stays with the phone, like the SMS review status below.
    // Otherwise an old backup would quietly switch the lock off, and a
    // backup from a phone whose PIN was forgotten would lock the user out.
    final localPinHash = loadSettings().pinHash;

    final settingsRaw = data['settings'];
    if (settingsRaw != null && settingsRaw is! Map) {
      throw const FormatException('Invalid settings data.');
    }
    final restoredSettings = settingsRaw is Map
        ? AppSettings.fromMap(Map<String, dynamic>.from(settingsRaw))
        : const AppSettings();
    final restoredCustomers = decode('customers', Customer.fromMap);
    final restoredSubscriptions = decode('subscriptions', Subscription.fromMap);
    final restoredTransactions = decode('transactions', Txn.fromMap);
    final restoredCategories = decode('categories', Category.fromMap);
    final restoredPlans = decode('plans', Plan.fromMap);
    final restoredSmsRules = decode('smsRules', BankRule.fromMap);
    final restoredBudgets = decode('budgets', Budget.fromMap);
    final restoredRecurring = decode('recurring', RecurringRule.fromMap);
    final restoredQuickExpenses = decode('quickExpenses', QuickExpense.fromMap);

    final customerIds = restoredCustomers.map((e) => e.id).toSet();
    if (restoredSubscriptions.any((s) => !customerIds.contains(s.customerId))) {
      throw const FormatException(
        'A subscription references a missing customer.',
      );
    }

    // All content is now validated; replacing the local data is safe to begin.
    await customers.clear();
    await subscriptions.clear();
    await transactions.clear();
    await categories.clear();
    await plans.clear();
    await meta.clear();
    await smsState
        .clear(); // Review status belongs to this device, not the backup.
    await smsRules.clear();
    await budgets.clear();
    await recurring.clear();
    await quickExpenses.clear();

    await meta.put(
      'settings',
      restoredSettings
          .copyWith(pinHash: localPinHash, clearPin: localPinHash == null)
          .toMap(),
    );
    for (final value in restoredCustomers) {
      await customers.put(value.id, value.toMap());
    }
    for (final value in restoredSubscriptions) {
      await subscriptions.put(value.id, value.toMap());
    }
    for (final value in restoredTransactions) {
      await transactions.put(value.id, value.toMap());
    }
    for (final value in restoredCategories) {
      await categories.put(value.id, value.toMap());
    }
    for (final value in restoredPlans) {
      await plans.put(value.id, value.toMap());
    }
    for (final value in restoredSmsRules) {
      await smsRules.put(value.id, value.toMap());
    }
    for (final value in restoredBudgets) {
      await budgets.put(value.id, value.toMap());
    }
    for (final value in restoredRecurring) {
      await recurring.put(value.id, value.toMap());
    }
    for (final value in restoredQuickExpenses) {
      await quickExpenses.put(value.id, value.toMap());
    }
    await ensureSeeded();
  }

  Future<void> close() async {
    await customers.close();
    await subscriptions.close();
    await transactions.close();
    await categories.close();
    await plans.close();
    await meta.close();
    await smsState.close();
    await smsRules.close();
    await budgets.close();
    await recurring.close();
    await quickExpenses.close();
  }

  // ---------- Bank SMS ----------
  /// Review status for each SMS: compact key → status.
  /// Possible statuses: approved | rejected.
  Map<String, String> loadSmsState() {
    final out = <String, String>{};
    for (final e in smsState.values) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final key = m['key'] as String?;
      final status = m['status'] as String?;
      if (key != null && status != null) out[key] = status;
    }
    return out;
  }

  /// Full local review history. Older status-only records remain valid for
  /// duplicate prevention but cannot be shown because their SMS body was not
  /// stored by earlier app versions.
  List<SmsHistoryEntry> loadSmsHistory() {
    final out = <SmsHistoryEntry>[];
    for (final e in smsState.values) {
      if (e is! Map) continue;
      try {
        final m = Map<String, dynamic>.from(e);
        final status = m['status'];
        if (status != SmsHistoryEntry.approvedStatus &&
            status != SmsHistoryEntry.rejectedStatus) {
          continue;
        }
        if (m['message'] is! Map) continue;
        out.add(SmsHistoryEntry.fromMap(m));
      } catch (_) {
        // A malformed history entry should not prevent the SMS feature from
        // loading or block the rest of the local database.
      }
    }
    return out..sort((a, b) => b.reviewedAt.compareTo(a.reviewedAt));
  }

  Future<void> setSmsState(
    String key,
    String status, {
    SmsHistoryEntry? history,
  }) {
    final previous = smsState.get(key);
    final record = previous is Map
        ? Map<String, dynamic>.from(previous)
        : <String, dynamic>{};
    if (history != null) record.addAll(history.toMap());
    record.addAll({
      'key': key,
      'status': status,
      'at': DateTime.now().millisecondsSinceEpoch,
    });
    return smsState.put(key, record);
  }

  Future<void> clearSmsState() => smsState.clear();

  /// Custom rules for banks not included in the built-in list.
  List<BankRule> loadSmsRules() {
    final out = <BankRule>[];
    for (final e in smsRules.values) {
      if (e is! Map) continue;
      out.add(BankRule.fromMap(Map<String, dynamic>.from(e)));
    }
    return out;
  }

  Future<void> putSmsRule(BankRule rule) => smsRules.put(rule.id, rule.toMap());

  Future<void> deleteSmsRule(String id) => smsRules.delete(id);

  // ---------- Personal finance ----------
  List<Budget> loadBudgets() {
    final out = <Budget>[];
    for (final e in budgets.values) {
      if (e is! Map) continue;
      out.add(Budget.fromMap(Map<String, dynamic>.from(e)));
    }
    return out;
  }

  Future<void> putBudget(Budget b) => budgets.put(b.id, b.toMap());

  Future<void> deleteBudget(String id) => budgets.delete(id);

  List<RecurringRule> loadRecurring() {
    final out = <RecurringRule>[];
    for (final e in recurring.values) {
      if (e is! Map) continue;
      out.add(RecurringRule.fromMap(Map<String, dynamic>.from(e)));
    }
    return out;
  }

  Future<void> putRecurring(RecurringRule r) => recurring.put(r.id, r.toMap());

  Future<void> deleteRecurring(String id) => recurring.delete(id);

  List<QuickExpense> loadQuickExpenses() {
    final out = <QuickExpense>[];
    for (final e in quickExpenses.values) {
      if (e is! Map) continue;
      out.add(QuickExpense.fromMap(Map<String, dynamic>.from(e)));
    }
    return out..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  Future<void> putQuickExpense(QuickExpense q) =>
      quickExpenses.put(q.id, q.toMap());

  Future<void> deleteQuickExpense(String id) => quickExpenses.delete(id);
}
