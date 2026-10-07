import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/core/jalali_utils.dart';
import 'package:poolland/data/ledger.dart';
import 'package:poolland/data/models.dart';

/// Accounting logic tests — no database required.
void main() {
  final now = DateTime(2026, 10, 4); // 1405/07/12

  Customer customer({
    String id = 'c1',
    double opening = 0,
    String name = 'Alex',
  }) => Customer(id: id, name: name, createdAt: now, openingBalance: opening);

  Txn txn({
    required TxnKind kind,
    required double amount,
    DateTime? date,
    String? customerId = 'c1',
    bool credit = false,
    String currency = 'IRT',
    double rate = 1,
  }) => Txn(
    id: 't${DateTime.now().microsecondsSinceEpoch}${amount.hashCode}',
    kind: kind,
    amount: amount,
    currency: currency,
    rateToBase: rate,
    date: date ?? now,
    customerId: customerId,
    credit: credit,
    createdAt: now,
  );

  group('Period summary', () {
    test('Income, expenses, and profit are calculated correctly', () {
      final txns = [
        txn(kind: TxnKind.income, amount: 1000000, credit: true),
        txn(kind: TxnKind.income, amount: 500000, credit: false),
        txn(kind: TxnKind.expense, amount: 300000, credit: false),
        txn(kind: TxnKind.receive, amount: 200000),
      ];
      final s = Ledger.summarize(txns);

      expect(s.income, 700000);
      expect(s.sales, 1500000);
      expect(s.expense, 300000);
      expect(s.profit, 400000);
      expect(s.received, 200000);
      expect(s.incomeCash, 500000);
      expect(s.cashIn, 700000); // 500 cash income + 200 collected
      expect(s.cashOut, 300000);
      expect(s.netCash, 400000);
      expect(s.txnCount, 4);
    });

    test('Credit-sale income is recognized as payments arrive', () {
      final c = customer();
      final sale = txn(
        kind: TxnKind.income,
        amount: 500000,
        credit: true,
      );
      final payment = txn(kind: TxnKind.receive, amount: 200000);
      final partial = Ledger.summarize([sale, payment]);

      expect(partial.sales, 500000);
      expect(partial.income, 200000);
      expect(partial.profit, 200000);
      expect(Ledger.customerBalance(c, [sale, payment]), 300000);

      final unpaid = Ledger.summarize([sale]);
      expect(unpaid.income, 0);
      expect(unpaid.profit, 0);
      expect(unpaid.sales, 500000);
    });

    test('Refunds are subtracted from profit', () {
      final s = Ledger.summarize([
        txn(kind: TxnKind.income, amount: 1000000),
        txn(kind: TxnKind.refund, amount: 400000),
      ]);
      expect(s.profit, 600000);
      expect(s.cashOut, 400000);
    });

    test('Payable settlements reduce cash but do not change profit', () {
      final s = Ledger.summarize([
        txn(kind: TxnKind.expense, amount: 200000, credit: true),
        txn(kind: TxnKind.payablePayment, amount: 80000),
      ]);
      expect(s.expense, 200000);
      expect(s.payablePayments, 80000);
      expect(s.profit, -200000);
      expect(s.cashOut, 80000);
    });

    test('Currency conversion uses the recorded rate', () {
      final s = Ledger.summarize([
        txn(kind: TxnKind.income, amount: 10, currency: 'USD', rate: 130000),
      ]);
      expect(s.income, 1300000);
    });

    test('Date-range filtering', () {
      final outOfRange = txn(
        kind: TxnKind.income,
        amount: 999,
        date: DateTime(2026, 5, 1),
      );
      final s = Ledger.summarize(
        [outOfRange, txn(kind: TxnKind.income, amount: 1000)],
        from: J.startOfMonth(now),
        to: J.endOfMonth(now),
      );
      expect(s.income, 1000);
    });
  });

  group('Contact balances', () {
    test('Credit sales create a balance that payments reduce', () {
      final c = customer();
      final txns = [
        txn(kind: TxnKind.income, amount: 800000, credit: true),
        txn(kind: TxnKind.receive, amount: 300000),
      ];
      expect(Ledger.customerBalance(c, txns), 500000);
    });

    test('Cash sales do not affect the balance', () {
      final c = customer();
      expect(
        Ledger.customerBalance(c, [txn(kind: TxnKind.income, amount: 800000)]),
        0,
      );
    });

    test('Opening balance, credit sale, and refund to a customer', () {
      final c = customer(opening: 200000);
      final txns = [
        txn(kind: TxnKind.income, amount: 1000000, credit: true),
        txn(kind: TxnKind.receive, amount: 500000),
        txn(kind: TxnKind.refund, amount: 100000),
      ];
      // 200,000 opening + 1,000,000 charged - 500,000 collected.
      // The refund is cash out of the till; it does not reduce what the
      // customer still owes us.
      expect(Ledger.customerBalance(c, txns), 700000);
    });

    test('Refunding a settled customer leaves their balance at zero', () {
      final c = customer();
      final sale = txn(kind: TxnKind.income, amount: 500000, credit: true);
      final payment = txn(kind: TxnKind.receive, amount: 500000);

      expect(Ledger.customerBalance(c, [sale, payment]), 0);

      // Service cancelled: we hand the 500,000 back.
      final refund = txn(kind: TxnKind.refund, amount: 500000);
      final txns = [sale, payment, refund];

      // The customer is square with us — we must not claim to owe them again.
      expect(Ledger.customerBalance(c, txns), 0);
      expect(Ledger.totals([c], txns).payable, 0);
      expect(Ledger.totals([c], txns).receivable, 0);

      // The money really did leave, and the sale no longer counts as profit.
      final s = Ledger.summarize(txns);
      expect(s.refunds, 500000);
      expect(s.profit, 0);
      expect(s.netCash, 0);
    });

    test('A refund does not move per-currency balances either', () {
      final c = customer();
      final txns = [
        txn(kind: TxnKind.income, amount: 40, credit: true, currency: 'USD'),
        txn(kind: TxnKind.refund, amount: 40, currency: 'USD'),
      ];
      expect(Ledger.customerCurrencyTotals(c, txns), {'USD': 40.0});
    });

    test('Overpayment produces a negative balance (payable)', () {
      final c = customer();
      final txns = [
        txn(kind: TxnKind.income, amount: 100000, credit: true),
        txn(kind: TxnKind.receive, amount: 250000),
      ];
      expect(Ledger.customerBalance(c, txns), -150000);
    });

    test('Receivable and payable totals', () {
      final a = customer(id: 'a', name: 'A');
      final b = customer(id: 'b', name: 'B');
      final txns = [
        txn(
          kind: TxnKind.income,
          amount: 500000,
          credit: true,
          customerId: 'a',
        ),
        txn(
          kind: TxnKind.expense,
          amount: 200000,
          credit: true,
          customerId: 'b',
        ),
      ];
      final totals = Ledger.totals([a, b], txns);
      expect(totals.receivable, 500000);
      expect(totals.payable, 200000);
      expect(totals.net, 300000);
      expect(totals.debtorsCount, 1);
      expect(totals.creditorsCount, 1);
    });

    test('Payable settlement reduces the contact balance', () {
      final c = customer();
      final txns = [
        txn(kind: TxnKind.expense, amount: 200000, credit: true),
        txn(kind: TxnKind.payablePayment, amount: 80000),
      ];
      expect(Ledger.customerBalance(c, txns), -120000);
      expect(Ledger.customerCurrencyTotals(c, txns)['IRT'], -120000);
    });

    test('Per-currency totals include the opening balance', () {
      final c = customer(opening: 250000);
      final txns = [txn(kind: TxnKind.income, amount: 100000, credit: true)];
      final map = Ledger.customerCurrencyTotals(c, txns);
      expect(map['IRT'], 350000);
      expect(
        Ledger.customerBalance(c, txns),
        350000,
        reason: 'Per-currency totals should match the overall balance',
      );
    });

    test('Settled balances are omitted from per-currency totals', () {
      final c = customer(opening: 250000);
      final txns = [txn(kind: TxnKind.receive, amount: 250000)];
      final map = Ledger.customerCurrencyTotals(c, txns);
      expect(map.containsKey('IRT'), isFalse, reason: 'The balance is zero');
      expect(Ledger.customerBalance(c, txns), 0);
    });

    test('Summary by currency', () {
      final c = customer();
      final txns = [
        txn(
          kind: TxnKind.income,
          amount: 20,
          currency: 'USD',
          rate: 130000,
          credit: true,
        ),
        txn(kind: TxnKind.receive, amount: 10, currency: 'USDT', rate: 129000),
      ];
      final map = Ledger.customerCurrencyTotals(c, txns);
      expect(map['USD'], 20);
      expect(map['USDT'], -10);
    });
  });

  group('Monthly series', () {
    test('Six months including Jalali months', () {
      final txns = [
        txn(kind: TxnKind.income, amount: 100, date: now),
        txn(kind: TxnKind.income, amount: 50, date: J.addMonths(now, -2)),
        txn(kind: TxnKind.expense, amount: 30, date: J.addMonths(now, -5)),
      ];
      final series = Ledger.monthlySeries(txns, months: 6, endMonth: now);
      expect(series.length, 6);
      expect(series.last.income, 100);
      expect(series[3].income, 50);
      expect(series.first.expense, 30);
    });
  });

  group('Subscription status', () {
    Subscription sub({required int daysFromNow}) => Subscription(
      id: 's1',
      customerId: 'c1',
      planName: 'Test plan',
      startDate: J.addDays(now, -30),
      endDate: J.addDays(now, daysFromNow),
      createdAt: now,
    );

    test('Active, expiring soon, and expired states', () {
      expect(
        Ledger.subStatus(sub(daysFromNow: 30), now: now),
        SubStatus.active,
      );
      expect(
        Ledger.subStatus(sub(daysFromNow: 2), now: now),
        SubStatus.expiringSoon,
      );
      expect(
        Ledger.subStatus(sub(daysFromNow: -1), now: now),
        SubStatus.expired,
      );
    });

    test('Days remaining are counted correctly', () {
      expect(Ledger.daysLeft(sub(daysFromNow: 5), now: now), 5);
      expect(Ledger.daysLeft(sub(daysFromNow: -3), now: now), -3);
    });

    test(
      'Alerts include soon-to-expire and recently expired subscriptions',
      () {
        final alerts = Ledger.alerts(
          [
            sub(daysFromNow: 40),
            sub(daysFromNow: 1),
            sub(daysFromNow: -5),
            sub(daysFromNow: -60),
          ],
          now: now,
          reminderDays: 3,
        );
        expect(alerts.length, 2);
      },
    );
  });

  group('Plans', () {
    test('Monthly plan end date follows the Jalali calendar', () {
      final p = Plan(
        id: 'p1',
        name: 'One month',
        price: 250000,
        durationValue: 1,
        durationUnit: PlanDurationUnit.month,
      );
      final start = J.toDate(1405, 7, 12);
      final end = p.endFrom(start);
      final endJ = J.of(end);
      expect([endJ.year, endJ.month, endJ.day], [1405, 8, 11]);
    });

    test('Three-month plan end date', () {
      final p = Plan(
        id: 'p1',
        name: 'Three months',
        durationValue: 3,
        durationUnit: PlanDurationUnit.month,
      );
      final end = J.of(p.endFrom(J.toDate(1405, 7, 12)));
      expect([end.year, end.month, end.day], [1405, 10, 11]);
    });

    test('Daily plan duration', () {
      final p = Plan(
        id: 'p1',
        name: 'One week',
        durationValue: 7,
        durationUnit: PlanDurationUnit.day,
      );
      final end = J.of(p.endFrom(J.toDate(1405, 7, 12)));
      expect([end.year, end.month, end.day], [1405, 7, 18]);
    });
  });

  group('Category report', () {
    test('Expenses are totaled by category', () {
      const cats = [Category(id: 'k1', name: 'Server', kind: TxnKind.expense)];
      final withCat = [
        txn(kind: TxnKind.expense, amount: 400000).copyWith(categoryId: 'k1'),
        txn(kind: TxnKind.expense, amount: 100000),
      ];
      final byCat = Ledger.byCategory(withCat, cats);
      expect(byCat['Server'], 400000);
      expect(byCat['Uncategorized'], 100000);
    });

    test('Income categories include receipts but exclude unpaid credit sales', () {
      const cats = [
        Category(id: 'income', name: 'VPN sales', kind: TxnKind.income),
      ];
      final txns = [
        txn(
          kind: TxnKind.income,
          amount: 500000,
          credit: true,
        ).copyWith(categoryId: 'income'),
        txn(
          kind: TxnKind.receive,
          amount: 200000,
        ).copyWith(categoryId: 'income'),
        txn(
          kind: TxnKind.income,
          amount: 100000,
        ).copyWith(categoryId: 'income'),
      ];

      final byCat = Ledger.byCategory(
        txns,
        cats,
        kind: TxnKind.income,
      );
      expect(byCat['VPN sales'], 300000);
    });
  });
}
