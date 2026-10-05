import '../core/jalali_utils.dart';
import 'models.dart';

/// ============================================================
///  Accounting logic (pure, testable functions).
///
///  Sign convention:
///   • Positive balance = the contact owes us (receivable).
///   • Negative balance = we owe the contact (payable).
///   • credit=true on income or expense means it is charged to the contact’s account.
/// ============================================================

/// A point on the monthly chart.
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

/// Summary for a date range (all amounts are converted to the base currency).
class Summary {
  final double income; // Sales and income (accrual basis).
  final double expense; // Expenses.
  final double refunds; // Refunds to customers.
  final double received; // Payments collected from customers.
  final double incomeCash; // Cash sales.
  final double expenseCash; // Cash expenses.
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
        'Income': income,
        'Expenses': expense,
        'Refunds': refunds,
        'Received': received,
        'Profit': profit,
        'Net cash': netCash,
      };
}

/// Totals across all accounts (current balance).
class Balances {
  final double receivable; // Total receivables from customers.
  final double payable; // Total amounts owed to others.
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

  /// Convert a transaction amount to the base currency using its recorded exchange rate.
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
    TxnScope? scope,
  }) {
    return txns.where((t) {
      if (!inRange(t.date, from, to)) return false;
      if (scope != null && t.scope != scope) return false;
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
      {DateTime? from, DateTime? to, String? customerId, TxnScope? scope}) {
    double income = 0,
        expense = 0,
        refunds = 0,
        received = 0,
        incomeCash = 0,
        expenseCash = 0;
    var count = 0;
    for (final t in filter(
      txns,
      from: from,
      to: to,
      customerId: customerId,
      scope: scope,
    )) {
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

  /// Effect of a transaction on a contact balance (in the base currency).
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

  /// Contact balance in the base currency.
  static double customerBalance(Customer c, Iterable<Txn> allTxns) {
    var bal = c.openingBalance;
    for (final t in allTxns) {
      if (t.customerId == c.id) bal += balanceEffect(t);
    }
    return bal;
  }

  /// Balance for each contact: customerId → amount (base currency).
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

  /// Total receivables and payables.
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

  /// Net balance for each contact by currency (without conversion).
  ///
  /// Note: the opening balance is also included in the base currency so the per-currency total
  /// matches the displayed overall balance.
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
    // Remove zero balances so irrelevant chips are not displayed.
    map.removeWhere((_, v) => v.abs() < 0.5);
    return map;
  }

  /// Monthly series (defaults to the last six Jalali months, including the current month).
  static List<MonthPoint> monthlySeries(
    List<Txn> txns, {
    int months = 6,
    DateTime? endMonth,
    TxnScope? scope,
  }) {
    final end = endMonth ?? DateTime.now();
    final start = J.startOfMonth(J.addMonths(end, -(months - 1)));
    final points = <MonthPoint>[];
    for (var i = 0; i < months; i++) {
      final mStart = J.addMonths(start, i);
      final mEnd = J.endOfMonth(mStart);
      final s = summarize(txns, from: mStart, to: mEnd, scope: scope);
      points.add(MonthPoint(monthStart: mStart, income: s.income, expense: s.expense));
    }
    return points;
  }

  /// Totals by category for a date range.
  static Map<String, double> byCategory(
    List<Txn> txns,
    List<Category> categories, {
    DateTime? from,
    DateTime? to,
    TxnKind? kind,
    TxnScope? scope,
    bool? personalOnly,
  }) {
    final names = {for (final c in categories) c.id: c.name};
    final out = <String, double>{};
    for (final t in filter(txns, from: from, to: to, kind: kind, scope: scope)) {
      if (!t.kind.isProfitKind) continue;
      final name = t.categoryId == null ? 'Uncategorized' : (names[t.categoryId] ?? 'Uncategorized');
      out[name] = (out[name] ?? 0) + base(t);
    }
    return out;
  }

  /// Totals by currency (original amounts, without conversion).
  static Map<String, double> byCurrency(
    List<Txn> txns, {
    DateTime? from,
    DateTime? to,
    TxnKind? kind,
    TxnScope? scope,
  }) {
    final out = <String, double>{};
    for (final t in filter(txns, from: from, to: to, kind: kind, scope: scope)) {
      out[t.currency] = (out[t.currency] ?? 0) + t.amount;
    }
    return out;
  }

  /// Top customers by purchases for a date range.
  static List<MapEntry<Customer, double>> topCustomers(
    List<Customer> customers,
    List<Txn> txns, {
    DateTime? from,
    DateTime? to,
    int limit = 5,
    TxnScope? scope,
  }) {
    final byId = {for (final c in customers) c.id: c};
    final sums = <String, double>{};
    for (final t in filter(
      txns,
      from: from,
      to: to,
      kind: TxnKind.income,
      scope: scope,
    )) {
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

  /// Subscription status.
  static SubStatus subStatus(Subscription s, {DateTime? now, int reminderDays = 3}) {
    final n = J.startOfDay(now ?? DateTime.now());
    final end = J.startOfDay(s.endDate);
    if (end.isBefore(n)) return SubStatus.expired;
    final left = J.daysBetween(n, end);
    return left <= reminderDays ? SubStatus.expiringSoon : SubStatus.active;
  }

  /// Days remaining (negative means expired).
  static int daysLeft(Subscription s, {DateTime? now}) {
    final n = J.startOfDay(now ?? DateTime.now());
    return J.daysBetween(n, J.startOfDay(s.endDate));
  }

  /// Subscriptions nearing expiry or already expired (for alerts).
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

  /// Suggested renewal end date (using Jalali months).
  static DateTime suggestEnd(DateTime start, int months) =>
      J.addMonths(start, months);

  /// Total expenses for a category and date range (in the base currency).
  static double spentIn(
    List<Txn> txns,
    String categoryId, {
    DateTime? from,
    DateTime? to,
  }) {
    var total = 0.0;
    for (final t in filter(txns, from: from, to: to, kind: TxnKind.expense)) {
      if (t.categoryId != categoryId) continue;
      total += base(t);
    }
    return total;
  }

  /// Daily series from [days] ago through today.
  static List<DayPoint> dailySeries(
    List<Txn> txns, {
    int days = 30,
    DateTime? endDay,
    TxnScope? scope,
  }) {
    final end = J.startOfDay(endDay ?? DateTime.now());
    final start = J.addDays(end, -(days - 1));
    final points = <DayPoint>[];
    for (var i = 0; i < days; i++) {
      final day = J.addDays(start, i);
      final dayEnd = DateTime(day.year, day.month, day.day, 23, 59, 59, 999);
      double expense = 0, income = 0;
      for (final t in filter(txns,
          from: day, to: dayEnd, kind: TxnKind.expense, scope: scope)) {
        expense += base(t);
      }
      for (final t in filter(txns,
          from: day, to: dayEnd, kind: TxnKind.income, scope: scope)) {
        income += base(t);
      }
      points.add(DayPoint(day: day, income: income, expense: expense));
    }
    return points;
  }

  /// Weekly series from [weeks] ago through the current week.
  static List<DayPoint> weeklySeries(
    List<Txn> txns, {
    int weeks = 12,
    DateTime? endDay,
    TxnScope? scope,
  }) {
    final end = J.startOfDay(endDay ?? DateTime.now());
    final points = <DayPoint>[];
    for (var i = weeks - 1; i >= 0; i--) {
      final weekEnd = J.addDays(end, -7 * i);
      final weekStart = J.addDays(weekEnd, -6);
      final s = summarize(txns, from: weekStart, to: J.endOfDay(weekEnd), scope: scope);
      points.add(DayPoint(
          day: weekStart, income: s.income, expense: s.expense, label: 'Week'));
    }
    return points;
  }
}

/// A point on a daily or weekly chart.
class DayPoint {
  final DateTime day;
  final double income;
  final double expense;
  final String label;

  const DayPoint({
    required this.day,
    required this.income,
    required this.expense,
    this.label = 'Day',
  });

}
