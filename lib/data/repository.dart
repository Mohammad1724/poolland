import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../core/jalali_utils.dart';
import '../core/localization.dart';
import '../core/money.dart';
import '../core/notifications/notify.dart';
import '../core/sms/bank_rules.dart';
import '../core/sms/sms_models.dart';
import '../core/sms/sms_parser.dart';
import '../core/sms/sms_service.dart';
import 'ledger.dart';
import 'models.dart';
import 'store.dart';

/// Core app repository: keeps data in memory, stores it in Hive,
/// and notifies the UI of changes.
class AppRepository extends ChangeNotifier {
  LocalStore? _store;
  bool _ready = false;

  AppRepository({LocalStore? store}) : _store = store {
    if (store != null) {
      _loadFrom(store);
      _ready = true;
    }
  }

  bool get isReady => _ready;
  LocalStore get store => _store!;

  AppSettings settings = const AppSettings();
  List<Customer> customers = [];
  List<Subscription> subscriptions = [];
  List<Txn> transactions = [];
  List<Category> categories = [];
  List<Plan> plans = [];

  // ---- Personal finance ----
  List<Budget> budgets = [];
  List<RecurringRule> recurringRules = [];
  List<QuickExpense> quickExpenses = [];

  /// UI scope filter (null = all).
  TxnScope? scopeFilter = TxnScope.business;

  void setScopeFilter(TxnScope? scope) {
    scopeFilter = scope;
    notifyListeners();
  }

  // ---- Bank SMS ----
  List<ParsedSms> smsSuggestions = [];
  List<SmsHistoryEntry> smsHistory = [];
  List<SmsMessage> smsUnrecognizedMessages = [];
  List<BankRule> smsRules = [];
  bool smsPermissionGranted = false;
  bool smsBusy = false;
  bool smsUnrecognizedBusy = false;
  bool _smsInited = false;

  /// Initialize the repository and open the database.
  Future<void> init() async {
    _store ??= await LocalStore.open();
    _loadFrom(_store!);
    _ready = true;
    notifyListeners();
  }

  T _readBox<T>(String box, T Function() read) {
    try {
      return read();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(
        StateError('Reading Hive box "$box" failed: $error'),
        stackTrace,
      );
    }
  }

  void _loadFrom(LocalStore s) {
    settings = _readBox('meta/settings', s.loadSettings);
    customers = _readBox(
      'customers',
      () => s.loadCustomers()..sort((a, b) => a.name.compareTo(b.name)),
    );
    subscriptions = _readBox(
      'subscriptions',
      () => s.loadSubscriptions()
        ..sort((a, b) => a.endDate.compareTo(b.endDate)),
    );
    transactions = _readBox(
      'transactions',
      () => s.loadTxns()..sort((a, b) => b.date.compareTo(a.date)),
    );
    categories = _readBox('categories', s.loadCategories);
    plans = _readBox('plans', s.loadPlans);
    smsRules = _readBox('sms_rules', s.loadSmsRules);
    smsHistory = _readBox('sms_state_v2', s.loadSmsHistory);
    budgets = _readBox('budgets', s.loadBudgets);
    recurringRules = _readBox('recurring', s.loadRecurring);
    quickExpenses = _readBox('quick_expenses', s.loadQuickExpenses);
    _syncGlobals();
  }

  void _syncGlobals() => Money.sync(settings);

  Future<void> reload() async {
    if (_store == null) return;
    _loadFrom(_store!);
    notifyListeners();
  }

  // ---------------- Quick accessors ----------------
  List<Customer> get activeCustomers =>
      customers.where((c) => !c.archived).toList();

  List<Plan> get activePlans => plans.where((p) => !p.archived).toList();

  Customer? customerById(String? id) {
    if (id == null) return null;
    for (final c in customers) {
      if (c.id == id) return c;
    }
    return null;
  }

  String customerName(String? id) => customerById(id)?.name ?? 'No customer'.tr;

  Subscription? subscriptionById(String? id) {
    if (id == null) return null;
    for (final s in subscriptions) {
      if (s.id == id) return s;
    }
    return null;
  }

  Plan? planById(String? id) {
    if (id == null) return null;
    for (final p in plans) {
      if (p.id == id) return p;
    }
    return null;
  }

  Category? categoryById(String? id) {
    if (id == null) return null;
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  String categoryName(String? id) =>
      categoryById(id)?.name.tr ?? 'Uncategorized'.tr;

  List<Category> categoriesOf(TxnKind kind, {TxnScope? scope}) => categories
      .where((c) => c.kind == kind && c.scope == (scope ?? TxnScope.business))
      .toList();

  List<Subscription> subsOfCustomer(String customerId) =>
      subscriptions.where((s) => s.customerId == customerId).toList()
        ..sort((a, b) => b.endDate.compareTo(a.endDate));

  List<Txn> txnsOfCustomer(String customerId) =>
      Ledger.forCustomer(businessTxns, customerId);

  double balanceOf(Customer c) => Ledger.customerBalance(c, businessTxns);

  Balances get totals => Ledger.totals(customers, businessTxns);

  /// Transactions in a given scope (all scopes when null).
  List<Txn> scopeTxns(TxnScope? scope) => scope == null
      ? transactions
      : transactions.where((t) => t.scope == scope).toList();

  /// Business transactions — everything except personal transactions.
  /// All business calculations use this list so personal expenses
  /// do not distort VPN business profit.
  List<Txn> get businessTxns =>
      transactions.where((t) => t.scope != TxnScope.personal).toList();

  Summary summary({DateTime? from, DateTime? to, TxnScope? scope}) =>
      Ledger.summarize(scopeTxns(scope), from: from, to: to, scope: scope);

  List<MonthPoint> series({int months = 6, TxnScope? scope}) =>
      Ledger.monthlySeries(scopeTxns(scope), months: months, scope: scope);

  List<Subscription> get alerts =>
      Ledger.alerts(subscriptions, reminderDays: settings.reminderDays);

  int get activeSubsCount => Ledger.activeCount(subscriptions);

  Map<String, double> balancesMap() =>
      Ledger.balancesByCustomer(customers, businessTxns);

  /// Cash/bank balance = opening balance + net business cash flow.
  double get cashBalance =>
      settings.openingCash + Ledger.summarize(businessTxns).netCash;

  /// Sorted list of debtors (contacts who owe us).
  List<MapEntry<Customer, double>> debtorsList() {
    final map = balancesMap();
    final list =
        activeCustomers
            .map((c) => MapEntry(c, map[c.id] ?? 0))
            .where((e) => e.value > 0.5)
            .toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    return list;
  }

  /// Sorted list of creditors (contacts we owe).
  List<MapEntry<Customer, double>> creditorsList() {
    final map = balancesMap();
    return activeCustomers
        .map((e) => MapEntry(e, map[e.id] ?? 0))
        .where((e) => e.value < -0.5)
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));
  }

  // ---------------- Customers ----------------
  Future<Customer> addCustomer({
    required String name,
    String phone = '',
    String telegram = '',
    String note = '',
    double openingBalance = 0,
    List<String> bankIdentifiers = const [],
  }) async {
    final c = Customer(
      id: LocalStore.newId(),
      name: name.trim(),
      phone: phone.trim(),
      telegram: telegram.trim(),
      note: note.trim(),
      openingBalance: openingBalance,
      createdAt: DateTime.now(),
      bankIdentifiers: bankIdentifiers,
    );
    await store.putCustomer(c);
    customers = [...customers, c]..sort((a, b) => a.name.compareTo(b.name));
    notifyListeners();
    return c;
  }

  Future<void> updateCustomer(Customer c) async {
    await store.putCustomer(c);
    await reload();
  }

  /// Delete a customer; [withData] also deletes their transactions and subscriptions.
  Future<void> deleteCustomer(String id, {bool withData = true}) async {
    final subscriptionIds = subscriptions
        .where((s) => s.customerId == id)
        .map((s) => s.id)
        .toSet();
    for (final t in transactions.where(
      (t) =>
          t.customerId == id ||
          (withData && subscriptionIds.contains(t.subscriptionId)),
    )) {
      if (withData) {
        await store.deleteTxn(t.id);
      } else {
        await store.putTxn(
          t.copyWith(
            clearCustomer: t.customerId == id,
            clearSubscription: subscriptionIds.contains(t.subscriptionId),
          ),
        );
      }
    }
    for (final subscriptionId in subscriptionIds) {
      await store.deleteSubscription(subscriptionId);
    }
    await store.deleteCustomer(id);
    await reload();
  }

  // ---------------- Subscriptions ----------------
  Future<Subscription> saveSubscription(Subscription s) async {
    await store.putSubscription(s);
    await reload();
    return s;
  }

  Future<void> deleteSubscription(String id) async {
    for (final txn in transactions.where((t) => t.subscriptionId == id)) {
      await store.putTxn(txn.copyWith(clearSubscription: true));
    }
    await store.deleteSubscription(id);
    await reload();
  }

  /// Record a subscription sale, including income and any immediate payment.
  Future<Subscription> sellSubscription({
    required Customer customer,
    Plan? plan,
    required String title,
    required double price,
    required String currencyCode,
    required DateTime start,
    required DateTime end,
    double received = 0,
    String? receiveCurrency,
    bool autoRenew = false,
    String note = '',
    String? categoryId,
    int deviceCount = 1,
  }) async {
    final saleCategoryId = (categoryId == null || categoryId.isEmpty)
        ? defaultIncomeCategoryId
        : categoryId;
    final s = Subscription(
      id: LocalStore.newId(),
      customerId: customer.id,
      planId: plan?.id,
      planName: title,
      startDate: J.dateOnly(start),
      endDate: J.dateOnly(end),
      amount: price,
      currency: currencyCode,
      deviceCount: deviceCount,
      note: note,
      autoRenew: autoRenew,
      createdAt: DateTime.now(),
    );
    await store.putSubscription(s);

    if (price > 0) {
      await store.putTxn(
        Txn(
          id: LocalStore.newId(),
          kind: TxnKind.income,
          amount: price,
          currency: currencyCode,
          rateToBase: settings.currency(currencyCode).rateToBase,
          date: J.dateOnly(start),
          categoryId: saleCategoryId,
          customerId: customer.id,
          subscriptionId: s.id,
          credit: true, // The full amount is charged to the customer’s balance.
          note: note.isEmpty ? 'Sale: $title' : note,
          createdAt: DateTime.now(),
        ),
      );
    }

    final cur = receiveCurrency ?? currencyCode;
    if (received > 0) {
      await store.putTxn(
        Txn(
          id: LocalStore.newId(),
          kind: TxnKind.receive,
          amount: received,
          currency: cur,
          rateToBase: settings.currency(cur).rateToBase,
          date: J.dateOnly(start),
          categoryId: saleCategoryId,
          customerId: customer.id,
          subscriptionId: s.id,
          note: 'Payment for $title',
          createdAt: DateTime.now(),
        ),
      );
    }

    await reload();
    return s;
  }

  /// Renew a subscription, starting the new one the day after the previous end date.
  Future<Subscription> renewSubscription(
    Subscription old, {
    int? months,
    double? price,
    double? received,
    String? currencyCode,
    DateTime? start,
    String? categoryId,
  }) async {
    final customer = customerById(old.customerId);
    if (customer == null) throw StateError('Customer not found');
    final plan = planById(old.planId);
    final startDate = start ?? J.addDays(old.endDate, 1);
    final end = plan != null
        ? plan.endFrom(startDate)
        : J.addDays(J.addMonths(startDate, months ?? 1), -1);
    return sellSubscription(
      customer: customer,
      plan: plan,
      title: old.planName,
      price: price ?? old.amount,
      currencyCode: currencyCode ?? old.currency,
      start: startDate,
      end: end,
      received: received ?? 0,
      receiveCurrency: currencyCode ?? old.currency,
      autoRenew: old.autoRenew,
      note: 'Renewal: ${old.planName}',
      categoryId: categoryId,
      deviceCount: old.deviceCount,
    );
  }

  String? get defaultIncomeCategoryId => defaultCategoryId(TxnKind.income);

  String? get defaultExpenseCategoryId => defaultCategoryId(TxnKind.expense);

  /// First suitable category for a transaction type and scope.
  String? defaultCategoryId(
    TxnKind kind, {
    TxnScope scope = TxnScope.business,
  }) {
    final list = categoriesOf(kind, scope: scope);
    if (list.isEmpty) return null;
    if (kind == TxnKind.income) {
      for (final c in list) {
        if (c.name.toLowerCase().contains('subscription')) return c.id;
      }
    }
    return list.first.id;
  }

  // ---------------- Transactions ----------------
  Txn buildTxn({
    required TxnKind kind,
    required double amount,
    required String currency,
    TxnScope scope = TxnScope.business,
    required DateTime date,
    String? categoryId,
    String? customerId,
    String? subscriptionId,
    bool credit = false,
    String note = '',
  }) => Txn(
    id: LocalStore.newId(),
    kind: kind,
    amount: amount,
    currency: currency,
    rateToBase: settings.currency(currency).rateToBase,
    date: date,
    categoryId: categoryId,
    customerId: customerId,
    subscriptionId: subscriptionId,
    credit: credit,
    note: note,
    scope: scope,
    createdAt: DateTime.now(),
  );

  Future<Txn> addTxn(Txn t) async {
    await store.putTxn(t);
    transactions = [...transactions, t]
      ..sort((a, b) => b.date.compareTo(a.date));
    notifyListeners();
    return t;
  }

  Future<void> updateTxn(Txn t) async {
    await store.putTxn(t);
    await reload();
  }

  Future<void> deleteTxn(String id) async {
    await store.deleteTxn(id);
    await reload();
  }

  // ================= Personal finance =================

  /// Current Jalali month range (for budgets and monthly charts).
  static DateTimeRangeOfMonth monthOf(DateTime d) {
    final j = J.of(d);
    final start = J.toDate(j.year, j.month, 1);
    final end = J.endOfDay(J.addDays(J.addMonths(start, 1), -1));
    return DateTimeRangeOfMonth(
      start: start,
      end: end,
      year: j.year,
      month: j.month,
    );
  }

  /// Usage for all budgets in the current month.
  List<BudgetUsage> budgetUsages({DateTime? now}) {
    final range = monthOf(now ?? DateTime.now());
    return budgets.map((b) {
      final cat = categories.where((c) => c.id == b.categoryId).firstOrNull;
      return BudgetUsage(
        budget: b,
        categoryName: cat?.name ?? 'Deleted category',
        spent: Ledger.spentIn(
          transactions,
          b.categoryId,
          from: range.start,
          to: range.end,
        ),
      );
    }).toList()..sort((a, b) => b.ratio.compareTo(a.ratio));
  }

  Future<void> addBudget(Budget b) async {
    budgets = [...budgets, b];
    await store.putBudget(b);
    notifyListeners();
  }

  Future<void> updateBudget(Budget b) async {
    budgets = budgets.map((e) => e.id == b.id ? b : e).toList();
    await store.putBudget(b);
    notifyListeners();
  }

  Future<void> deleteBudget(String id) async {
    budgets = budgets.where((e) => e.id != id).toList();
    await store.deleteBudget(id);
    notifyListeners();
  }

  Future<void> addRecurring(RecurringRule r) async {
    recurringRules = [...recurringRules, r];
    await store.putRecurring(r);
    notifyListeners();
  }

  Future<void> updateRecurring(RecurringRule r) async {
    recurringRules = recurringRules.map((e) => e.id == r.id ? r : e).toList();
    await store.putRecurring(r);
    notifyListeners();
  }

  Future<void> deleteRecurring(String id) async {
    recurringRules = recurringRules.where((e) => e.id != id).toList();
    await store.deleteRecurring(id);
    notifyListeners();
  }

  /// Automatically post recurring transactions that are due.
  /// Returns the number of transactions created.
  Future<int> postDueRecurring({DateTime? now}) async {
    final today = now ?? DateTime.now();
    var created = 0;
    for (final r in List<RecurringRule>.from(recurringRules)) {
      final dues = r.pendingDues(today);
      if (dues.isEmpty) continue;
      for (final d in dues) {
        // Deterministic occurrence IDs make posting idempotent if the app closes
        // after writing a transaction but before advancing lastPosted.
        final occurrenceId = 'rec:${r.id}:${d.millisecondsSinceEpoch}';
        if (store.transactions.containsKey(occurrenceId)) continue;
        await store.putTxn(
          Txn(
            id: occurrenceId,
            kind: r.kind,
            amount: r.amount,
            currency: r.currency,
            rateToBase: settings.currency(r.currency).rateToBase,
            date: d,
            categoryId: r.categoryId,
            customerId: r.customerId,
            note: r.note.isEmpty ? r.title : r.note,
            scope: r.scope,
            createdAt: DateTime.now(),
          ),
        );
        created++;
      }
      final updated = r.copyWith(lastPosted: dues.last);
      await store.putRecurring(updated);
      recurringRules = recurringRules
          .map((e) => e.id == updated.id ? updated : e)
          .toList();
    }
    if (created > 0) {
      transactions = store.loadTxns()..sort((a, b) => b.date.compareTo(a.date));
      notifyListeners();
    }
    return created;
  }

  /// Record a quick expense or income from a dashboard button.
  Future<Txn> addQuickExpense(
    QuickExpense q, {
    double? amount,
    DateTime? date,
  }) {
    return addTxn(
      Txn(
        id: LocalStore.newId(),
        kind: q.kind,
        amount: amount ?? q.amount,
        currency: 'IRT',
        rateToBase: settings.currency('IRT').rateToBase,
        date: date ?? DateTime.now(),
        categoryId: q.categoryId,
        note: q.label,
        scope: q.scope,
        createdAt: DateTime.now(),
      ),
    );
  }

  Future<void> addQuickButton(QuickExpense q) async {
    quickExpenses = [...quickExpenses, q]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    await store.putQuickExpense(q);
    notifyListeners();
  }

  Future<void> updateQuickButton(QuickExpense q) async {
    quickExpenses = (quickExpenses.map((e) => e.id == q.id ? q : e).toList())
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    await store.putQuickExpense(q);
    notifyListeners();
  }

  Future<void> deleteQuickButton(String id) async {
    quickExpenses = quickExpenses.where((e) => e.id != id).toList();
    await store.deleteQuickExpense(id);
    notifyListeners();
  }

  /// Quickly record a receipt from or payment to a customer.
  Future<void> addPayment({
    required Customer customer,
    required double amount,
    required String currencyCode,
    required DateTime date,
    bool isReceive = true,
    String note = '',
  }) => addTxn(
    Txn(
      id: LocalStore.newId(),
      kind: isReceive
          ? TxnKind.receive
          : (balanceOf(customer) < -0.5
                ? TxnKind.payablePayment
                : TxnKind.refund),
      amount: amount,
      currency: currencyCode,
      rateToBase: settings.currency(currencyCode).rateToBase,
      date: date,
      categoryId: isReceive ? defaultIncomeCategoryId : null,
      customerId: customer.id,
      note: note.isEmpty
          ? (isReceive
                ? 'Payment received'
                : (balanceOf(customer) < -0.5
                      ? 'Payable settlement'
                      : 'Refund to customer'))
          : note,
      createdAt: DateTime.now(),
    ),
  );

  // ---------------- Categories ----------------
  Future<void> addCategory(
    String name,
    TxnKind kind, {
    TxnScope scope = TxnScope.business,
  }) async {
    final list = categoriesOf(kind, scope: scope);
    await store.putCategory(
      Category(
        id: LocalStore.newId(),
        name: name.trim(),
        kind: kind,
        sortOrder: list.isEmpty ? 0 : list.last.sortOrder + 1,
        scope: scope,
      ),
    );
    await reload();
  }

  Future<void> renameCategory(Category c, String newName) async {
    await store.putCategory(
      Category(
        id: c.id,
        name: newName.trim(),
        kind: c.kind,
        sortOrder: c.sortOrder,
        scope: c.scope,
      ),
    );
    await reload();
  }

  Future<void> deleteCategory(String id) async {
    for (final t in transactions.where((t) => t.categoryId == id).toList()) {
      await store.putTxn(t.copyWith(clearCategory: true));
    }
    await store.deleteCategory(id);
    await reload();
  }

  // ---------------- Plans ----------------
  Future<Plan> addPlan(Plan p) async {
    final created = Plan(
      id: LocalStore.newId(),
      name: p.name,
      price: p.price,
      currency: p.currency,
      durationValue: p.durationValue,
      durationUnit: p.durationUnit,
      note: p.note,
    );
    await store.putPlan(created);
    await reload();
    return created;
  }

  Future<void> updatePlan(Plan p) async {
    await store.putPlan(p);
    await reload();
  }

  Future<void> deletePlan(String id) async {
    final plan = planById(id);
    final isInUse = subscriptions.any((s) => s.planId == id);
    if (plan != null && isInUse) {
      // Keep the plan available to existing subscriptions (renewal pricing and
      // duration still depend on it), while hiding it from new sales.
      await store.putPlan(plan.copyWith(archived: true));
    } else {
      await store.deletePlan(id);
    }
    await reload();
  }

  // ---------------- Settings ----------------
  Future<void> updateSettings(AppSettings s) async {
    final reminderChanged =
        s.dailyReminder != settings.dailyReminder ||
        s.reminderHour != settings.reminderHour ||
        s.reminderMinute != settings.reminderMinute;
    final wasEnabled = settings.dailyReminder;
    settings = s;
    _syncGlobals();
    await store.saveSettings(s);
    notifyListeners();
    if (!reminderChanged) return;
    if (s.dailyReminder) {
      await scheduleDailyReminder();
    } else if (wasEnabled) {
      await cancelDailyReminder();
    }
  }

  /// Schedule the daily reminder only when the user has enabled it.
  /// When the reminder is off, avoid initializing the notification plugin so
  /// app startup stays lightweight and dependency-free.
  Future<void> scheduleDailyReminder() async {
    if (!reminder.supported || !settings.dailyReminder) return;
    try {
      await reminder.scheduleDaily(
        hour: settings.reminderHour,
        minute: settings.reminderMinute,
      );
    } catch (_) {
      // The app must keep working if notifications are unavailable.
    }
  }

  /// Cancel the scheduled reminder.
  Future<void> cancelDailyReminder() async {
    if (!reminder.supported) return;
    try {
      await reminder.cancelDaily();
    } catch (_) {
      // Ignore possible plugin errors.
    }
  }

  /// Visible transactions after applying the scope filter.
  List<Txn> get visibleTxns => scopeFilter == null
      ? transactions
      : transactions.where((t) => t.scope == scopeFilter).toList();

  Future<void> upsertCurrency(CurrencyDef def) async {
    final list = [...settings.currencies];
    final i = list.indexWhere((c) => c.code == def.code);
    if (i >= 0) {
      list[i] = def;
    } else {
      list.add(def);
    }
    await updateSettings(settings.copyWith(currencies: list));
  }

  Future<void> removeCurrency(String code) async {
    if (code == settings.baseCurrency) return;
    final list = settings.currencies.where((c) => c.code != code).toList();
    await updateSettings(settings.copyWith(currencies: list));
  }

  // ---------------- Bank SMS ----------------
  /// Whether SMS is supported on this device (Android only).
  bool get smsSupported => SmsService.isSupported;

  /// Number of suggestions awaiting approval.
  int get smsPendingCount => smsSuggestions.length;

  /// Built-in rules are enabled unless explicitly disabled in settings.
  bool isSmsRuleEnabled(String ruleId) =>
      !settings.disabledSmsRuleIds.contains(ruleId);

  /// Persist a per-rule switch and immediately apply it to the review queue.
  Future<void> setSmsRuleEnabled(String ruleId, bool enabled) async {
    final disabledRuleIds = settings.disabledSmsRuleIds.toSet();
    final wasEnabled = !disabledRuleIds.contains(ruleId);
    if (wasEnabled == enabled) return;

    if (enabled) {
      disabledRuleIds.remove(ruleId);
    } else {
      disabledRuleIds.add(ruleId);
    }
    final sortedIds = disabledRuleIds.toList()..sort();
    await updateSettings(
      settings.copyWith(disabledSmsRuleIds: sortedIds),
    );
    _refreshPendingSms();

    // Enabling a rule may make messages already in the inbox eligible for
    // manual review. It still never records a transaction automatically.
    if (enabled && smsPermissionGranted) {
      try {
        await syncSms(force: true);
      } catch (_) {
        // The setting is saved; the user can retry from the SMS review page.
      }
    }
  }

  void _refreshPendingSms() {
    final disabledRuleIds = settings.disabledSmsRuleIds.toSet();
    final refreshed = smsSuggestions
        .map(
          (sms) => SmsParser.parse(
            sms.message,
            extraRules: smsRules,
            disabledRuleIds: disabledRuleIds,
          ),
        )
        .where((sms) => sms.isTransaction)
        .toList()
      ..sort((a, b) => b.message.date.compareTo(a.message.date));
    smsSuggestions = refreshed;
    smsUnrecognizedMessages = [];
    notifyListeners();
  }

  /// Initialize listening for new SMS messages.
  void initSms() {
    if (_smsInited || !SmsService.isSupported) return;
    _smsInited = true;
    SmsService.init();
    SmsService.onSmsReceived = _onIncomingSms;
  }

  void _onIncomingSms(SmsMessage msg) {
    final parsed = SmsParser.parse(
      msg,
      extraRules: smsRules,
      disabledRuleIds: settings.disabledSmsRuleIds.toSet(),
    );
    if (!parsed.isTransaction) return;
    final state = store.loadSmsState();
    if (state.containsKey(parsed.key)) return;

    smsSuggestions = [
      parsed,
      ...smsSuggestions.where((e) => e.key != parsed.key),
    ]..sort((a, b) => b.message.date.compareTo(a.message.date));
    notifyListeners();
  }

  Future<bool> refreshSmsPermission() async {
    smsPermissionGranted = await SmsService.hasPermission();
    notifyListeners();
    return smsPermissionGranted;
  }

  Future<bool> requestSmsPermission() async {
    final ok = await SmsService.requestPermission();
    smsPermissionGranted = ok;
    if (ok) {
      await updateSettings(settings.copyWith(smsEnabled: true));
      unawaited(syncSms());
    }
    notifyListeners();
    return ok;
  }

  /// Read SMS messages and build the suggestion list.
  /// Returns the number of new suggestions.
  Future<int> syncSms({bool force = false}) async {
    if (!isReady || !SmsService.isSupported) return 0;
    if (smsBusy && !force) return 0;
    smsBusy = true;
    notifyListeners();
    try {
      final days = settings.smsSyncDays < 1 ? 1 : settings.smsSyncDays;
      final since = DateTime.now().subtract(Duration(days: days));
      final messages = await SmsService.readInbox(since: since);
      final state = store.loadSmsState();

      final disabledRuleIds = settings.disabledSmsRuleIds.toSet();
      final current = smsSuggestions
          .map(
            (sms) => SmsParser.parse(
              sms.message,
              extraRules: smsRules,
              disabledRuleIds: disabledRuleIds,
            ),
          )
          .where((sms) => sms.isTransaction && !state.containsKey(sms.key))
          .toList();

      final pending = <ParsedSms>[];
      for (final m in messages) {
        if (state.containsKey(m.key)) continue;
        final parsed = SmsParser.parse(
          m,
          extraRules: smsRules,
          disabledRuleIds: disabledRuleIds,
        );
        if (parsed.isTransaction) {
          pending.add(parsed);
        } else {
          // Unmatched messages are discarded by policy. Do not create review
          // cache entries for them; they may be rechecked later but never enter
          // the approval queue without a rule match.
        }
      }

      final known = current.map((e) => e.key).toSet();
      final merged = <ParsedSms>[
        ...current,
        ...pending.where((p) => !known.contains(p.key)),
      ]..sort((a, b) => b.message.date.compareTo(a.message.date));
      smsSuggestions = merged;

      await updateSettings(
        settings.copyWith(smsLastSyncAt: DateTime.now().millisecondsSinceEpoch),
      );
      notifyListeners();
      return pending.length;
    } finally {
      smsBusy = false;
      notifyListeners();
    }
  }

  /// Find transaction-like messages that do not match any active rule.
  /// These remain out of the review queue until the user explicitly creates a
  /// rule for their sender or a phrase in the body.
  Future<int> scanUnrecognizedSms({bool force = false}) async {
    if (!isReady || !SmsService.isSupported || !smsPermissionGranted) return 0;
    if (smsUnrecognizedBusy && !force) return 0;

    smsUnrecognizedBusy = true;
    notifyListeners();
    try {
      final days = settings.smsSyncDays < 1 ? 1 : settings.smsSyncDays;
      final since = DateTime.now().subtract(Duration(days: days));
      final messages = await SmsService.readInbox(since: since);
      final state = store.loadSmsState();
      final disabledRuleIds = settings.disabledSmsRuleIds.toSet();
      final candidates = <String, SmsMessage>{};

      for (final message in messages) {
        if (state.containsKey(message.key)) continue;
        final body = SmsParser.normalize(message.body);
        if (SmsParser.isIgnored(body)) continue;

        final parsed = SmsParser.parse(
          message,
          extraRules: smsRules,
          disabledRuleIds: disabledRuleIds,
        );
        if (!parsed.isPotentialUnrecognizedTransaction) continue;

        // Do not advertise a known-but-disabled bank as an unknown sender.
        final disabledMatch = SmsParser.findRule(
          SmsParser.normalize(message.address).toUpperCase(),
          body,
          smsRules,
        );
        if (disabledMatch != null &&
            disabledRuleIds.contains(disabledMatch.id)) {
          continue;
        }
        candidates[message.key] = message;
      }

      smsUnrecognizedMessages = candidates.values.toList()
        ..sort((a, b) => b.date.compareTo(a.date));
      return smsUnrecognizedMessages.length;
    } finally {
      smsUnrecognizedBusy = false;
      notifyListeners();
    }
  }

  /// Match an SMS to a customer using their bank identifiers.
  Customer? matchCustomerForSms(ParsedSms sms) {
    for (final c in activeCustomers) {
      if (c.bankIdentifiers.isEmpty) continue;
      if (SmsParser.matchesIdentifiers(sms, c.bankIdentifiers)) return c;
    }
    return null;
  }

  /// Approve an SMS as a transaction in the selected personal/business scope.
  Future<Txn?> approveSms(
    ParsedSms sms, {
    Customer? customer,
    TxnKind? kind,
    String? categoryId,
    double? amount,
    required TxnScope scope,
  }) async {
    if (!sms.isTransaction) return null;

    final cust = scope == TxnScope.business
        ? (customer ?? matchCustomerForSms(sms))
        : null;
    final suggestedKind = sms.direction == SmsDirection.deposit
        ? (scope == TxnScope.business &&
                  cust != null &&
                  balanceOf(cust) > 0.5
              ? TxnKind.receive
              : TxnKind.income)
        : TxnKind.expense;
    var k = kind ?? suggestedKind;
    if (scope == TxnScope.personal &&
        k != TxnKind.income &&
        k != TxnKind.expense) {
      k = suggestedKind;
    }

    final categoryKind = switch (k) {
      TxnKind.expense => TxnKind.expense,
      TxnKind.income || TxnKind.receive => TxnKind.income,
      _ => null,
    };
    var cat = categoryId;
    if (categoryKind != null) {
      final categoriesForScope = categoriesOf(categoryKind, scope: scope);
      if (cat == null || !categoriesForScope.any((c) => c.id == cat)) {
        cat = defaultCategoryId(categoryKind, scope: scope);
      }
    }

    final cur = sms.currency;
    final txn = Txn(
      id: LocalStore.newId(),
      kind: k,
      amount: amount ?? sms.amount,
      currency: cur,
      rateToBase: settings.currency(cur).rateToBase,
      date: sms.message.date,
      categoryId: categoryKind == null ? null : cat,
      customerId: cust?.id,
      credit: false,
      scope: scope,
      note: _smsNote(sms),
      createdAt: DateTime.now(),
    );
    await store.putTxn(txn);
    await store.setSmsState(
      sms.key,
      SmsHistoryEntry.approvedStatus,
      history: _smsHistoryEntry(
        sms,
        SmsHistoryEntry.approvedStatus,
        transactionId: txn.id,
      ),
    );
    smsSuggestions = smsSuggestions.where((e) => e.key != sms.key).toList();
    await reload();
    return txn;
  }

  /// Reject a suggestion (it will no longer be displayed).
  Future<void> rejectSms(ParsedSms sms) async {
    await store.setSmsState(
      sms.key,
      SmsHistoryEntry.rejectedStatus,
      history: _smsHistoryEntry(sms, SmsHistoryEntry.rejectedStatus),
    );
    smsSuggestions = smsSuggestions.where((e) => e.key != sms.key).toList();
    smsHistory = store.loadSmsHistory();
    notifyListeners();
  }

  /// Reject all suggestions.
  Future<void> rejectAllSms() async {
    for (final sms in smsSuggestions) {
      await store.setSmsState(
        sms.key,
        SmsHistoryEntry.rejectedStatus,
        history: _smsHistoryEntry(sms, SmsHistoryEntry.rejectedStatus),
      );
    }
    smsSuggestions = [];
    smsHistory = store.loadSmsHistory();
    notifyListeners();
  }

  SmsHistoryEntry _smsHistoryEntry(
    ParsedSms sms,
    String status, {
    String? transactionId,
  }) => SmsHistoryEntry(
    key: sms.key,
    message: sms.message,
    status: status,
    bankName: sms.bankName,
    amount: sms.amount,
    currency: sms.currency,
    direction: sms.direction,
    reviewedAt: DateTime.now(),
    transactionId: transactionId,
  );

  /// Clear review history so all messages are scanned again.
  Future<void> resetSmsState() async {
    await store.clearSmsState();
    smsSuggestions = [];
    smsHistory = [];
    smsUnrecognizedMessages = [];
    notifyListeners();
  }

  Future<void> addSmsRule(BankRule rule) async {
    await store.putSmsRule(rule);
    await reload();
    _refreshPendingSms();
    if (smsPermissionGranted) {
      try {
        await syncSms(force: true);
      } catch (_) {
        // Keep the new rule even if inbox scanning is temporarily unavailable.
      }
    }
  }

  Future<void> deleteSmsRule(String id) async {
    await store.deleteSmsRule(id);
    final disabledRuleIds = settings.disabledSmsRuleIds
        .where((ruleId) => ruleId != id)
        .toList();
    if (disabledRuleIds.length != settings.disabledSmsRuleIds.length) {
      await updateSettings(
        settings.copyWith(disabledSmsRuleIds: disabledRuleIds),
      );
    }
    await reload();
    _refreshPendingSms();
  }

  static String _smsNote(ParsedSms sms) {
    final parts = <String>[];
    if (sms.bankName != null && sms.bankName!.isNotEmpty) {
      parts.add(sms.bankName!);
    }
    if (sms.cardMask != null && sms.cardMask!.isNotEmpty) {
      parts.add('Card ${sms.cardMask}');
    }
    if (sms.reference != null && sms.reference!.isNotEmpty) {
      parts.add('Reference ${sms.reference}');
    }
    if (parts.isEmpty) parts.add('Imported from SMS');
    return parts.join(' · ');
  }

  // ---------------- Backups ----------------
  Map<String, dynamic> exportData() => store.exportAll();

  Future<void> importData(Map<String, dynamic> data) async {
    await store.importAll(data);
    await reload();
  }

  Future<void> wipeAll() async {
    await store.clearAll();
    await reload();
  }

  /// Sample data for quick testing and the GitHub demo.
  Future<void> loadDemoData() async {
    // Preserve user-entered settings (including setupDone and the opening balance)
    // when replacing transactions with sample data.
    final settingsToKeep = settings;
    await store.clearAll();
    await store.saveSettings(settingsToKeep);

    // Synchronize memory with the database: clearAll() deletes data, and
    // default categories and plans are recreated with new IDs.
    // Without this reload, in-memory lists still point to deleted records
    // and can create orphaned transactions.
    await reload();

    final rnd = Random(1405);
    final names = [
      'Alex Morgan',
      'Maya Carter',
      'Daniel Kim',
      'Sara Reed',
      'Ryan Brooks',
      'Nora Taylor',
      'Ethan Clark',
      'Emma Wilson',
    ];

    // If the database has no plans, save the defaults so
    // subscriptions can reference a valid plan and renewals continue to work.
    var planList = plans;
    if (planList.isEmpty) {
      for (final p in LocalStore.defaultPlans()) {
        await store.putPlan(p);
      }
      await reload();
      planList = plans;
    }

    // Keep customers created in this run for later references.
    final createdCustomers = <Customer>[];
    final now = J.today;

    for (var i = 0; i < names.length; i++) {
      final c = Customer(
        id: LocalStore.newId(),
        name: names[i],
        phone: '0912000010$i',
        note: i == 0 ? 'Long-time customer; usually pays with USDT' : '',
        openingBalance: i == 3 ? 250000 : 0,
        createdAt: J.addDays(now, -200),
      );
      await store.putCustomer(c);
      createdCustomers.add(c);

      var start = J.addDays(now, -(30 * 5) + i * 3);
      for (var k = 0; k < 5; k++) {
        final plan = planList[rnd.nextInt(planList.length)];
        final end = plan.endFrom(start);
        final sub = Subscription(
          id: LocalStore.newId(),
          customerId: c.id,
          planId: plan.id,
          planName: plan.name,
          startDate: J.dateOnly(start),
          endDate: J.dateOnly(end),
          amount: plan.price,
          currency: plan.currency,
          deviceCount: 1 + rnd.nextInt(2),
          createdAt: start,
        );
        await store.putSubscription(sub);
        await store.putTxn(
          Txn(
            id: LocalStore.newId(),
            kind: TxnKind.income,
            amount: plan.price,
            currency: plan.currency,
            rateToBase: settings.currency(plan.currency).rateToBase,
            date: J.dateOnly(start),
            categoryId: defaultIncomeCategoryId,
            customerId: c.id,
            subscriptionId: sub.id,
            credit: true,
            note: 'Sale: ${plan.name}',
            createdAt: start,
          ),
        );
        final paid = rnd.nextDouble();
        if (paid < 0.75) {
          final amount = paid < 0.45
              ? plan.price
              : (plan.price / 2).roundToDouble();
          await store.putTxn(
            Txn(
              id: LocalStore.newId(),
              kind: TxnKind.receive,
              amount: amount,
              currency: plan.currency,
              rateToBase: settings.currency(plan.currency).rateToBase,
              date: J.addDays(start, 1 + rnd.nextInt(12)),
              customerId: c.id,
              note: amount == plan.price ? 'Paid in full' : 'Partial payment',
              createdAt: start,
            ),
          );
        }
        start = J.addDays(end, 1);
        if (start.isAfter(now)) break;
      }
    }

    // Fixed monthly expenses.
    const expenses = <String, double>{
      'Server / VPS purchase': 4200000,
      'Domain and SSL': 650000,
      'Control panel and license': 1800000,
      'Advertising and marketing': 900000,
      'Internet and work tools': 400000,
    };
    for (var m = 0; m < 6; m++) {
      for (final e in expenses.entries) {
        final cat = categoriesOf(TxnKind.expense)
            .where((c) => c.name == e.key)
            .toList();
        await store.putTxn(
          Txn(
            id: LocalStore.newId(),
            kind: TxnKind.expense,
            amount: e.value * (0.85 + rnd.nextDouble() * 0.3),
            currency: 'IRT',
            rateToBase: 1,
            date: J.addDays(J.addMonths(now, -m), -rnd.nextInt(20)),
            categoryId: cat.isEmpty ? defaultExpenseCategoryId : cat.first.id,
            note: e.key,
            createdAt: now,
          ),
        );
      }
    }

    // Add a few USDT and USD sales to demonstrate multiple currencies.
    for (final cur in ['USD', 'USDT']) {
      if (settings.currencies.any((c) => c.code == cur) &&
          createdCustomers.isNotEmpty) {
        final c = createdCustomers[rnd.nextInt(createdCustomers.length)];
        await store.putTxn(
          Txn(
            id: LocalStore.newId(),
            kind: TxnKind.income,
            amount: 15,
            currency: cur,
            rateToBase: settings.currency(cur).rateToBase,
            date: J.addDays(now, -rnd.nextInt(40)),
            categoryId: defaultIncomeCategoryId,
            customerId: c.id,
            credit: false,
            note: 'Configuration sale (paid in $cur)',
            createdAt: now,
          ),
        );
      }
    }

    // ---------- Personal finance sample data ----------
    final personalExp = <String, double>{
      'Food and dining': 380000,
      'Transport and fuel': 120000,
      'Utilities (water, electricity, gas)': 450000,
      'Internet and mobile top-up': 200000,
      'Leisure and entertainment': 150000,
      'Personal shopping and clothing': 600000,
    };
    for (final e in personalExp.entries) {
      final cat = categoriesOf(
        TxnKind.expense,
        scope: TxnScope.personal,
      ).where((c) => c.name == e.key).toList();
      final count = 2 + rnd.nextInt(4);
      for (var k = 0; k < count; k++) {
        await store.putTxn(
          Txn(
            id: LocalStore.newId(),
            kind: TxnKind.expense,
            amount: e.value * (0.4 + rnd.nextDouble() * 1.2),
            currency: 'IRT',
            rateToBase: 1,
            date: J.addDays(now, -rnd.nextInt(40)),
            categoryId: cat.isEmpty ? null : cat.first.id,
            note: e.key,
            scope: TxnScope.personal,
            createdAt: now,
          ),
        );
      }
    }

    // Monthly salary (personal income).
    final salaryCat = categoriesOf(
      TxnKind.income,
      scope: TxnScope.personal,
    ).where((c) => c.name == 'Salary').toList();
    for (var m = 0; m < 3; m++) {
      await store.putTxn(
        Txn(
          id: LocalStore.newId(),
          kind: TxnKind.income,
          amount: 25000000,
          currency: 'IRT',
          rateToBase: 1,
          date: J.toDate(
            J.of(J.addMonths(now, -m)).year,
            J.of(J.addMonths(now, -m)).month,
            28,
          ),
          categoryId: salaryCat.isEmpty ? null : salaryCat.first.id,
          note: 'Monthly salary',
          scope: TxnScope.personal,
          createdAt: now,
        ),
      );
    }

    // A sample food budget.
    final foodCat = categoriesOf(
      TxnKind.expense,
      scope: TxnScope.personal,
    ).where((c) => c.name.toLowerCase().contains('food')).toList();
    if (foodCat.isNotEmpty) {
      await store.putBudget(
        Budget(
          id: LocalStore.newId(),
          categoryId: foodCat.first.id,
          limit: 3000000,
        ),
      );
    }

    // A sample recurring rule that started last month.
    final rentCat = categoriesOf(
      TxnKind.expense,
      scope: TxnScope.personal,
    ).where((c) => c.name.toLowerCase().contains('housing')).toList();
    // Set lastPosted to today so loading sample data does not suddenly
    // create several rent transactions (the next one is posted automatically next month).
    await store.putRecurring(
      RecurringRule(
        id: LocalStore.newId(),
        title: 'Home rent',
        amount: 8000000,
        categoryId: rentCat.isEmpty ? null : rentCat.first.id,
        period: RecurringPeriod.monthly,
        dayOfMonth: 5,
        startDate: J.addMonths(now, -1),
        lastPosted: now,
      ),
    );

    await reload();
  }
}

/// A Jalali month range.
class DateTimeRangeOfMonth {
  final DateTime start;
  final DateTime end;
  final int year;
  final int month;

  const DateTimeRangeOfMonth({
    required this.start,
    required this.end,
    required this.year,
    required this.month,
  });
}
