import 'package:hive_ce_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/sms/bank_rules.dart';
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
  static const boxSmsState = 'sms_state';
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

  /// Open storage boxes on mobile or web.
  static Future<LocalStore> open() async {
    await Hive.initFlutter('vpn_ledger');
    final store = LocalStore._(
      customers: await Hive.openBox(boxCustomers),
      subscriptions: await Hive.openBox(boxSubscriptions),
      transactions: await Hive.openBox(boxTransactions),
      categories: await Hive.openBox(boxCategories),
      plans: await Hive.openBox(boxPlans),
      meta: await Hive.openBox(boxMeta),
      smsState: await Hive.openBox(boxSmsState),
      smsRules: await Hive.openBox(boxSmsRules),
      budgets: await Hive.openBox(boxBudgets),
      recurring: await Hive.openBox(boxRecurring),
      quickExpenses: await Hive.openBox(boxQuick),
    );
    await store.ensureSeeded();
    return store;
  }

  /// Open storage boxes at a specific path (for tests).
  static Future<LocalStore> openAt(String path) async {
    Hive.init(path);
    final store = LocalStore._(
      customers: await Hive.openBox(boxCustomers),
      subscriptions: await Hive.openBox(boxSubscriptions),
      transactions: await Hive.openBox(boxTransactions),
      categories: await Hive.openBox(boxCategories),
      plans: await Hive.openBox(boxPlans),
      meta: await Hive.openBox(boxMeta),
      smsState: await Hive.openBox(boxSmsState),
      smsRules: await Hive.openBox(boxSmsRules),
      budgets: await Hive.openBox(boxBudgets),
      recurring: await Hive.openBox(boxRecurring),
      quickExpenses: await Hive.openBox(boxQuick),
    );
    await store.ensureSeeded();
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
      out.add(Category(id: newId(), name: name, kind: TxnKind.income, sortOrder: i++));
    }
    i = 0;
    for (final name in expense) {
      out.add(Category(id: newId(), name: name, kind: TxnKind.expense, sortOrder: i++));
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
      out.add(Category(
          id: newId(),
          name: name,
          kind: TxnKind.income,
          sortOrder: i++,
          scope: TxnScope.personal));
    }
    i = 0;
    for (final name in expense) {
      out.add(Category(
          id: newId(),
          name: name,
          kind: TxnKind.expense,
          sortOrder: i++,
          scope: TxnScope.personal));
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
            durationValue: 3),
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

  List<Category> loadCategories() => categories.values
      .map((e) => Category.fromMap(Map<String, dynamic>.from(e as Map)))
      .toList()
    ..sort((a, b) {
      final k = a.kind.index.compareTo(b.kind.index);
      return k != 0 ? k : a.sortOrder.compareTo(b.sortOrder);
    });

  List<Plan> loadPlans() => plans.values
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

  Future<void> putSubscription(Subscription s) => subscriptions.put(s.id, s.toMap());
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
        'settings': loadSettings().toMap(),
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

  /// Restore from a backup file.
  Future<void> importAll(Map<String, dynamic> data) async {
    await customers.clear();
    await subscriptions.clear();
    await transactions.clear();
    await categories.clear();
    await plans.clear();
    await meta.clear();

    final s = data['settings'];
    if (s is Map) {
      await meta.put('settings', Map<String, dynamic>.from(s));
    } else {
      await meta.put('settings', const AppSettings().toMap());
    }

    for (final raw in (data['customers'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(raw as Map);
      await customers.put('${m['id']}', m);
    }
    for (final raw in (data['subscriptions'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(raw as Map);
      await subscriptions.put('${m['id']}', m);
    }
    for (final raw in (data['transactions'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(raw as Map);
      await transactions.put('${m['id']}', m);
    }
    for (final raw in (data['categories'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(raw as Map);
      await categories.put('${m['id']}', m);
    }
    for (final raw in (data['plans'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(raw as Map);
      await plans.put('${m['id']}', m);
    }
    for (final raw in (data['smsRules'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(raw as Map);
      await smsRules.put('${m['id']}', m);
    }
    for (final raw in (data['budgets'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(raw as Map);
      await budgets.put('${m['id']}', m);
    }
    for (final raw in (data['recurring'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(raw as Map);
      await recurring.put('${m['id']}', m);
    }
    for (final raw in (data['quickExpenses'] as List? ?? const [])) {
      final m = Map<String, dynamic>.from(raw as Map);
      await quickExpenses.put('${m['id']}', m);
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
  /// Review status for each SMS: key → status.
  /// Possible statuses: approved | rejected | ignored.
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

  Future<void> setSmsState(String key, String status) => smsState.put(
      key, {'key': key, 'status': status, 'at': DateTime.now().millisecondsSinceEpoch});

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
    return out
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  Future<void> putQuickExpense(QuickExpense q) =>
      quickExpenses.put(q.id, q.toMap());

  Future<void> deleteQuickExpense(String id) => quickExpenses.delete(id);
}
