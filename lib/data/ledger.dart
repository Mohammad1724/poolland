import '../core/jalali_utils.dart';
import 'models.dart';

/// ============================================================
///  منطق حسابداری (توابع خالص و قابل تست)
///
///  قرارداد علامت‌ها:
///   • موجودی مثبت  = طرف حساب به ما بدهکار است (طلب ما)
///   • موجودی منفی = ما به طرف حساب بدهکاریم (بستانکار)
///   • credit=true در درآمد/هزینه یعنی «نسیه / روی حساب»
/// ============================================================

/// یک نقطه روی نمودار ماهانه
class MonthPoint {
  final DateTime monthStart;
  final double income;
  final double expense;
  const MonthPoint({
    required this.monthStart,
    required this.income,
    required this.expense,
  });

  double get profit => income - expense;
}

/// خلاصه‌ی یک بازه‌ی زمانی (همه به ارز پایه تبدیل می‌شوند)
class Summary {
  final double income; // فروش/درآمد (تعهدی)
  final double expense; // هزینه
  final double refunds; // برگشت وجه به مشتری
  final double received; // وصولی از مشتری‌ها
  final double incomeCash; // فروش‌های نقدی
  final double expenseCash; // هزینه‌های نقدی
  final int txnCount;

  const Summary({
    this.income = 0,
    this.expense = 0,
    this.refunds = 0,
    this.received = 0,
    this.incomeCash = 0,
    this.expenseCash = 0,
    this.txnCount = 0,
  });

  double get profit => income - expense - refunds;
  double get cashIn => incomeCash + received;
  double get cashOut => expenseCash + refunds;
  double get netCash => cashIn - cashOut;

  static const empty = Summary();

  Map<String, double> get asMap => {
        'درآمد': income,
        'هزینه': expense,
        'برگشت وجه': refunds,
        'وصولی': received,
        'سود': profit,
        'خالص نقد': netCash,
      };
}

/// جمع کل همه‌ی حساب‌ها (وضعیت لحظه‌ای)
class Balances {
  final double receivable; // جمع طلب ما از مشتری‌ها
  final double payable; // جمع بدهی ما به دیگران
  final int debtorsCount;
  final int creditorsCount;

  const Balances({
    this.receivable = 0,
    this.payable = 0,
    this.debtorsCount = 0,
    this.creditorsCount = 0,
  });

  double get net => receivable - payable;
}

class Ledger {
  Ledger._();

  /// تبدیل مبلغ تراکنش به ارز پایه با نرخ ثبت‌شده‌ی همان تراکنش
  static double base(Txn t) => t.amount * t.rateToBase;

  static bool inRange(DateTime d, DateTime? from, DateTime? to) {
    if (from != null && d.isBefore(J.startOfDay(from))) return false;
    if (to != null && d.isAfter(J.endOfDay(to))) return false;
    return true;
  }

  static Iterable<Txn> filter(
    Iterable<Txn> txns, {
    DateTime? from,
    DateTime? to,
    TxnKind? kind,
    String? customerId,
    String? categoryId,
    String? search,
  }) {
    return txns.where((t) {
      if (!inRange(t.date, from, to)) return false;
      if (kind != null && t.kind != kind) return false;
      if (customerId != null && t.customerId != customerId) return false;
      if (categoryId != null && t.categoryId != categoryId) return false;
      if (search != null && search.trim().isNotEmpty) {
        final q = search.trim().toLowerCase();
        if (!t.note.toLowerCase().contains(q) &&
            !t.amount.toStringAsFixed(0).contains(q)) {
          return false;
        }
      }
      return true;
    });
  }

  static Summary summarize(Iterable<Txn> txns,
      {DateTime? from, DateTime? to, String? customerId}) {
    double income = 0,
        expense = 0,
        refunds = 0,
        received = 0,
        incomeCash = 0,
        expenseCash = 0;
    var count = 0;
    for (final t in filter(txns, from: from, to: to, customerId: customerId)) {
      final v = base(t);
      count++;
      switch (t.kind) {
        case TxnKind.income:
          income += v;
          if (!t.credit) incomeCash += v;
          break;
        case TxnKind.expense:
          expense += v;
          if (!t.credit) expenseCash += v;
          break;
        case TxnKind.receive:
          received += v;
          break;
        case TxnKind.refund:
          refunds += v;
          break;
      }
    }
    return Summary(
      income: income,
      expense: expense,
      refunds: refunds,
      received: received,
      incomeCash: incomeCash,
      expenseCash: expenseCash,
      txnCount: count,
    );
  }

  /// اثر یک تراکنش روی موجودی طرف حساب (به ارز پایه)
  static double balanceEffect(Txn t) {
    final v = base(t);
    switch (t.kind) {
      case TxnKind.income:
        return t.credit ? v : 0;
      case TxnKind.expense:
        return t.credit ? -v : 0;
      case TxnKind.receive:
        return -v;
      case TxnKind.refund:
        return -v;
    }
  }

  static List<Txn> forCustomer(Iterable<Txn> txns, String customerId) =>
      txns.where((t) => t.customerId == customerId).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  /// موجودی یک طرف حساب به ارز پایه
  static double customerBalance(Customer c, Iterable<Txn> allTxns) {
    var bal = c.openingBalance;
    for (final t in allTxns) {
      if (t.customerId == c.id) bal += balanceEffect(t);
    }
    return bal;
  }

  /// موجودی هر طرف حساب: customerId → مبلغ (ارز پایه)
  static Map<String, double> balancesByCustomer(
      List<Customer> customers, List<Txn> txns) {
    final map = <String, double>{for (final c in customers) c.id: c.openingBalance};
    for (final t in txns) {
      final id = t.customerId;
      if (id == null || !map.containsKey(id)) continue;
      map[id] = (map[id] ?? 0) + balanceEffect(t);
    }
    return map;
  }

  /// جمع طلب/بدهی کل
  static Balances totals(List<Customer> customers, List<Txn> txns) {
    final map = balancesByCustomer(customers, txns);
    double rec = 0, pay = 0;
    int dc = 0, cc = 0;
    for (final c in customers) {
      if (c.archived) continue;
      final b = map[c.id] ?? 0;
      if (b > 0.5) {
        rec += b;
        dc++;
      } else if (b < -0.5) {
        pay += -b;
        cc++;
      }
    }
    return Balances(receivable: rec, payable: pay, debtorsCount: dc, creditorsCount: cc);
  }

  /// خالص حساب هر طرف حساب به تفکیک ارز (بدون تبدیل)
  ///
  /// نکته: «بدهی/طلب اولیه» به ارز پایه هم لحاظ می‌شود تا مجموعِ تفکیک‌ارز
  /// با مانده‌ی کلِ نمایش‌داده‌شده یکی باشد.
  static Map<String, double> customerCurrencyTotals(
    Customer c,
    Iterable<Txn> txns, {
    String baseCurrency = 'IRT',
  }) {
    final map = <String, double>{};
    if (c.openingBalance.abs() > 0.5) {
      map[baseCurrency] = (map[baseCurrency] ?? 0) + c.openingBalance;
    }
    for (final t in txns) {
      if (t.customerId != c.id) continue;
      final delta = switch (t.kind) {
        TxnKind.income => t.credit ? t.amount : 0.0,
        TxnKind.expense => t.credit ? -t.amount : 0.0,
        TxnKind.receive => -t.amount,
        TxnKind.refund => -t.amount,
      };
      if (delta != 0) map[t.currency] = (map[t.currency] ?? 0) + delta;
    }
    // مقادیرِ صفر (تراز‌شده) را حذف می‌کنیم تا چیپِ بی‌ربط نمایش داده نشود
    map.removeWhere((_, v) => v.abs() < 0.5);
    return map;
  }

  /// سری ماهانه (پیش‌فرض: ۶ ماه شمسی اخیر تا ماه جاری)
  static List<MonthPoint> monthlySeries(
    List<Txn> txns, {
    int months = 6,
    DateTime? endMonth,
  }) {
    final end = endMonth ?? DateTime.now();
    final start = J.startOfMonth(J.addMonths(end, -(months - 1)));
    final points = <MonthPoint>[];
    for (var i = 0; i < months; i++) {
      final mStart = J.addMonths(start, i);
      final mEnd = J.endOfMonth(mStart);
      final s = summarize(txns, from: mStart, to: mEnd);
      points.add(MonthPoint(monthStart: mStart, income: s.income, expense: s.expense));
    }
    return points;
  }

  /// جمع به تفکیک دسته‌بندی در یک بازه
  static Map<String, double> byCategory(
    List<Txn> txns,
    List<Category> categories, {
    DateTime? from,
    DateTime? to,
    TxnKind? kind,
  }) {
    final names = {for (final c in categories) c.id: c.name};
    final out = <String, double>{};
    for (final t in filter(txns, from: from, to: to, kind: kind)) {
      if (!t.kind.isProfitKind) continue;
      final name = t.categoryId == null ? 'بدون دسته' : (names[t.categoryId] ?? 'بدون دسته');
      out[name] = (out[name] ?? 0) + base(t);
    }
    return out;
  }

  /// جمع به تفکیک ارز (مبلغ اصلی، بدون تبدیل)
  static Map<String, double> byCurrency(
    List<Txn> txns, {
    DateTime? from,
    DateTime? to,
    TxnKind? kind,
  }) {
    final out = <String, double>{};
    for (final t in filter(txns, from: from, to: to, kind: kind)) {
      out[t.currency] = (out[t.currency] ?? 0) + t.amount;
    }
    return out;
  }

  /// مشتری‌های برتر بر اساس خرید در یک بازه
  static List<MapEntry<Customer, double>> topCustomers(
    List<Customer> customers,
    List<Txn> txns, {
    DateTime? from,
    DateTime? to,
    int limit = 5,
  }) {
    final byId = {for (final c in customers) c.id: c};
    final sums = <String, double>{};
    for (final t in filter(txns, from: from, to: to, kind: TxnKind.income)) {
      final id = t.customerId;
      if (id == null || !byId.containsKey(id)) continue;
      sums[id] = (sums[id] ?? 0) + base(t);
    }
    final list = sums.entries
        .map((e) => MapEntry(byId[e.key]!, e.value))
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list.take(limit).toList();
  }

  /// وضعیت اشتراک
  static SubStatus subStatus(Subscription s, {DateTime? now, int reminderDays = 3}) {
    final n = J.startOfDay(now ?? DateTime.now());
    final end = J.startOfDay(s.endDate);
    if (end.isBefore(n)) return SubStatus.expired;
    final left = J.daysBetween(n, end);
    return left <= reminderDays ? SubStatus.expiringSoon : SubStatus.active;
  }

  /// روزهای باقی‌مانده (منفی = گذشته)
  static int daysLeft(Subscription s, {DateTime? now}) {
    final n = J.startOfDay(now ?? DateTime.now());
    return J.daysBetween(n, J.startOfDay(s.endDate));
  }

  /// اشتراک‌های نزدیک انقضا یا منقضی‌شده (برای هشدارها)
  static List<Subscription> alerts(
    List<Subscription> subs, {
    DateTime? now,
    int reminderDays = 3,
    int expiredWithinDays = 14,
  }) {
    final n = J.startOfDay(now ?? DateTime.now());
    final out = subs.where((s) {
      final left = J.daysBetween(n, J.startOfDay(s.endDate));
      if (left >= 0) return left <= reminderDays;
      return -left <= expiredWithinDays;
    }).toList()
      ..sort((a, b) => a.endDate.compareTo(b.endDate));
    return out;
  }

  static int activeCount(List<Subscription> subs, {DateTime? now}) =>
      subs.where((s) => subStatus(s, now: now) != SubStatus.expired).length;

  /// تاریخ پایان پیشنهادی برای تمدید (ماه‌های شمسی)
  static DateTime suggestEnd(DateTime start, int months) =>
      J.addMonths(start, months);
}
