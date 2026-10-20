import '../core/format_utils.dart';
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
  /// Income recognized when cash is received: cash sales plus customer receipts.
  final double income;

  /// Total recorded sales/income, including unpaid credit sales.
  final double sales;
  final double expense; // Expenses.
  final double refunds; // Refunds to customers.
  final double received; // Payments collected from customers.
  final double
  payablePayments; // Cash paid to settle previously recorded payables.
  final double incomeCash; // Direct cash sales (excludes customer collections).
  final double expenseCash; // Cash expenses.
  final int txnCount;

  const Summary({
    this.income = 0,
    this.sales = 0,
    this.expense = 0,
    this.refunds = 0,
    this.received = 0,
    this.payablePayments = 0,
    this.incomeCash = 0,
    this.expenseCash = 0,
    this.txnCount = 0,
  });

  double get profit => income - expense - refunds;
  double get cashIn => incomeCash + received;
  double get cashOut => expenseCash + refunds + payablePayments;
  double get netCash => cashIn - cashOut;

  static const empty = Summary();

  Map<String, double> get asMap => {
    'Income received': income,
    'Sales recorded': sales,
    'Expenses': expense,
    'Refunds': refunds,
    'Received': received,
    'Payable payments': payablePayments,
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

  /// Whether a transaction counts as **realized income**.
  ///
  /// One definition for the whole app, because the same period is aggregated
  /// in several places — [summarize] for the summary cards and the
  /// weekly/monthly series, [byCategory] for the income breakdown, and
  /// [dailySeries] for the daily bars — and the user compares those numbers
  /// against each other on one screen.
  ///
  /// Realized income is a cash sale plus money actually collected from a
  /// contact. A credit sale is a receivable, not income: it becomes income
  /// through the `receive` entry that settles it, and counting it twice (or
  /// counting it before it is paid) is exactly what the sign convention in
  /// the README rules out.
  static bool isRecognizedIncome(Txn t) =>
      (t.kind == TxnKind.income && !t.credit) || t.kind == TxnKind.receive;

  /// Whether a transaction counts as an **expense** on the charts.
  ///
  /// Refunds are deliberately not folded in here: [Summary] keeps them as
  /// their own line so that `profit = income - expense - refunds` stays
  /// readable, and the weekly/monthly series plot `expense` only. The daily
  /// bars have to agree with them.
  static bool isChartedExpense(Txn t) => t.kind == TxnKind.expense;

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
        // Persian and Arabic-Indic digits are normalized on both sides so a
        // search typed with either keyboard matches stored Latin-digit data.
        final q = Fmt.normalizeDigits(search.trim().toLowerCase());
        if (!Fmt.normalizeDigits(t.note.toLowerCase()).contains(q) &&
            !t.amount.toStringAsFixed(0).contains(q)) {
          return false;
        }
      }
      return true;
    });
  }

  static Summary summarize(
    Iterable<Txn> txns, {
    DateTime? from,
    DateTime? to,
    String? customerId,
    TxnScope? scope,
  }) {
    double income = 0,
        sales = 0,
        expense = 0,
        refunds = 0,
        received = 0,
        payablePayments = 0,
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
      // Recognize revenue only when the money is actually there: cash sales
      // and customer collections. A credit sale stays a receivable until a
      // `receive` entry settles it. Routed through the shared predicate so
      // the charts cannot drift away from this.
      if (isRecognizedIncome(t)) income += v;
      switch (t.kind) {
        case TxnKind.income:
          sales += v;
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
        case TxnKind.payablePayment:
          payablePayments += v;
          break;
      }
    }
    return Summary(
      income: income,
      sales: sales,
      expense: expense,
      refunds: refunds,
      received: received,
      payablePayments: payablePayments,
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
        // A refund is cash handed back to the customer. It reduces profit and
        // cash (see [summarize]) but settles nothing: the customer does not
        // start owing us less, and we do not start owing them more. Returning
        // -v here used to leave a fully refunded customer sitting at a
        // negative balance, i.e. the app claimed we still owed them the money
        // we had just paid out.
        return 0;
      case TxnKind.payablePayment:
        return v;
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
    List<Customer> customers,
    List<Txn> txns,
  ) {
    final map = <String, double>{
      for (final c in customers) c.id: c.openingBalance,
    };
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
    return Balances(
      receivable: rec,
      payable: pay,
      debtorsCount: dc,
      creditorsCount: cc,
    );
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
        // Mirrors [balanceEffect]: a cash refund does not move the balance.
        TxnKind.refund => 0.0,
        TxnKind.payablePayment => t.amount,
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
      points.add(
        MonthPoint(monthStart: mStart, income: s.income, expense: s.expense),
      );
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
    // Subcategories roll up into their parent, so a report shows the
    // total spent on "car" including the "fuel" child, not two rows.
    final byId = {for (final c in categories) c.id: c};
    String nameOf(String? id) {
      if (id == null) return 'Uncategorized';
      var c = byId[id];
      if (c == null) return 'Uncategorized';
      final parent = c.parentId == null ? null : byId[c.parentId];
      return (parent ?? c).name;
    }

    final out = <String, double>{};
    for (final t in filter(txns, from: from, to: to, scope: scope)) {
      final recognizedIncome = isRecognizedIncome(t);
      final isExpense = isChartedExpense(t);
      final include = switch (kind) {
        TxnKind.income => recognizedIncome,
        TxnKind.expense => isExpense,
        null => recognizedIncome || isExpense,
        _ => false,
      };
      if (!include) continue;
      final name = nameOf(t.categoryId);
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
    for (final t in filter(
      txns,
      from: from,
      to: to,
      kind: kind,
      scope: scope,
    )) {
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
    final list =
        sums.entries.map((e) => MapEntry(byId[e.key]!, e.value)).toList()
          ..sort((a, b) => b.value.compareTo(a.value));
    return list.take(limit).toList();
  }

  /// Subscription status.
  static SubStatus subStatus(
    Subscription s, {
    DateTime? now,
    int reminderDays = 3,
  }) {
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

  /// Whether [s] has been superseded by a newer subscription for the same
  /// customer and service plan.
  static bool isSuperseded(Subscription s, List<Subscription> all) {
    final end = J.startOfDay(s.endDate);
    for (final other in all) {
      if (other.id == s.id) continue;
      if (other.customerId != s.customerId) continue;
      if (other.planName != s.planName) continue;
      if (J.startOfDay(other.endDate).isAfter(end)) return true;
    }
    return false;
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
      if (isSuperseded(s, subs)) return false;
      final left = J.daysBetween(n, J.startOfDay(s.endDate));
      if (left >= 0) return left <= reminderDays;
      return -left <= expiredWithinDays;
    }).toList()..sort((a, b) => a.endDate.compareTo(b.endDate));
    return out;
  }

  static int activeCount(List<Subscription> subs, {DateTime? now}) =>
      subs.where((s) => subStatus(s, now: now) != SubStatus.expired).length;

  /// Suggested renewal end date (using Jalali months).
  static DateTime suggestEnd(DateTime start, int months) =>
      J.addMonths(start, months);

  /// Total expenses for a category and date range (in the base currency).
  ///
  /// When [categories] is supplied, expenses recorded under direct
  /// subcategories of [categoryId] also count toward the parent category.
  static double spentIn(
    List<Txn> txns,
    String categoryId, {
    DateTime? from,
    DateTime? to,
    TxnScope? scope,
    List<Category>? categories,
  }) {
    final childIds = categories == null
        ? const <String>{}
        : categories
              .where((c) => c.parentId == categoryId)
              .map((c) => c.id)
              .toSet();
    var total = 0.0;
    for (final t in filter(
      txns,
      from: from,
      to: to,
      kind: TxnKind.expense,
      scope: scope,
    )) {
      final cid = t.categoryId;
      if (cid != categoryId && !childIds.contains(cid)) continue;
      total += base(t);
    }
    return total;
  }

  /// Daily series from [days] ago through today.
  ///
  /// Single pass over the transactions: each one is placed in its day bucket
  /// directly. The previous implementation re-scanned the whole list twice per
  /// day (sixty passes for a 30-day chart), which made the personal page
  /// noticeably janky once a ledger grew to a few thousand rows.
  ///
  /// Buckets follow the same recognition as [weeklySeries] and
  /// [monthlySeries] — [isRecognizedIncome] and [isChartedExpense] — because
  /// all three sit behind one Daily/Weekly/Monthly switch on the same card.
  /// They used to disagree: the daily bars summed *every* `income` entry
  /// regardless of `credit` and ignored customer receipts entirely, so for a
  /// seller whose sales are mostly on credit the daily chart showed money the
  /// summary card right above it did not count, and the three modes of one
  /// chart told three different stories about one month.
  static List<DayPoint> dailySeries(
    List<Txn> txns, {
    int days = 30,
    DateTime? endDay,
    TxnScope? scope,
  }) {
    final end = J.startOfDay(endDay ?? DateTime.now());
    final start = J.addDays(end, -(days - 1));
    final income = List<double>.filled(days, 0);
    final expense = List<double>.filled(days, 0);
    for (final t in txns) {
      final asIncome = isRecognizedIncome(t);
      final asExpense = isChartedExpense(t);
      if (!asIncome && !asExpense) continue;
      if (scope != null && t.scope != scope) continue;
      final day = J.startOfDay(t.date);
      if (day.isBefore(start) || day.isAfter(end)) continue;
      final index = day.difference(start).inDays;
      if (index < 0 || index >= days) continue;
      final v = base(t);
      if (asIncome) {
        income[index] += v;
      } else {
        expense[index] += v;
      }
    }
    return [
      for (var i = 0; i < days; i++)
        DayPoint(
          day: J.addDays(start, i),
          income: income[i],
          expense: expense[i],
        ),
    ];
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
      final s = summarize(
        txns,
        from: weekStart,
        to: J.endOfDay(weekEnd),
        scope: scope,
      );
      points.add(
        DayPoint(
          day: weekStart,
          income: s.income,
          expense: s.expense,
          label: 'Week',
        ),
      );
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
