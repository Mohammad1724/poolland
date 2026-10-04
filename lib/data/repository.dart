import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../core/jalali_utils.dart';
import '../core/money.dart';
import '../core/notifications/notify.dart';
import '../core/sms/bank_rules.dart';
import '../core/sms/sms_models.dart';
import '../core/sms/sms_parser.dart';
import '../core/sms/sms_service.dart';
import 'ledger.dart';
import 'models.dart';
import 'store.dart';

/// مغز برنامه: داده‌ها را در حافظه نگه می‌دارد، در Hive ذخیره می‌کند
/// و به رابط کاربری خبر می‌دهد.
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

  // ---- حسابداری شخصی ----
  List<Budget> budgets = [];
  List<RecurringRule> recurringRules = [];
  List<QuickExpense> quickExpenses = [];

  /// فیلتر حوزه‌ی نمایش در رابط کاربری (null = همه)
  TxnScope? scopeFilter;

  void setScopeFilter(TxnScope? scope) {
    scopeFilter = scope;
    notifyListeners();
  }

  // ---- پیامک بانکی ----
  List<ParsedSms> smsSuggestions = [];
  List<BankRule> smsRules = [];
  bool smsPermissionGranted = false;
  bool smsBusy = false;
  bool _smsInited = false;

  /// آماده‌سازی اولیه (باز کردن دیتابیس)
  Future<void> init() async {
    _store ??= await LocalStore.open();
    _loadFrom(_store!);
    _ready = true;
    notifyListeners();
  }

  void _loadFrom(LocalStore s) {
    settings = s.loadSettings();
    customers = s.loadCustomers()..sort((a, b) => a.name.compareTo(b.name));
    subscriptions = s.loadSubscriptions()
      ..sort((a, b) => a.endDate.compareTo(b.endDate));
    transactions = s.loadTxns()..sort((a, b) => b.date.compareTo(a.date));
    categories = s.loadCategories();
    plans = s.loadPlans();
    smsRules = s.loadSmsRules();
    budgets = s.loadBudgets();
    recurringRules = s.loadRecurring();
    quickExpenses = s.loadQuickExpenses();
    _syncGlobals();
  }

  void _syncGlobals() => Money.sync(settings);

  Future<void> reload() async {
    if (_store == null) return;
    _loadFrom(_store!);
    notifyListeners();
  }

  // ---------------- دسترسی‌های سریع ----------------
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

  String customerName(String? id) => customerById(id)?.name ?? 'بدون مشتری';

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

  String categoryName(String? id) => categoryById(id)?.name ?? 'بدون دسته';

  List<Category> categoriesOf(TxnKind kind, {TxnScope? scope}) =>
      categories
          .where((c) => c.kind == kind && c.scope == (scope ?? TxnScope.business))
          .toList();

  List<Subscription> subsOfCustomer(String customerId) =>
      subscriptions.where((s) => s.customerId == customerId).toList()
        ..sort((a, b) => b.endDate.compareTo(a.endDate));

  List<Txn> txnsOfCustomer(String customerId) =>
      Ledger.forCustomer(transactions, customerId);

  double balanceOf(Customer c) => Ledger.customerBalance(c, transactions);

  Balances get totals => Ledger.totals(customers, transactions);

  /// تراکنش‌های یک حوزه‌ی مشخص (اگر null باشد، همه)
  List<Txn> scopeTxns(TxnScope? scope) => scope == null
      ? transactions
      : transactions.where((t) => t.scope == scope).toList();

  /// تراکنش‌های کسب‌وکار — یعنی همه به‌جز موارد «شخصی».
  /// این مبنای تمام محاسبات کسب‌وکار است تا هزینه‌های شخصی
  /// سودِ فروش وی‌پی‌ان را خراب نکند.
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

  /// موجودی نقدی/بانکی = موجودی اولیه + خالص جریان نقدی (فقط کسب‌وکار)
  double get cashBalance =>
      settings.openingCash + Ledger.summarize(businessTxns).netCash;

  /// فهرست بدهکارها (به ما بدهکار) مرتب‌شده
  List<MapEntry<Customer, double>> debtorsList() {
    final map = balancesMap();
    final list = activeCustomers
        .map((c) => MapEntry(c, map[c.id] ?? 0))
        .where((e) => e.value > 0.5)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list;
  }

  /// فهرست بستانکارها (ما به آن‌ها بدهکاریم)
  List<MapEntry<Customer, double>> creditorsList() {
    final map = balancesMap();
    return activeCustomers
        .map((e) => MapEntry(e, map[e.id] ?? 0))
        .where((e) => e.value < -0.5)
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));
  }

  // ---------------- مشتری‌ها ----------------
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

  /// حذف مشتری؛ [withData] یعنی تراکنش‌ها و اشتراک‌های او هم حذف شوند
  Future<void> deleteCustomer(String id, {bool withData = true}) async {
    if (withData) {
      for (final t in transactions.where((t) => t.customerId == id).toList()) {
        await store.deleteTxn(t.id);
      }
    } else {
      for (final t in transactions.where((t) => t.customerId == id).toList()) {
        await store.putTxn(t.copyWith(clearCustomer: true));
      }
    }
    for (final s in subscriptions.where((s) => s.customerId == id).toList()) {
      await store.deleteSubscription(s.id);
    }
    await store.deleteCustomer(id);
    await reload();
  }

  // ---------------- اشتراک‌ها ----------------
  Future<Subscription> saveSubscription(Subscription s) async {
    await store.putSubscription(s);
    await reload();
    return s;
  }

  Future<void> deleteSubscription(String id) async {
    await store.deleteSubscription(id);
    await reload();
  }

  /// ثبت فروش اشتراک (+ ثبت درآمد و پرداخت در همان لحظه)
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
      await store.putTxn(Txn(
        id: LocalStore.newId(),
        kind: TxnKind.income,
        amount: price,
        currency: currencyCode,
        rateToBase: settings.currency(currencyCode).rateToBase,
        date: J.dateOnly(start),
        categoryId: (categoryId == null || categoryId.isEmpty)
            ? defaultIncomeCategoryId
            : categoryId,
        customerId: customer.id,
        subscriptionId: s.id,
        credit: true, // کل مبلغ به حساب مشتری بدهکار می‌شود
        note: note.isEmpty ? 'فروش $title' : note,
        createdAt: DateTime.now(),
      ));
    }

    final cur = receiveCurrency ?? currencyCode;
    if (received > 0) {
      await store.putTxn(Txn(
        id: LocalStore.newId(),
        kind: TxnKind.receive,
        amount: received,
        currency: cur,
        rateToBase: settings.currency(cur).rateToBase,
        date: J.dateOnly(start),
        customerId: customer.id,
        subscriptionId: s.id,
        note: 'دریافت بابت $title',
        createdAt: DateTime.now(),
      ));
    }

    await reload();
    return s;
  }

  /// تمدید اشتراک: اشتراک جدید از فردای تاریخ پایان قبلی
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
    if (customer == null) throw StateError('مشتری پیدا نشد');
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
      note: 'تمدید ${old.planName}',
      categoryId: categoryId,
      deviceCount: old.deviceCount,
    );
  }

  String? get defaultIncomeCategoryId => defaultCategoryId(TxnKind.income);

  String? get defaultExpenseCategoryId => defaultCategoryId(TxnKind.expense);

  /// اولین دسته‌بندی مناسب برای یک نوع/حوزه
  String? defaultCategoryId(TxnKind kind, {TxnScope scope = TxnScope.business}) {
    final list = categoriesOf(kind, scope: scope);
    if (list.isEmpty) return null;
    if (kind == TxnKind.income) {
      for (final c in list) {
        if (c.name.contains('اشتراک')) return c.id;
      }
    }
    return list.first.id;
  }

  // ---------------- تراکنش‌ها ----------------
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
  }) =>
      Txn(
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
    transactions = [...transactions, t]..sort((a, b) => b.date.compareTo(a.date));
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

  // ================= حسابداری شخصی =================

  /// بازه‌ی ماه شمسیِ جاری (برای بودجه و نمودار ماهانه)
  static DateTimeRangeOfMonth monthOf(DateTime d) {
    final j = J.of(d);
    final start = J.toDate(j.year, j.month, 1);
    final end = J.endOfDay(J.addDays(J.addMonths(start, 1), -1));
    return DateTimeRangeOfMonth(start: start, end: end, year: j.year, month: j.month);
  }

  /// وضعیت مصرف همه‌ی بودجه‌ها در ماه جاری
  List<BudgetUsage> budgetUsages({DateTime? now}) {
    final range = monthOf(now ?? DateTime.now());
    return budgets.map((b) {
      final cat = categories.where((c) => c.id == b.categoryId).firstOrNull;
      return BudgetUsage(
        budget: b,
        categoryName: cat?.name ?? 'دسته حذف‌شده',
        spent: Ledger.spentIn(
          transactions,
          b.categoryId,
          from: range.start,
          to: range.end,
        ),
      );
    }).toList()
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
    recurringRules =
        recurringRules.map((e) => e.id == r.id ? r : e).toList();
    await store.putRecurring(r);
    notifyListeners();
  }

  Future<void> deleteRecurring(String id) async {
    recurringRules = recurringRules.where((e) => e.id != id).toList();
    await store.deleteRecurring(id);
    notifyListeners();
  }

  /// ثبت خودکارِ تراکنش‌های تکرارشونده‌ای که سررسیدشان رسیده است.
  /// تعداد تراکنش‌های ایجادشده را برمی‌گرداند.
  Future<int> postDueRecurring({DateTime? now}) async {
    final today = now ?? DateTime.now();
    var created = 0;
    for (final r in List<RecurringRule>.from(recurringRules)) {
      final dues = r.pendingDues(today);
      if (dues.isEmpty) continue;
      for (final d in dues) {
        await store.putTxn(Txn(
          id: LocalStore.newId(),
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
        ));
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

  /// ثبت یک هزینه‌ی سریع از روی دکمه‌های داشبورد
  Future<Txn> addQuickExpense(QuickExpense q, {double? amount, DateTime? date}) {
    return addTxn(Txn(
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
    ));
  }

  Future<void> addQuickButton(QuickExpense q) async {
    quickExpenses = [...quickExpenses, q]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
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

  /// ثبت سریع دریافت/پرداخت برای یک مشتری
  Future<void> addPayment({
    required Customer customer,
    required double amount,
    required String currencyCode,
    required DateTime date,
    bool isReceive = true,
    String note = '',
  }) =>
      addTxn(Txn(
        id: LocalStore.newId(),
        kind: isReceive ? TxnKind.receive : TxnKind.refund,
        amount: amount,
        currency: currencyCode,
        rateToBase: settings.currency(currencyCode).rateToBase,
        date: date,
        customerId: customer.id,
        note: note.isEmpty ? (isReceive ? 'دریافت وجه' : 'پرداخت وجه') : note,
        createdAt: DateTime.now(),
      ));

  // ---------------- دسته‌بندی‌ها ----------------
  Future<void> addCategory(String name, TxnKind kind,
      {TxnScope scope = TxnScope.business}) async {
    final list = categoriesOf(kind, scope: scope);
    await store.putCategory(Category(
      id: LocalStore.newId(),
      name: name.trim(),
      kind: kind,
      sortOrder: list.isEmpty ? 0 : list.last.sortOrder + 1,
      scope: scope,
    ));
    await reload();
  }

  Future<void> renameCategory(Category c, String newName) async {
    await store.putCategory(Category(
        id: c.id,
        name: newName.trim(),
        kind: c.kind,
        sortOrder: c.sortOrder,
        scope: c.scope));
    await reload();
  }

  Future<void> deleteCategory(String id) async {
    for (final t in transactions.where((t) => t.categoryId == id).toList()) {
      await store.putTxn(t.copyWith(clearCategory: true));
    }
    await store.deleteCategory(id);
    await reload();
  }

  // ---------------- پلن‌ها ----------------
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
    await store.deletePlan(id);
    await reload();
  }

  // ---------------- تنظیمات ----------------
  Future<void> updateSettings(AppSettings s) async {
    final reminderChanged = s.dailyReminder != settings.dailyReminder ||
        s.reminderHour != settings.reminderHour ||
        s.reminderMinute != settings.reminderMinute;
    settings = s;
    _syncGlobals();
    await store.saveSettings(s);
    notifyListeners();
    if (reminderChanged) await syncDailyReminder();
  }

  /// فعال/غیرفعال کردن یادآور روزانه بر اساس تنظیمات
  Future<void> syncDailyReminder() async {
    if (!reminder.supported) return;
    try {
      if (settings.dailyReminder) {
        await reminder.scheduleDaily(
          hour: settings.reminderHour,
          minute: settings.reminderMinute,
        );
      } else {
        await reminder.cancelDaily();
      }
    } catch (_) {
      // اگر اعلان در دسترس نبود، برنامه نباید از کار بیفتد
    }
  }

  /// تراکنش‌های قابل‌نمایش با احتساب فیلتر حوزه
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

  // ---------------- پیامک بانکی ----------------
  /// آیا این دستگاه اصلاً پیامک دارد؟ (فقط اندروید)
  bool get smsSupported => SmsService.isSupported;

  /// تعداد پیشنهادهای در انتظار تأیید
  int get smsPendingCount => smsSuggestions.length;

  /// آماده‌سازی گوش دادن به پیامک‌های جدید
  void initSms() {
    if (_smsInited || !SmsService.isSupported) return;
    _smsInited = true;
    SmsService.init();
    SmsService.onSmsReceived = _onIncomingSms;
  }

  Future<void> _onIncomingSms(SmsMessage msg) async {
    final parsed = SmsParser.parse(msg, extraRules: smsRules);
    if (!parsed.isTransaction) return;
    final state = store.loadSmsState();
    if (state.containsKey(parsed.key)) return;

    smsSuggestions = [parsed, ...smsSuggestions.where((e) => e.key != parsed.key)]
      ..sort((a, b) => b.message.date.compareTo(a.message.date));
    notifyListeners();

    if (settings.smsAutoApprove && parsed.confident) {
      await approveSms(parsed);
    }
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

  /// خواندن پیامک‌ها و ساخت فهرست پیشنهادها
  /// برمی‌گرداند: تعداد پیشنهادهای جدید
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

      final pending = <ParsedSms>[];
      for (final m in messages) {
        if (state.containsKey(m.key)) continue;
        final parsed = SmsParser.parse(m, extraRules: smsRules);
        if (parsed.isTransaction) {
          pending.add(parsed);
        } else {
          // پیامک‌های غیرمالی را دیگر هر بار بررسی نمی‌کنیم
          await store.setSmsState(m.key, 'ignored');
        }
      }

      final known = smsSuggestions.map((e) => e.key).toSet();
      final merged = <ParsedSms>[
        ...smsSuggestions,
        ...pending.where((p) => !known.contains(p.key)),
      ]..sort((a, b) => b.message.date.compareTo(a.message.date));
      smsSuggestions = merged;

      await updateSettings(
          settings.copyWith(smsLastSyncAt: DateTime.now().millisecondsSinceEpoch));
      notifyListeners();
      return pending.length;
    } finally {
      smsBusy = false;
      notifyListeners();
    }
  }

  /// تطبیق پیامک با مشتری از طریق شناسه‌های بانکی او
  Customer? matchCustomerForSms(ParsedSms sms) {
    for (final c in activeCustomers) {
      if (c.bankIdentifiers.isEmpty) continue;
      if (SmsParser.matchesIdentifiers(sms, c.bankIdentifiers)) return c;
    }
    return null;
  }

  /// تأیید یک پیشنهاد و تبدیل آن به تراکنش واقعی
  Future<Txn?> approveSms(
    ParsedSms sms, {
    Customer? customer,
    TxnKind? kind,
    String? categoryId,
    double? amount,
  }) async {
    final cust = customer ?? matchCustomerForSms(sms);
    final k = kind ??
        (sms.direction == SmsDirection.deposit
            ? (cust != null ? TxnKind.receive : TxnKind.income)
            : TxnKind.expense);

    String? cat = categoryId;
    if (cat == null || cat.isEmpty) {
      cat = k == TxnKind.expense ? defaultExpenseCategoryId : defaultIncomeCategoryId;
    }

    final cur = sms.currency;
    final txn = Txn(
      id: LocalStore.newId(),
      kind: k,
      amount: amount ?? sms.amount,
      currency: cur,
      rateToBase: settings.currency(cur).rateToBase,
      date: sms.message.date,
      categoryId: (k == TxnKind.income || k == TxnKind.expense) ? cat : null,
      customerId: cust?.id,
      credit: false,
      note: _smsNote(sms),
      createdAt: DateTime.now(),
    );
    await store.putTxn(txn);
    await store.setSmsState(sms.key, 'approved');
    smsSuggestions = smsSuggestions.where((e) => e.key != sms.key).toList();
    await reload();
    return txn;
  }

  /// رد کردن یک پیشنهاد (دیگر نمایش داده نمی‌شود)
  Future<void> rejectSms(ParsedSms sms) async {
    await store.setSmsState(sms.key, 'rejected');
    smsSuggestions = smsSuggestions.where((e) => e.key != sms.key).toList();
    notifyListeners();
  }

  /// رد کردن همه‌ی پیشنهادها
  Future<void> rejectAllSms() async {
    for (final s in smsSuggestions) {
      await store.setSmsState(s.key, 'rejected');
    }
    smsSuggestions = [];
    notifyListeners();
  }

  /// پاک کردن تاریخچه‌ی بررسی‌شده‌ها (همه چیز دوباره بررسی می‌شود)
  Future<void> resetSmsState() async {
    await store.clearSmsState();
    smsSuggestions = [];
    notifyListeners();
  }

  Future<void> addSmsRule(BankRule rule) async {
    await store.putSmsRule(rule);
    await reload();
  }

  Future<void> deleteSmsRule(String id) async {
    await store.deleteSmsRule(id);
    await reload();
  }

  static String _smsNote(ParsedSms sms) {
    final parts = <String>[];
    if (sms.bankName != null && sms.bankName!.isNotEmpty) parts.add(sms.bankName!);
    if (sms.cardMask != null && sms.cardMask!.isNotEmpty) parts.add('کارت ${sms.cardMask}');
    if (sms.reference != null && sms.reference!.isNotEmpty) {
      parts.add('پیگیری ${sms.reference}');
    }
    if (parts.isEmpty) parts.add('ثبت‌شده از پیامک');
    return parts.join(' · ');
  }

  // ---------------- پشتیبان‌گیری ----------------
  Map<String, dynamic> exportData() => store.exportAll();

  Future<void> importData(Map<String, dynamic> data) async {
    await store.importAll(data);
    await reload();
  }

  Future<void> wipeAll() async {
    await store.clearAll();
    await reload();
  }

  /// داده‌ی نمونه برای تست سریع و دموی گیت‌هاب
  Future<void> loadDemoData() async {
    await store.clearAll();

    // همگام‌سازی حافظه با دیتابیس: clearAll() همه چیز را پاک می‌کند و
    // دسته‌ها و پلن‌های پیش‌فرض با شناسه‌ی جدید ساخته می‌شوند.
    // بدون این reload، فهرست‌های درون‌حافظه‌ای (plans/customers/categories)
    // هنوز به رکوردهای حذف‌شده اشاره می‌کنند و تراکنش‌های یتیم می‌سازند.
    await reload();

    final rnd = Random(1405);
    final names = [
      'علی رضایی',
      'مریم احمدی',
      'حسین کریمی',
      'سارا محمدی',
      'رضا نوری',
      'نگار تهرانی',
      'امیر صادقی',
      'فاطمه یوسفی',
    ];

    // اگر پلنی در دیتابیس نیست، پلن‌های پیش‌فرض را «ذخیره» می‌کنیم تا
    // اشتراک‌ها بتوانند به یک پلن معتبر اشاره کنند (و تمدید کار کند)
    var planList = plans;
    if (planList.isEmpty) {
      for (final p in LocalStore.defaultPlans()) {
        await store.putPlan(p);
      }
      await reload();
      planList = plans;
    }

    // مشتری‌هایی که در همین اجرا ساخته می‌شوند (برای ارجاع‌های بعدی)
    final createdCustomers = <Customer>[];
    final now = J.today;

    for (var i = 0; i < names.length; i++) {
      final c = Customer(
        id: LocalStore.newId(),
        name: names[i],
        phone: '0912000010$i',
        note: i == 0 ? 'مشتری قدیمی - معمولاً با تتر پرداخت می‌کند' : '',
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
        await store.putTxn(Txn(
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
          note: 'فروش ${plan.name}',
          createdAt: start,
        ));
        final paid = rnd.nextDouble();
        if (paid < 0.75) {
          final amount = paid < 0.45 ? plan.price : (plan.price / 2).roundToDouble();
          await store.putTxn(Txn(
            id: LocalStore.newId(),
            kind: TxnKind.receive,
            amount: amount,
            currency: plan.currency,
            rateToBase: settings.currency(plan.currency).rateToBase,
            date: J.addDays(start, 1 + rnd.nextInt(12)),
            customerId: c.id,
            note: amount == plan.price ? 'تسویه کامل' : 'علی‌الحساب',
            createdAt: start,
          ));
        }
        start = J.addDays(end, 1);
        if (start.isAfter(now)) break;
      }
    }

    // هزینه‌های ماهانه‌ی ثابت
    const expenses = <String, double>{
      'خرید سرور / VPS': 4200000,
      'دامنه و SSL': 650000,
      'پنل و لایسنس': 1800000,
      'تبلیغات و بازاریابی': 900000,
      'اینترنت و ابزار کار': 400000,
    };
    for (var m = 0; m < 6; m++) {
      for (final e in expenses.entries) {
        final cat = categoriesOf(TxnKind.expense)
            .where((c) => c.name == e.key)
            .toList();
        await store.putTxn(Txn(
          id: LocalStore.newId(),
          kind: TxnKind.expense,
          amount: e.value * (0.85 + rnd.nextDouble() * 0.3),
          currency: 'IRT',
          rateToBase: 1,
          date: J.addDays(J.addMonths(now, -m), -rnd.nextInt(20)),
          categoryId: cat.isEmpty ? defaultExpenseCategoryId : cat.first.id,
          note: e.key,
          createdAt: now,
        ));
      }
    }

    // چند فروش با تتر و دلار برای نمایش چند‌ارزی
    for (final cur in ['USD', 'USDT']) {
      if (settings.currencies.any((c) => c.code == cur) && createdCustomers.isNotEmpty) {
        final c = createdCustomers[rnd.nextInt(createdCustomers.length)];
        await store.putTxn(Txn(
          id: LocalStore.newId(),
          kind: TxnKind.income,
          amount: 15,
          currency: cur,
          rateToBase: settings.currency(cur).rateToBase,
          date: J.addDays(now, -rnd.nextInt(40)),
          categoryId: defaultIncomeCategoryId,
          customerId: c.id,
          credit: false,
          note: 'فروش کانفیگ (پرداخت $cur)',
          createdAt: now,
        ));
      }
    }

    // ---------- داده‌ی نمونه‌ی حسابداری شخصی ----------
    final personalExp = <String, double>{
      'خوراک و رستوران': 380000,
      'حمل‌ونقل و سوخت': 120000,
      'قبوض (آب، برق، گاز)': 450000,
      'اینترنت و شارژ موبایل': 200000,
      'تفریح و سرگرمی': 150000,
      'خرید شخصی و پوشاک': 600000,
    };
    for (final e in personalExp.entries) {
      final cat = categoriesOf(TxnKind.expense, scope: TxnScope.personal)
          .where((c) => c.name == e.key)
          .toList();
      final count = 2 + rnd.nextInt(4);
      for (var k = 0; k < count; k++) {
        await store.putTxn(Txn(
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
        ));
      }
    }

    // حقوق ماهانه (درآمد شخصی)
    final salaryCat = categoriesOf(TxnKind.income, scope: TxnScope.personal)
        .where((c) => c.name == 'حقوق')
        .toList();
    for (var m = 0; m < 3; m++) {
      await store.putTxn(Txn(
        id: LocalStore.newId(),
        kind: TxnKind.income,
        amount: 25000000,
        currency: 'IRT',
        rateToBase: 1,
        date: J.toDate(J.of(J.addMonths(now, -m)).year,
            J.of(J.addMonths(now, -m)).month, 28),
        categoryId: salaryCat.isEmpty ? null : salaryCat.first.id,
        note: 'حقوق ماهانه',
        scope: TxnScope.personal,
        createdAt: now,
      ));
    }

    // یک بودجه‌ی نمونه برای خوراک
    final foodCat = categoriesOf(TxnKind.expense, scope: TxnScope.personal)
        .where((c) => c.name.contains('خوراک'))
        .toList();
    if (foodCat.isNotEmpty) {
      await store.putBudget(Budget(
        id: LocalStore.newId(),
        categoryId: foodCat.first.id,
        limit: 3000000,
      ));
    }

    // یک قانونِ تکرارشونده‌ی نمونه (از ماه قبل شروع شده)
    final rentCat = categoriesOf(TxnKind.expense, scope: TxnScope.personal)
        .where((c) => c.name.contains('مسکن'))
        .toList();
    await store.putRecurring(RecurringRule(
      id: LocalStore.newId(),
      title: 'اجاره خانه',
      amount: 8000000,
      categoryId: rentCat.isEmpty ? null : rentCat.first.id,
      period: RecurringPeriod.monthly,
      dayOfMonth: 5,
      startDate: J.addMonths(now, -1),
    ));

    await reload();
  }
}

/// بازه‌ی یک ماه شمسی
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
