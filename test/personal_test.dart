import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/core/jalali_utils.dart';
import 'package:poolland/data/ledger.dart';
import 'package:poolland/data/models.dart';
import 'package:poolland/data/repository.dart';
import 'package:poolland/data/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late LocalStore store;
  late AppRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('poolland_personal');
    store = await LocalStore.openAt(tmp.path);
    repo = AppRepository(store: store);
    await repo.reload();
  });

  tearDown(() async {
    await store.close();
    await tmp.delete(recursive: true);
  });

  // ---------------------------------------------------------------- حوزه

  test('دسته‌بندی‌های شخصی هنگام راه‌اندازی ساخته می‌شوند', () {
    final personal = repo.categoriesOf(TxnKind.expense, scope: TxnScope.personal);
    final income = repo.categoriesOf(TxnKind.income, scope: TxnScope.personal);
    expect(personal, isNotEmpty);
    expect(income, isNotEmpty);
    // دسته‌های کسب‌وکار جدا هستند
    final business = repo.categoriesOf(TxnKind.expense);
    for (final c in business) {
      expect(c.scope, TxnScope.business);
    }
  });

  test('دکمه‌های سریع پیش‌فرض ساخته می‌شوند', () {
    expect(repo.quickExpenses.length, 6);
    expect(repo.quickExpenses.first.scope, TxnScope.personal);
  });

  test('تراکنش‌های شخصی در سود کسب‌وکار لحاظ نمی‌شوند', () async {
    final cat = repo
        .categoriesOf(TxnKind.expense, scope: TxnScope.personal)
        .first;
    final businessCat = repo.categoriesOf(TxnKind.expense).first;

    await repo.addTxn(repo.buildTxn(
      kind: TxnKind.income,
      amount: 1000000,
      currency: 'IRT',
      date: DateTime.now(),
      categoryId: repo.defaultCategoryId(TxnKind.income),
    ));
    await repo.addTxn(repo.buildTxn(
      kind: TxnKind.expense,
      amount: 200000,
      currency: 'IRT',
      date: DateTime.now(),
      categoryId: businessCat.id,
      scope: TxnScope.business,
    ));
    await repo.addTxn(repo.buildTxn(
      kind: TxnKind.expense,
      amount: 500000,
      currency: 'IRT',
      date: DateTime.now(),
      categoryId: cat.id,
      scope: TxnScope.personal,
    ));

    // سود کسب‌وکار = ۱,۰۰۰,۰۰۰ − ۲۰۰,۰۰۰ (هزینه‌ی شخصی حساب نشده)
    final all = repo.summary();
    expect(all.profit, closeTo(300000, 0.01)); // همه: ۱۰۰۰۰۰۰-۷۰۰۰۰۰
    final biz = repo.summary(scope: TxnScope.business);
    expect(biz.profit, closeTo(800000, 0.01));
    final per = repo.summary(scope: TxnScope.personal);
    expect(per.expense, closeTo(500000, 0.01));
  });

  test('هزینه‌ی شخصیِ نقدی موجودی صندوق را کم نمی‌کند', () async {
    await repo.updateSettings(repo.settings.copyWith(openingCash: 1000000));
    final before = repo.cashBalance;
    final cat = repo
        .categoriesOf(TxnKind.expense, scope: TxnScope.personal)
        .first;
    await repo.addTxn(repo.buildTxn(
      kind: TxnKind.expense,
      amount: 250000,
      currency: 'IRT',
      date: DateTime.now(),
      categoryId: cat.id,
      scope: TxnScope.personal,
    ));
    expect(repo.cashBalance, closeTo(before, 0.01));
  });

  test('بک‌آپِ قدیمی بدون فیلد scope به‌عنوان کسب‌وکار بار می‌شود', () async {
    final data = store.exportAll();
    // فیلد scope را از همه‌ی تراکنش‌ها و دسته‌ها حذف می‌کنیم (شبیه نسخه ۱.۱)
    for (final m in data['transactions'] as List) {
      (m as Map).remove('scope');
    }
    for (final m in data['categories'] as List) {
      (m as Map).remove('scope');
    }
    await store.importAll(data);

    final loaded = store.loadTxns();
    for (final t in loaded) {
      expect(t.scope, TxnScope.business);
    }
    for (final c in store.loadCategories()) {
      expect(c.scope, TxnScope.business);
    }
  });

  test('پشتیبان‌گیری و بازگردانی شامل بودجه و قوانین تکرار است', () async {
    final cat = repo
        .categoriesOf(TxnKind.expense, scope: TxnScope.personal)
        .first;
    final b = Budget(id: 'b1', categoryId: cat.id, limit: 5000000);
    await repo.addBudget(b);
    await repo.addRecurring(RecurringRule(
      id: 'r1',
      title: 'اجاره',
      amount: 3000000,
      startDate: J.toDate(1405, 1, 1),
      dayOfMonth: 5,
      categoryId: cat.id,
    ));

    final data = store.exportAll();
    expect((data['budgets'] as List).length, 1);
    expect((data['recurring'] as List).length, 1);
    expect((data['quickExpenses'] as List).length, 6);

    await store.importAll(data);
    expect(store.loadBudgets().length, 1);
    expect(store.loadRecurring().length, 1);
  });

  // ---------------------------------------------------------------- بودجه

  test('محاسبه‌ی مصرف بودجه در ماه جاری', () async {
    final cat = repo
        .categoriesOf(TxnKind.expense, scope: TxnScope.personal)
        .firstWhere((c) => c.name.contains('خوراک'));
    await repo.addBudget(Budget(id: 'b1', categoryId: cat.id, limit: 1000000));

    final now = DateTime.now();
    for (var i = 0; i < 3; i++) {
      await repo.addTxn(repo.buildTxn(
        kind: TxnKind.expense,
        amount: 100000,
        currency: 'IRT',
        date: now,
        categoryId: cat.id,
        scope: TxnScope.personal,
      ));
    }

    final usages = repo.budgetUsages();
    expect(usages.length, 1);
    expect(usages.first.spent, closeTo(300000, 0.01));
    expect(usages.first.ratio, closeTo(0.3, 0.001));
    expect(usages.first.remaining, closeTo(700000, 0.01));
    expect(usages.first.isOver, isFalse);
    expect(usages.first.level, 0);
    expect(usages.first.categoryName, contains('خوراک'));
  });

  test('عبور از سقف بودجه تشخیص داده می‌شود', () async {
    final cat = repo
        .categoriesOf(TxnKind.expense, scope: TxnScope.personal)
        .first;
    await repo.addBudget(Budget(id: 'b1', categoryId: cat.id, limit: 100000));
    await repo.addTxn(repo.buildTxn(
      kind: TxnKind.expense,
      amount: 150000,
      currency: 'IRT',
      date: DateTime.now(),
      categoryId: cat.id,
      scope: TxnScope.personal,
    ));
    final u = repo.budgetUsages().first;
    expect(u.isOver, isTrue);
    expect(u.level, 2);
    expect(u.remaining, closeTo(-50000, 0.01));
  });

  test('هزینه‌ی ماهِ قبل در بودجه‌ی این ماه حساب نمی‌شود', () async {
    final cat = repo
        .categoriesOf(TxnKind.expense, scope: TxnScope.personal)
        .first;
    await repo.addBudget(Budget(id: 'b1', categoryId: cat.id, limit: 1000000));
    final lastMonth = J.addMonths(DateTime.now(), -1);
    await repo.addTxn(repo.buildTxn(
      kind: TxnKind.expense,
      amount: 900000,
      currency: 'IRT',
      date: lastMonth,
      categoryId: cat.id,
      scope: TxnScope.personal,
    ));
    expect(repo.budgetUsages().first.spent, closeTo(0, 0.01));
  });

  test('حذف بودجه', () async {
    final cat = repo
        .categoriesOf(TxnKind.expense, scope: TxnScope.personal)
        .first;
    await repo.addBudget(Budget(id: 'b1', categoryId: cat.id, limit: 1000));
    expect(repo.budgets.length, 1);
    await repo.deleteBudget('b1');
    expect(repo.budgets, isEmpty);
    expect(store.loadBudgets(), isEmpty);
  });

  // ------------------------------------------------- تکرارشونده‌ها

  test('سررسید ماهانه با روزِ مشخص درست محاسبه می‌شود', () {
    final r = RecurringRule(
      id: 'r',
      title: 'اجاره',
      amount: 1000,
      startDate: J.toDate(1405, 1, 1),
      dayOfMonth: 5,
      period: RecurringPeriod.monthly,
    );
    final dues = r.occurrencesUpTo(J.toDate(1405, 4, 30), limit: 12);
    expect(dues.length, 4);
    expect(J.of(dues.first).day, 5);
    expect(J.of(dues.first).month, 1);
    expect(J.of(dues.last).month, 4);
  });

  test('روزِ ۳۱ در ماه‌های ۲۹ و ۳۰ روزه به آخرِ ماه محدود می‌شود', () {
    final r = RecurringRule(
      id: 'r',
      title: 'قسط',
      amount: 1000,
      startDate: J.toDate(1404, 1, 1),
      dayOfMonth: 31,
      period: RecurringPeriod.monthly,
    );
    final dues = r.occurrencesUpTo(J.toDate(1404, 12, 29), limit: 20);
    for (final d in dues) {
      final j = J.of(d);
      final len = J.addMonths(J.toDate(j.year, j.month, 1), 1)
          .difference(J.toDate(j.year, j.month, 1))
          .inDays;
      expect(j.day, lessThanOrEqualTo(len));
    }
    expect(dues.length, 12);
  });

  test('قانونِ غیرفعال هیچ سررسیدی ندارد', () {
    final r = RecurringRule(
      id: 'r',
      title: 'x',
      amount: 1000,
      startDate: J.toDate(1405, 1, 1),
      enabled: false,
    );
    expect(r.pendingDues(DateTime.now()), isEmpty);
    expect(r.nextDue(DateTime.now()), isNull);
  });

  test('تاریخ پایان رعایت می‌شود', () {
    final r = RecurringRule(
      id: 'r',
      title: 'x',
      amount: 1000,
      startDate: J.toDate(1405, 1, 1),
      endDate: J.toDate(1405, 3, 1),
      period: RecurringPeriod.monthly,
    );
    final dues = r.occurrencesUpTo(J.toDate(1405, 12, 29), limit: 30);
    expect(dues.length, 3);
    expect(dues.last, J.toDate(1405, 3, 1));
  });

  test('ثبت خودکارِ قوانینِ سررسیدشده و عدم تکرار', () async {
    final cat = repo
        .categoriesOf(TxnKind.expense, scope: TxnScope.personal)
        .first;
    // از دو ماه پیش شروع شده با تکرار ماهانه
    await repo.addRecurring(RecurringRule(
      id: 'r1',
      title: 'اجاره',
      amount: 3000000,
      startDate: J.addMonths(DateTime.now(), -3),
      dayOfMonth: 1,
      categoryId: cat.id,
      period: RecurringPeriod.monthly,
    ));

    final before = repo.transactions.length;
    final n = await repo.postDueRecurring();
    expect(n, greaterThanOrEqualTo(3)); // ماه‌های گذشته + ماه جاری
    expect(repo.transactions.length, before + n);

    // هر تراکنش شخصی و با مبلغ درست
    final posted = repo.transactions.where((t) => t.note.contains('اجاره'));
    expect(posted.length, n);
    for (final t in posted) {
      expect(t.scope, TxnScope.personal);
      expect(t.amount, 3000000);
      expect(t.kind, TxnKind.expense);
    }

    // اجرای دوباره: چیزی اضافه نمی‌شود
    final again = await repo.postDueRecurring();
    expect(again, 0);
    expect(repo.transactions.length, before + n);
  });

  test('قانونِ غیرفعال چیزی ثبت نمی‌کند', () async {
    await repo.addRecurring(RecurringRule(
      id: 'r1',
      title: 'x',
      amount: 1000,
      startDate: J.addMonths(DateTime.now(), -2),
      enabled: false,
    ));
    final n = await repo.postDueRecurring();
    expect(n, 0);
  });

  test('حذف قانون تکرارشونده', () async {
    await repo.addRecurring(RecurringRule(
        id: 'r1', title: 'x', amount: 1, startDate: DateTime.now()));
    await repo.deleteRecurring('r1');
    expect(repo.recurringRules, isEmpty);
    expect(store.loadRecurring(), isEmpty);
  });

  // ------------------------------------------------- ثبت سریع

  test('ثبت سریع با مبلغ ثابت', () async {
    final q = QuickExpense(
        id: 'q1', label: 'تاکسی', amount: 50000, iconCodePoint: 0);
    await repo.addQuickButton(q);
    final before = repo.transactions.length;
    await repo.addQuickExpense(q);
    expect(repo.transactions.length, before + 1);
    final t = repo.transactions.first;
    expect(t.amount, 50000);
    expect(t.scope, TxnScope.personal);
    expect(t.kind, TxnKind.expense);
    expect(t.note, 'تاکسی');
  });

  test('ثبت سریع با مبلغِ لحظه‌ای', () async {
    final q = QuickExpense(id: 'q1', label: 'ناهار', iconCodePoint: 0);
    expect(q.hasFixedAmount, isFalse);
    final t = await repo.addQuickExpense(q, amount: 120000);
    expect(t.amount, 120000);
  });

  test('دکمه‌ی سریع با درآمد', () async {
    final cat = repo
        .categoriesOf(TxnKind.income, scope: TxnScope.personal)
        .firstWhere((c) => c.name.contains('حقوق'));
    final q = QuickExpense(
        id: 'q1',
        label: 'حقوق',
        amount: 20000000,
        kind: TxnKind.income,
        categoryId: cat.id,
        iconCodePoint: 0);
    final t = await repo.addQuickExpense(q);
    expect(t.kind, TxnKind.income);
    final per = repo.summary(scope: TxnScope.personal);
    expect(per.income, closeTo(20000000, 0.01));
  });

  test('حذف دکمه‌ی سریع', () async {
    await repo.addQuickButton(
        QuickExpense(id: 'q9', label: 'تست', iconCodePoint: 0));
    final n = repo.quickExpenses.length;
    await repo.deleteQuickButton('q9');
    expect(repo.quickExpenses.length, n - 1);
    expect(store.loadQuickExpenses().any((e) => e.id == 'q9'), isFalse);
  });

  // ------------------------------------------------- نمودارها

  test('سری روزانه ۳۰ نقطه و مجموعِ درست دارد', () async {
    final cat = repo
        .categoriesOf(TxnKind.expense, scope: TxnScope.personal)
        .first;
    final today = DateTime.now();
    await repo.addTxn(repo.buildTxn(
      kind: TxnKind.expense,
      amount: 10000,
      currency: 'IRT',
      date: today,
      categoryId: cat.id,
      scope: TxnScope.personal,
    ));
    await repo.addTxn(repo.buildTxn(
      kind: TxnKind.expense,
      amount: 5000,
      currency: 'IRT',
      date: J.addDays(today, -1),
      categoryId: cat.id,
      scope: TxnScope.personal,
    ));
    await repo.addTxn(repo.buildTxn(
      kind: TxnKind.expense,
      amount: 77777,
      currency: 'IRT',
      date: J.addDays(today, -60),
      categoryId: cat.id,
      scope: TxnScope.personal,
    ));

    final daily = Ledger.dailySeries(repo.transactions,
        days: 30, scope: TxnScope.personal);
    expect(daily.length, 30);
    final total = daily.fold<double>(0, (a, p) => a + p.expense);
    expect(total, closeTo(15000, 0.01)); // تراکنشِ ۶۰ روز پیش داخل بازه نیست
  });

  test('سری هفتگی تعدادِ درخواستی را برمی‌گرداند', () {
    final weekly = Ledger.weeklySeries(repo.transactions,
        weeks: 12, scope: TxnScope.personal);
    expect(weekly.length, 12);
    for (final p in weekly) {
      expect(p.label, 'هفته');
    }
  });

  test('نمودار ماهانه با فیلتر حوزه', () async {
    final cat = repo
        .categoriesOf(TxnKind.expense, scope: TxnScope.personal)
        .first;
    await repo.addTxn(repo.buildTxn(
      kind: TxnKind.expense,
      amount: 100000,
      currency: 'IRT',
      date: DateTime.now(),
      categoryId: cat.id,
      scope: TxnScope.personal,
    ));
    final personalSeries = repo.series(months: 6, scope: TxnScope.personal);
    final businessSeries = repo.series(months: 6, scope: TxnScope.business);
    expect(
        personalSeries.fold<double>(0, (a, p) => a + p.expense),
        closeTo(100000, 0.01));
    expect(businessSeries.fold<double>(0, (a, p) => a + p.expense),
        closeTo(0, 0.01));
  });

  // ------------------------------------------------- فیلتر UI

  test('تغییر فیلتر حوزه به رابط کاربری اطلاع می‌دهد', () {
    var notified = 0;
    repo.addListener(() => notified++);
    repo.setScopeFilter(TxnScope.personal);
    expect(repo.scopeFilter, TxnScope.personal);
    repo.setScopeFilter(null);
    expect(repo.scopeFilter, isNull);
    expect(notified, 2);
  });

  test('ماه شمسیِ جاری درست محاسبه می‌شود', () {
    final r = AppRepository.monthOf(DateTime.now());
    final j = J.of(DateTime.now());
    expect(r.year, j.year);
    expect(r.month, j.month);
    expect(J.of(r.start).day, 1);
    expect(r.end.isAfter(r.start), isTrue);
  });
}
