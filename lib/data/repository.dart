import 'dart:math';

import 'package:flutter/foundation.dart' show ChangeNotifier;

import '../core/jalali_utils.dart';
import '../core/money.dart';
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

  /// دفتر فعال (null = همه‌ی دفترها). فقط در حافظه نگه داشته می‌شود.
  String? _bookFilter;
  String? get bookFilter => _bookFilter;
  bool get isBookFiltered => _bookFilter != null;

  void setBookFilter(String? id) {
    if (id == _bookFilter) return;
    _bookFilter = (id == null || !settings.isKnownBook(id)) ? null : id;
    notifyListeners();
  }

  /// تراکنش‌های قابل مشاهده با فیلتر دفتر فعلی
  List<Txn> get visibleTxns => _bookFilter == null
      ? transactions
      : transactions.where((t) => t.bookId == _bookFilter).toList();

  /// دفتر پیش‌فرض تراکنش‌های جدید؛ اگر فیلتر فعال باشد همان دفتر انتخاب می‌شود
  String get newTxnBookId => _bookFilter ?? settings.defaultBookId;

  Book bookById(String? id) => settings.book(id);
  String bookName(String? id) => settings.book(id).name;

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

  List<Category> categoriesOf(TxnKind kind) =>
      categories.where((c) => c.kind == kind).toList();

  List<Subscription> subsOfCustomer(String customerId) =>
      subscriptions.where((s) => s.customerId == customerId).toList()
        ..sort((a, b) => b.endDate.compareTo(a.endDate));

  List<Txn> txnsOfCustomer(String customerId) =>
      Ledger.forCustomer(transactions, customerId);

  double balanceOf(Customer c) => Ledger.customerBalance(c, transactions);

  Balances get totals => Ledger.totals(customers, transactions);

  Summary summary({DateTime? from, DateTime? to, String? bookId}) => Ledger.summarize(
        transactions,
        from: from,
        to: to,
        bookId: bookId ?? _bookFilter,
      );

  /// خلاصه‌ی هر دفتر در یک بازه — برای مقایسه‌ی کسب‌وکار و شخصی
  List<MapEntry<Book, Summary>> summaryByBook({DateTime? from, DateTime? to}) => [
        for (final b in settings.books)
          MapEntry(b, Ledger.summarize(transactions, from: from, to: to, bookId: b.id)),
      ];

  List<MonthPoint> series({int months = 6}) =>
      Ledger.monthlySeries(transactions, months: months, bookId: _bookFilter);

  List<Subscription> get alerts =>
      Ledger.alerts(subscriptions, reminderDays: settings.reminderDays);

  int get activeSubsCount => Ledger.activeCount(subscriptions);

  Map<String, double> balancesMap() =>
      Ledger.balancesByCustomer(customers, transactions);

  /// موجودی نقدی/بانکی = موجودی اولیه + خالص جریان نقدی
  double get cashBalance => settings.openingCash + summary().netCash;

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
  }) async {
    final c = Customer(
      id: LocalStore.newId(),
      name: name.trim(),
      phone: phone.trim(),
      telegram: telegram.trim(),
      note: note.trim(),
      openingBalance: openingBalance,
      createdAt: DateTime.now(),
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
    String? bookId,
  }) async {
    final book = bookId ?? settings.defaultBookId;
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
        bookId: book,
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
        bookId: book,
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

  String? get defaultIncomeCategoryId {
    final list = categoriesOf(TxnKind.income);
    if (list.isEmpty) return null;
    for (final c in list) {
      if (c.name.contains('اشتراک')) return c.id;
    }
    return list.first.id;
  }

  String? get defaultExpenseCategoryId {
    final list = categoriesOf(TxnKind.expense);
    return list.isEmpty ? null : list.first.id;
  }

  // ---------------- تراکنش‌ها ----------------
  Txn buildTxn({
    required TxnKind kind,
    required double amount,
    required String currency,
    required DateTime date,
    String? categoryId,
    String? customerId,
    String? subscriptionId,
    bool credit = false,
    String note = '',
    String? bookId,
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
        createdAt: DateTime.now(),
        bookId: bookId ?? newTxnBookId,
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
  Future<void> addCategory(String name, TxnKind kind) async {
    final list = categoriesOf(kind);
    await store.putCategory(Category(
      id: LocalStore.newId(),
      name: name.trim(),
      kind: kind,
      sortOrder: list.isEmpty ? 0 : list.last.sortOrder + 1,
    ));
    await reload();
  }

  Future<void> renameCategory(Category c, String newName) async {
    await store.putCategory(Category(
        id: c.id, name: newName.trim(), kind: c.kind, sortOrder: c.sortOrder));
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
    settings = s;
    _syncGlobals();
    await store.saveSettings(s);
    notifyListeners();
  }

  // ---------------- دفترها ----------------
  Future<void> addBook(String name, {int color = 0xFF2563EB}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await upsertBook(Book(
      id: LocalStore.newId(),
      name: trimmed,
      color: color,
      sortOrder: settings.books.length,
    ));
  }

  Future<void> upsertBook(Book b) async {
    final list = [...settings.books];
    final i = list.indexWhere((x) => x.id == b.id);
    if (i >= 0) {
      list[i] = b;
    } else {
      list.add(b);
    }
    await updateSettings(settings.copyWith(books: list));
  }

  Future<void> setDefaultBook(String id) async {
    if (!settings.isKnownBook(id)) return;
    await updateSettings(settings.copyWith(defaultBookId: id));
  }

  /// حذف دفتر؛ تراکنش‌های آن به دفتر پیش‌فرض منتقل می‌شوند
  Future<void> removeBook(String id) async {
    if (settings.books.length <= 1) return;
    if (id == settings.defaultBookId) return;
    final fallback = settings.defaultBookId;
    for (final t in transactions.where((t) => t.bookId == id).toList()) {
      await store.putTxn(t.copyWith(bookId: fallback));
    }
    final list = settings.books.where((b) => b.id != id).toList();
    await updateSettings(settings.copyWith(books: list));
    if (_bookFilter == id) _bookFilter = fallback;
    notifyListeners();
  }

  /// تغییر دفتر گروهی از تراکنش‌های انتخابی (ابزار اصلاح داده‌های قدیمی)
  Future<void> moveTxnsToBook(Iterable<String> txnIds, String bookId) async {
    if (!settings.isKnownBook(bookId)) return;
    final ids = txnIds.toSet();
    for (final t in transactions.where((t) => ids.contains(t.id)).toList()) {
      if (t.bookId == bookId) continue;
      await store.putTxn(t.copyWith(bookId: bookId));
    }
    await reload();
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
    final planList = plans.isEmpty ? LocalStore.defaultPlans() : plans;
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
      if (settings.currencies.any((c) => c.code == cur) && customers.isNotEmpty) {
        final c = customers[rnd.nextInt(customers.length)];
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

    // ---------- دفتر شخصی: هزینه و درآمد روزانه ----------
    String? catOf(String name, TxnKind kind) {
      final list = categoriesOf(kind).where((c) => c.name == name).toList();
      return list.isEmpty ? null : list.first.id;
    }

    const salaryCat = 'حقوق و درآمد شخصی';
    const personal = <String, double>{
      'اجاره و خانه': 4500000,
      'خوراک و خرید روزانه': 2800000,
      'قبض و شارژ': 900000,
      'هزینه شخصی': 600000,
    };
    for (var m = 0; m < 6; m++) {
      // حقوق ماهانه
      await store.putTxn(Txn(
        id: LocalStore.newId(),
        kind: TxnKind.income,
        amount: 32000000,
        currency: 'IRT',
        rateToBase: 1,
        date: J.addDays(J.addMonths(now, -m), -2),
        categoryId: catOf(salaryCat, TxnKind.income),
        note: 'حقوق ماه',
        createdAt: now,
        bookId: BookIds.personal,
      ));
      // هزینه‌های شخصی
      for (final e in personal.entries) {
        await store.putTxn(Txn(
          id: LocalStore.newId(),
          kind: TxnKind.expense,
          amount: e.value * (0.8 + rnd.nextDouble() * 0.4),
          currency: 'IRT',
          rateToBase: 1,
          date: J.addDays(J.addMonths(now, -m), -rnd.nextInt(25)),
          categoryId: catOf(e.key, TxnKind.expense),
          note: e.key,
          createdAt: now,
          bookId: BookIds.personal,
        ));
      }
    }

    await reload();
  }
}
