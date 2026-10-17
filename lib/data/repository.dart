import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show ChangeNotifier, VoidCallback;

import '../core/app_lock.dart';
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

  /// Whether the OS currently allows posting notifications. Tracked so the
  /// settings page never claims "notifications on" while Android is silently
  /// dropping them (restored backups used to look enabled without this).
  bool notificationPermissionGranted = true;
  bool smsBusy = false;
  bool smsUnrecognizedBusy = false;
  bool _smsInited = false;

  /// Called when a new bank SMS lands in the review queue while the app is
  /// open, so the shell can point at the queue. The system notification for
  /// the background case is posted natively (see SmsReceiver.kt).
  VoidCallback? onNewSmsSuggestion;

  /// Initialize the repository and open the database.
  Future<void> init() async {
    // The safe Android build ships without the SMS permissions; ask the
    // native side which build this is before anything reads
    // [SmsService.isSupported] (the intro gate, the settings section, and
    // the startup sync all do).
    await SmsService.detectSupport();
    _store ??= await LocalStore.open();
    _loadFrom(_store!);
    _ready = true;
    await syncNativeSmsPrefs();
    await refreshNotificationPermission();
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

  /// Pull-to-refresh: re-read the ledger from disk and re-scan bank SMS,
  /// so a manual pully always shows the freshest data.
  Future<void> refreshAll() async {
    await reload();
    if (smsSupported && settings.smsEnabled) {
      try {
        await syncSms();
      } catch (_) {
        // A failed SMS scan must not break the refresh gesture.
      }
    }
  }

  Future<void> reload() async {
    if (_store == null) return;
    _loadFrom(_store!);
    notifyListeners();
  }

  // ---------------- Quick accessors ----------------

  // Derived-data cache.
  //
  // Pages watch the whole repository and read these getters several times per
  // build, and each aggregation walks the entire ledger. Caching per data
  // version means every aggregation runs once per change instead of once per
  // access; [notifyListeners] bumps the version, and every mutation goes
  // through it, so cached values can never outlive the data they came from.
  int _version = 0;

  @override
  void notifyListeners() {
    _version++;
    super.notifyListeners();
  }

  int _cacheVersion = -1;
  List<Customer>? _activeCustomers;
  List<Txn>? _businessTxns;
  List<Txn>? _visibleTxns;
  Balances? _totals;
  double? _cashBalance;
  int? _activeSubsCount;
  List<Subscription>? _alerts;
  Map<String, double>? _balancesMap;
  List<MapEntry<Customer, double>>? _debtors;
  List<MapEntry<Customer, double>>? _creditors;
  final Map<String, Summary> _summaryCache = {};
  final Map<String, List<MonthPoint>> _seriesCache = {};

  /// Clears every cached aggregate when the data version has moved on.
  void _syncCache() {
    if (_cacheVersion == _version) return;
    _cacheVersion = _version;
    _activeCustomers = null;
    _businessTxns = null;
    _visibleTxns = null;
    _totals = null;
    _cashBalance = null;
    _activeSubsCount = null;
    _alerts = null;
    _balancesMap = null;
    _debtors = null;
    _creditors = null;
    _summaryCache.clear();
    _seriesCache.clear();
  }

  List<Customer> get activeCustomers {
    _syncCache();
    return _activeCustomers ??=
        customers.where((c) => !c.archived).toList();
  }

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

  /// Categories used the most in real transactions, for preset chips:
  /// usage counts beat any hand-picked default because they follow the
  /// actual bookkeeping of this ledger.
  List<Category> topCategories(
    TxnKind categoryKind, {
    TxnScope? scope,
    int limit = 6,
  }) {
    final counts = <String, int>{};
    for (final t in transactions) {
      final id = t.categoryId;
      if (id == null) continue;
      if (scope != null && t.scope != scope) continue;
      final ck = t.kind == TxnKind.income || t.kind == TxnKind.receive
          ? TxnKind.income
          : TxnKind.expense;
      if (ck != categoryKind) continue;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    final pool = categoriesOf(categoryKind, scope: scope);
    pool.sort((a, b) => (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0));
    return pool.take(limit).toList();
  }

  /// Customers with the most transactions: the likely pick whenever a form
  /// or the SMS sheet asks "which contact?".
  List<Customer> topCustomers({int limit = 4}) {
    final counts = <String, int>{};
    for (final t in transactions) {
      final id = t.customerId;
      if (id == null) continue;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    final list = customers.where((c) => (counts[c.id] ?? 0) > 0).toList();
    list.sort((a, b) => (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0));
    return list.take(limit).toList();
  }

  /// Newest distinct entries (same kind+category+contact+note+amount counts
  /// once), for "repeat a recent transaction" chips.
  List<Txn> recentDistinctTxns(int limit) {
    final seen = <String>{};
    final out = <Txn>[];
    for (final t in transactions) {
      final key =
          '${t.kind.name}|${t.scope.name}|${t.categoryId}|${t.customerId}|'
          '${t.note}|${t.amount.round()}';
      if (seen.add(key)) out.add(t);
      if (out.length >= limit) break;
    }
    return out;
  }

  List<Category> categoriesOf(TxnKind kind, {TxnScope? scope}) => categories
      .where((c) => c.kind == kind && c.scope == (scope ?? TxnScope.business))
      .toList();

  List<Subscription> subsOfCustomer(String customerId) =>
      subscriptions.where((s) => s.customerId == customerId).toList()
        ..sort((a, b) => b.endDate.compareTo(a.endDate));

  List<Txn> txnsOfCustomer(String customerId) =>
      Ledger.forCustomer(businessTxns, customerId);

  double balanceOf(Customer c) => Ledger.customerBalance(c, businessTxns);

  Balances get totals {
    _syncCache();
    return _totals ??= Ledger.totals(customers, businessTxns);
  }

  /// Transactions in a given scope (all scopes when null).
  List<Txn> scopeTxns(TxnScope? scope) => scope == null
      ? transactions
      : transactions.where((t) => t.scope == scope).toList();

  /// Business transactions — everything except personal transactions.
  /// All business calculations use this list so personal expenses
  /// do not distort VPN business profit.
  List<Txn> get businessTxns {
    _syncCache();
    return _businessTxns ??=
        transactions.where((t) => t.scope != TxnScope.personal).toList();
  }

  Summary summary({DateTime? from, DateTime? to, TxnScope? scope}) {
    _syncCache();
    final key =
        '${from?.millisecondsSinceEpoch ?? '-'}|'
        '${to?.millisecondsSinceEpoch ?? '-'}|${scope?.name ?? '-'}';
    return _summaryCache.putIfAbsent(
      key,
      () => Ledger.summarize(scopeTxns(scope), from: from, to: to, scope: scope),
    );
  }

  List<MonthPoint> series({int months = 6, TxnScope? scope}) {
    _syncCache();
    final key = '$months|${scope?.name ?? '-'}';
    return _seriesCache.putIfAbsent(
      key,
      () => Ledger.monthlySeries(scopeTxns(scope), months: months, scope: scope),
    );
  }

  List<Subscription> get alerts {
    _syncCache();
    return _alerts ??=
        Ledger.alerts(subscriptions, reminderDays: settings.reminderDays);
  }

  int get activeSubsCount {
    _syncCache();
    return _activeSubsCount ??= Ledger.activeCount(subscriptions);
  }

  Map<String, double> balancesMap() {
    _syncCache();
    return _balancesMap ??=
        Ledger.balancesByCustomer(customers, businessTxns);
  }

  /// Cash/bank balance = opening balance + net business cash flow.
  double get cashBalance {
    _syncCache();
    return _cashBalance ??=
        settings.openingCash + Ledger.summarize(businessTxns).netCash;
  }

  /// Sorted list of debtors (contacts who owe us).
  List<MapEntry<Customer, double>> debtorsList() {
    _syncCache();
    return _debtors ??= () {
      final map = balancesMap();
      return activeCustomers
          .map((c) => MapEntry(c, map[c.id] ?? 0))
          .where((e) => e.value > 0.5)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
    }();
  }

  /// Sorted list of creditors (contacts we owe).
  List<MapEntry<Customer, double>> creditorsList() {
    _syncCache();
    return _creditors ??= () {
      final map = balancesMap();
      return activeCustomers
          .map((e) => MapEntry(e, map[e.id] ?? 0))
          .where((e) => e.value < -0.5)
          .toList()
        ..sort((a, b) => a.value.compareTo(b.value));
    }();
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
          subscriptionIds.contains(t.subscriptionId),
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
          note: 'Payment for {plan}'.trArgs({'plan': title.tr}),
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
      note: 'Renewal: {plan}'.trArgs({'plan': old.planName.tr}),
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

  /// Usage for all enabled budgets in the current month.
  List<BudgetUsage> budgetUsages({DateTime? now}) {
    final range = monthOf(now ?? DateTime.now());
    return budgets
        .where((b) => b.enabled)
        .map((b) {
          final cat = categories.where((c) => c.id == b.categoryId).firstOrNull;
          return BudgetUsage(
            budget: b,
            categoryName: cat?.name ?? 'Deleted category',
            spent: Ledger.spentIn(
              transactions,
              b.categoryId,
              from: range.start,
              to: range.end,
              scope: b.scope,
            ),
          );
        })
        .toList()
      ..sort((a, b) => b.ratio.compareTo(a.ratio));
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
    String? parentId,
  }) async {
    final list = categoriesOf(kind, scope: scope);
    final parent = _validParent(parentId, kind, scope);
    await store.putCategory(
      Category(
        id: LocalStore.newId(),
        name: name.trim(),
        kind: kind,
        sortOrder: list.isEmpty ? 0 : list.last.sortOrder + 1,
        scope: scope,
        parentId: parent?.id,
      ),
    );
    await reload();
  }

  /// A parent must exist, share the child's kind and scope, and be
  /// top-level itself (the nesting is exactly one level deep).
  Category? _validParent(String? parentId, TxnKind kind, TxnScope scope) {
    final parent = categoryById(parentId);
    if (parent == null || parent.parentId != null) return null;
    if (parent.kind != kind || parent.scope != scope) return null;
    return parent;
  }

  /// Moves [id] under [parentId] (or to the top level with null). Keeping
  /// the nesting one level deep: any children of [id] are flattened back
  /// to the top level when it becomes a child itself.
  Future<void> setCategoryParent(
    String id,
    String? parentId,
  ) async {
    final c = categoryById(id);
    if (c == null) return;
    if (parentId == c.parentId) return;
    final parent = _validParent(parentId, c.kind, c.scope);
    if (parent == null && parentId != null) return;
    await store.putCategory(
      Category(
        id: c.id,
        name: c.name,
        kind: c.kind,
        sortOrder: c.sortOrder,
        scope: c.scope,
        parentId: parent?.id,
      ),
    );
    final flattened = <String, String?>{};
    for (final child in categories) {
      if (child.parentId == id) flattened[child.id] = null;
    }
    for (final entry in flattened.entries) {
      final child = categoryById(entry.key)!;
      await store.putCategory(
        Category(
          id: child.id,
          name: child.name,
          kind: child.kind,
          sortOrder: child.sortOrder,
          scope: child.scope,
          parentId: entry.value,
        ),
      );
    }
    await reload();
  }

  /// The picker order for a kind and scope: parents ranked by group usage
  /// (their own transactions plus the transactions of their children),
  /// each child directly under its parent, the rest following creation
  /// order. A frequently used child keeps its parent near the top too.
  List<Category> pickOrderCategories(
    TxnKind kind, {
    TxnScope scope = TxnScope.business,
  }) {
    final all = categoriesOf(kind, scope: scope);
    final counts = <String, int>{};
    for (final t in transactions) {
      final id = t.categoryId;
      if (id == null || t.scope != scope) continue;
      final ck = t.kind == TxnKind.income || t.kind == TxnKind.receive
          ? TxnKind.income
          : TxnKind.expense;
      if (ck != kind) continue;
      counts[id] = (counts[id] ?? 0) + 1;
    }
    final byId = {for (final c in all) c.id: c};
    final childrenOf = <String, List<Category>>{};
    final tops = <Category>[];
    for (final c in all) {
      final parent = c.parentId == null ? null : byId[c.parentId];
      if (parent == null) {
        tops.add(c);
      } else {
        (childrenOf[parent.id] ??= []).add(c);
      }
    }
    int weight(Category c) =>
        (counts[c.id] ?? 0) +
        (childrenOf[c.id] ?? const <Category>[])
            .fold<int>(0, (s, k) => s + (counts[k.id] ?? 0));
    for (final kids in childrenOf.values) {
      kids.sort((a, b) {
        final d = (counts[b.id] ?? 0).compareTo(counts[a.id] ?? 0);
        return d != 0 ? d : a.sortOrder.compareTo(b.sortOrder);
      });
    }
    tops.sort((a, b) {
      final d = weight(b).compareTo(weight(a));
      return d != 0 ? d : a.sortOrder.compareTo(b.sortOrder);
    });
    final out = <Category>[];
    for (final p in tops) {
      out.add(p);
      out.addAll(childrenOf[p.id] ?? const <Category>[]);
    }
    return out;
  }

  Future<void> renameCategory(Category c, String newName) async {
    await store.putCategory(
      Category(
        id: c.id,
        name: newName.trim(),
        kind: c.kind,
        sortOrder: c.sortOrder,
        scope: c.scope,
        parentId: c.parentId,
      ),
    );
    await reload();
  }

  Future<void> deleteCategory(String id) async {
    for (final t in transactions.where((t) => t.categoryId == id).toList()) {
      await store.putTxn(t.copyWith(clearCategory: true));
    }
    // Orphan any children: they keep their data and move to the top level
    // instead of keeping a dangling parent reference.
    for (final child in categories.where((c) => c.parentId == id).toList()) {
      await store.putCategory(
        Category(
          id: child.id,
          name: child.name,
          kind: child.kind,
          sortOrder: child.sortOrder,
          scope: child.scope,
        ),
      );
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
        s.reminderMinute != settings.reminderMinute ||
        s.notificationSoundUri != settings.notificationSoundUri ||
        // The reminder text is baked into the scheduled notification, so a
        // language switch must reschedule it in the new language.
        s.languageCode != settings.languageCode;
    final wasEnabled = settings.dailyReminder;
    settings = s;
    _syncGlobals();
    await store.saveSettings(s);
    notifyListeners();
    // The native receiver mirrors language, rules, and the notification flag.
    await syncNativeSmsPrefs();
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
        // Baked into the scheduled notification: translate with the saved
        // settings language explicitly — the global language code only
        // catches up when MaterialApp rebuilds, which can be later.
        title: AppLocalization.text(
          'Expense reminder',
          languageCode: settings.languageCode,
        ),
        body: AppLocalization.text(
          'Have you recorded today’s expenses and income?',
          languageCode: settings.languageCode,
        ),
        soundUri: settings.notificationSoundUri,
        soundName: settings.notificationSoundName,
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
  List<Txn> get visibleTxns {
    _syncCache();
    return _visibleTxns ??= scopeFilter == null
        ? transactions
        : transactions.where((t) => t.scope == scopeFilter).toList();
  }

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

  // ---------------- App lock ----------------
  /// Is the PIN lock turned on?
  bool get hasAppLock => (settings.pinHash ?? '').isNotEmpty;

  /// Check a PIN against the stored hash. Always false when there is no lock,
  /// so callers cannot accidentally "unlock" an unprotected app with junk.
  bool verifyPin(String pin) =>
      hasAppLock && AppLock.verify(pin, settings.pinHash);

  /// Turn the lock on, or change an existing PIN.
  Future<void> setPin(String pin) async {
    if (!AppLock.isValidPin(pin)) {
      throw ArgumentError.value(pin, 'pin', 'A PIN must be 4-8 digits');
    }
    await updateSettings(settings.copyWith(pinHash: AppLock.hash(pin)));
  }

  /// Turn the lock off. This also drops biometric unlock, which only ever
  /// existed as a shortcut past the PIN.
  Future<void> clearPin() =>
      updateSettings(settings.copyWith(clearPin: true));

  /// Is fingerprint/face unlock switched on?
  ///
  /// Always false without a PIN: biometrics are a shortcut past the PIN, not
  /// a lock of their own, so there would be nothing to unlock.
  bool get biometricUnlock => hasAppLock && settings.biometricUnlock;

  /// Turning it on without a PIN is ignored rather than stored, so the flag
  /// on disk can never disagree with [biometricUnlock].
  Future<void> setBiometricUnlock(bool enabled) => updateSettings(
    settings.copyWith(biometricUnlock: enabled && hasAppLock),
  );

  // ---------------- Bank SMS ----------------
  /// Whether SMS is supported on this device (Android only).
  bool get smsSupported => SmsService.isSupported;

  /// Mirror everything the native SMS receiver needs into Android
  /// SharedPreferences: the notification flag, the app language, and the
  /// effective bank rules.
  ///
  /// The receiver runs even when the Flutter engine is not alive, so it
  /// cannot read Hive. Mirroring the rules keeps the native pre-filter (and
  /// therefore the arrival notification) in lockstep with the Dart parser:
  /// a carrier or shop SMS that matches no rule never produces a
  /// “bank SMS” notification.
  Future<void> syncNativeSmsPrefs() => SmsService.syncNotificationPrefs(
    enabled: settings.smsEnabled && settings.smsNotify,
    language: settings.languageCode,
    rulesJson: nativeRulesJson(),
  );

  /// The active bank rules (custom rules first, like [SmsParser.findRule])
  /// as JSON the native side can match against: normalized sender hints,
  /// normalized body hints, and the bank name in both app languages.
  String nativeRulesJson() {
    final active = [...smsRules, ...builtinBankRules]
        .where((rule) => isSmsRuleEnabled(rule.id))
        .toList();
    return jsonEncode([
      for (final rule in active)
        {
          's': [
            for (final hint in rule.senderHints)
              SmsParser.normalize(hint).toUpperCase(),
          ],
          'b': [for (final hint in rule.bodyHints) SmsParser.normalize(hint)],
          'fa': AppLocalization.text(rule.bankName, languageCode: 'fa'),
          'en': rule.bankName,
        },
    ]);
  }

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
        .map((sms) {
          final parsed = SmsParser.parse(
            sms.message,
            extraRules: smsRules,
            disabledRuleIds: disabledRuleIds,
          );
          // A pasted message the user already queued must survive a rule
          // toggle even when no bank matched it.
          return sms.manual ? parsed.asManual() : parsed;
        })
        .where((sms) => sms.isTransaction || sms.manual)
        .toList()
      ..sort((a, b) => b.message.date.compareTo(a.message.date));
    smsSuggestions = collapseTwins(refreshed);
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

  Future<void> _onIncomingSms(SmsMessage msg) async {
    final parsed = SmsParser.parse(
      msg,
      extraRules: smsRules,
      disabledRuleIds: settings.disabledSmsRuleIds.toSet(),
    );
    if (!parsed.isTransaction) return;
    final state = store.loadSmsState();
    if (state.containsKey(parsed.key)) return;

    // A duplicate confirmation of an event already queued or reviewed must
    // not create a second card for the same transaction.
    final twinQueued = smsSuggestions.any(isTwinSmsOf(parsed));
    final twinReviewed = smsHistory.any(
      (h) =>
          _twinKeyOf(h.message.address, h.direction, h.amount) ==
              _twinKey(parsed) &&
          h.message.date.difference(parsed.message.date).abs() <= twinWindow,
    );
    if (twinQueued || twinReviewed) {
      await store.setSmsState(
        parsed.key,
        SmsHistoryEntry.rejectedStatus,
        history: _smsHistoryEntry(parsed, SmsHistoryEntry.rejectedStatus),
      );
      return;
    }

    smsSuggestions = [
      parsed,
      ...smsSuggestions.where((e) => e.key != parsed.key),
    ]..sort((a, b) => b.message.date.compareTo(a.message.date));
    notifyListeners();
    onNewSmsSuggestion?.call();
  }

  /// Queues a bank message the user pasted into the review page.
  ///
  /// This is the permission-free counterpart of [_onIncomingSms]: the `safe`
  /// build never reads the inbox, but the parser, the rules, and the review
  /// sheet are identical. A message that matches no active bank rule is still
  /// accepted when it clearly contains an amount and a direction — the same
  /// "potential transaction" bar used when scanning unknown senders — so a
  /// paste from a bank the rule list does not cover is not thrown away.
  ///
  /// Duplicates are matched on the message body as well as the sender/time
  /// twin window, because a pasted message has no sender and may be pasted
  /// again after the window (or after a restart).
  SmsImportResult importSmsText(String rawText) {
    final text = rawText.trim();
    if (text.isEmpty) return SmsImportResult.notRecognized;

    final message = SmsMessage(
      id: 'pasted-${DateTime.now().microsecondsSinceEpoch}',
      address: '',
      body: text,
      date: DateTime.now(),
    );
    final parsed = SmsParser.parse(
      message,
      extraRules: smsRules,
      disabledRuleIds: settings.disabledSmsRuleIds.toSet(),
    );
    if (!parsed.isTransaction && !parsed.isPotentialUnrecognizedTransaction) {
      return SmsImportResult.notRecognized;
    }
    // Potential-but-unmatched messages are still queued: the review sheet
    // shows "Unknown bank" and the user confirms every field. They carry the
    // `manual` mark so `approveSms` accepts them without weakening the rule
    // check for inbox messages.
    final queued = parsed.isTransaction ? parsed : parsed.asManual();

    final normalized = SmsParser.normalize(text).trim();
    final alreadyQueued = smsSuggestions.any(
      (s) => SmsParser.normalize(s.message.body).trim() == normalized,
    );
    final alreadyReviewed = smsHistory.any(
      (h) => SmsParser.normalize(h.message.body).trim() == normalized,
    );
    if (alreadyQueued ||
        alreadyReviewed ||
        smsSuggestions.any(isTwinSmsOf(queued))) {
      return SmsImportResult.duplicate;
    }

    smsSuggestions = [queued, ...smsSuggestions]
      ..sort((a, b) => b.message.date.compareTo(a.message.date));
    notifyListeners();
    return SmsImportResult.added;
  }

  Future<bool> refreshSmsPermission() async {
    smsPermissionGranted = await SmsService.hasPermission();
    notifyListeners();
    return smsPermissionGranted;
  }

  /// Quiet probe of the notification permission (no system dialog).
  Future<bool> refreshNotificationPermission() async {
    try {
      notificationPermissionGranted = await reminder.notificationsEnabled();
    } catch (_) {
      // A platform without the plugin must never break startup or tests.
      notificationPermissionGranted = false;
    }
    notifyListeners();
    return notificationPermissionGranted;
  }

  Future<bool> requestSmsPermission() async {
    final ok = await SmsService.requestPermission();
    smsPermissionGranted = ok;
    if (ok) {
      await updateSettings(settings.copyWith(smsEnabled: true));
      // Fire-and-forget, but an inbox read failure must not surface as an
      // unhandled async error; the review page offers a manual retry.
      unawaited(syncSms().catchError((_) => 0));
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
          .map((sms) {
            final parsed = SmsParser.parse(
              sms.message,
              extraRules: smsRules,
              disabledRuleIds: disabledRuleIds,
            );
            // Manual pastes survive an inbox sync even when no rule matches.
            return sms.manual ? parsed.asManual() : parsed;
          })
          .where(
            (sms) =>
                (sms.isTransaction || sms.manual) &&
                !state.containsKey(sms.key),
          )
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
      final collapsed = collapseTwins(merged);
      for (final twin in merged.where(
        (s) => !collapsed.any((k) => k.key == s.key),
      )) {
        await store.setSmsState(
          twin.key,
          SmsHistoryEntry.rejectedStatus,
          history: _smsHistoryEntry(twin, SmsHistoryEntry.rejectedStatus),
        );
      }
      smsSuggestions = collapsed;

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
    // Inbox messages must match a bank rule, but a pasted message is an
    // explicit user decision: it may be recorded even when no rule matched
    // (the safe build depends on this).
    if (!sms.isTransaction && !sms.manual) return null;

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

  // ---------------------------------------------------------
  // Duplicate SMS collapse
  // ---------------------------------------------------------

  /// Banks such as Blu/Sina send a second confirmation message seconds after
  /// the transaction SMS (charge notice, balance echo…). Both parse into
  /// suggestions for the *same* real-world event, so recording one left its
  /// twin sitting in the review queue forever.
  static const Duration twinWindow = Duration(minutes: 2);

  static String _twinKeyOf(
    String address,
    SmsDirection direction,
    double amount,
  ) => '${address.toUpperCase()}|${direction.name}|${amount.round()}';

  static String _twinKey(ParsedSms s) =>
      _twinKeyOf(s.message.address, s.direction, s.amount);

  /// Whether two suggestions describe the same real-world event (same
  /// sender, direction and amount within [twinWindow]) while being distinct
  /// messages — the signature of a duplicate confirmation SMS.
  static bool isTwinSms(ParsedSms a, ParsedSms b) =>
      a.key != b.key &&
      _twinKey(a) == _twinKey(b) &&
      a.message.date.difference(b.message.date).abs() <= twinWindow;

  /// Keeps the newest of each twin pair; callers mark the collapsed
  /// duplicates rejected so later syncs never resurrect them.
  static List<ParsedSms> collapseTwins(List<ParsedSms> list) {
    final kept = <ParsedSms>[];
    for (final s in list) {
      if (kept.any(isTwinSmsOf(s))) continue;
      kept.add(s);
    }
    return kept;
  }

  static bool Function(ParsedSms) isTwinSmsOf(ParsedSms s) =>
      (other) => isTwinSms(s, other);

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
    await syncNativeSmsPrefs();
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
    await syncNativeSmsPrefs();
  }

  static String _smsNote(ParsedSms sms) {
    final parts = <String>[];
    if (sms.bankName != null && sms.bankName!.isNotEmpty) {
      parts.add(sms.bankName!.tr);
    }
    if (sms.cardMask != null && sms.cardMask!.isNotEmpty) {
      parts.add('Card {card}'.trArgs({'card': sms.cardMask}));
    }
    if (sms.reference != null && sms.reference!.isNotEmpty) {
      parts.add('Reference {reference}'.trArgs({'reference': sms.reference}));
    }
    if (parts.isEmpty) parts.add('Imported from SMS'.tr);
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
            note: 'Sale: {plan}'.trArgs({'plan': plan.name.tr}),
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
            note: 'Configuration sale (paid in {currency})'.trArgs({
              'currency': cur,
            }),
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
          note: 'Monthly salary'.tr,
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
        title: 'Home rent'.tr,
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
