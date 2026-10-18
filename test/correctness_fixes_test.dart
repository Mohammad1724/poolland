import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:poolland/core/jalali_utils.dart';
import 'package:poolland/core/localization.dart';
import 'package:poolland/core/sms/sms_models.dart';
import 'package:poolland/data/models.dart';
import 'package:poolland/data/repository.dart';
import 'package:poolland/data/store.dart';
import 'package:poolland/ui/customers_page.dart';
import 'package:poolland/ui/forms/sell_subscription_page.dart';
import 'package:poolland/ui/sms_page.dart';
import 'package:poolland/ui/theme.dart';

/// Regression tests for the correctness bugs found in the 1.4.0 UX audit
/// (`docs/ux-audit-1.4.0.md`, section «سطح ۰») that can only be seen on screen.
///
/// Each one was a place where the UI said something the ledger did not mean,
/// or could not be drawn at all:
///
///  * a contact with no name took the whole customers list down;
///  * the sale form's outstanding-debt line was frozen at whatever the two
///    amount fields held when the page last rebuilt for another reason;
///  * the SMS review sheet guessed its section from whichever transaction
///    happened to be newest, which is usually a personal one.
///
/// The fourth level-0 bug — the daily chart recognizing income differently
/// from the weekly and monthly modes of the same chart — is pure accounting
/// and is pinned in `ledger_test.dart`.
///
/// **Every store and repository call lives in `setUp`, never in a test body.**
/// `testWidgets` runs the body inside `FakeAsync`, where a real file-I/O
/// future never completes, so `await repo.…` in a body stalls the whole
/// `flutter test` run instead of failing. `setUp` runs outside that zone,
/// which is why the rest of the suite does it that way too.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late LocalStore store;
  late AppRepository repo;

  Future<void> openStore() async {
    tmp = await Directory.systemTemp.createTemp('poolland_correctness');
    store = await LocalStore.openAt(tmp.path);
    repo = AppRepository(store: store);
  }

  Future<void> closeStore() async {
    await store.close();
    await tmp.delete(recursive: true);
  }

  Widget wrap(Widget child) {
    AppLocalization.languageCode = 'en';
    return ChangeNotifierProvider<AppRepository>.value(
      value: repo,
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(),
        builder: (context, c) => Directionality(
          textDirection: TextDirection.ltr,
          child: c ?? const SizedBox(),
        ),
        home: Scaffold(body: child),
      ),
    );
  }

  /// The sale form's main list. There is exactly one, so the first scrollable
  /// inside it is the form's own.
  Finder formScrollable() => find
      .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
      .first;

  group('a contact with no name', () {
    setUp(() async {
      await openStore();
      await repo.loadDemoData();
      // Reachable from a ledger written by an older build: the entry form
      // refuses an empty name and `importAll` now rejects one, but a record
      // already on disk never went through either.
      await store.putCustomer(
        Customer(id: 'blank', name: '', createdAt: DateTime.now()),
      );
      await repo.reload();
    });
    tearDown(closeStore);

    testWidgets('is listed instead of crashing the page', (tester) async {
      await tester.pumpWidget(wrap(const CustomersPage()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.takeException(), isNull);
      // The avatar falls back to a placeholder rather than asking an empty
      // string for its first character. A blank name also sorts first, so the
      // row is the one at the top of the list.
      expect(find.text('؟'), findsOneWidget);
      // The rest of the ledger is still listed: one blank record does not take
      // the page down with it.
      expect(find.byType(Dismissible), findsWidgets);
    });
  });

  group('the sale form\'s outstanding-debt line', () {
    setUp(() async {
      await openStore();
      await repo.loadDemoData();
    });
    tearDown(closeStore);

    Finder saleAmount() => find.widgetWithText(TextField, 'Sale amount');
    Finder receivedNow() => find.widgetWithText(TextField, 'Received now');

    /// Scrolls the payment section into view. The hint lives directly under
    /// the "received now" field, so once that field is on screen the hint is
    /// built too; `skipOffstage: false` on the assertions below then makes
    /// them about content rather than about what the lazy list happened to
    /// build.
    Future<void> revealPayment(WidgetTester tester) async {
      await tester.scrollUntilVisible(
        receivedNow(),
        120,
        scrollable: formScrollable(),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('says nothing while there is no price', (tester) async {
      await tester.pumpWidget(
        wrap(SellSubscriptionPage(contact: repo.customers.first)),
      );
      await tester.pumpAndSettle();
      await revealPayment(tester);

      // 0 - 0 used to read as "paid in full" for a sale that did not exist yet.
      expect(find.text('Paid in full', skipOffstage: false), findsNothing);
      expect(
        find.textContaining('customer debt', skipOffstage: false),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('follows what is typed into both amounts', (tester) async {
      await tester.pumpWidget(
        wrap(SellSubscriptionPage(contact: repo.customers.first)),
      );
      await tester.pumpAndSettle();

      // The price field is near the top of the form, so set it before
      // scrolling away from it. Neither amount field rebuilds the page — that
      // is exactly the bug — so nothing but the new listener can move the
      // hint below.
      await tester.enterText(saleAmount(), '500000');
      await tester.pumpAndSettle();
      await revealPayment(tester);
      expect(
        find.textContaining(
          'customer debt: 500,000 Toman',
          skipOffstage: false,
        ),
        findsOneWidget,
      );

      await tester.enterText(receivedNow(), '200000');
      await tester.pumpAndSettle();
      expect(
        find.textContaining(
          'customer debt: 300,000 Toman',
          skipOffstage: false,
        ),
        findsOneWidget,
      );

      await tester.enterText(receivedNow(), '500000');
      await tester.pumpAndSettle();
      expect(find.text('Paid in full', skipOffstage: false), findsOneWidget);
      expect(
        find.textContaining('customer debt', skipOffstage: false),
        findsNothing,
      );

      // And an over-payment is still "paid in full", never a negative debt.
      await tester.enterText(receivedNow(), '600000');
      await tester.pumpAndSettle();
      expect(find.text('Paid in full', skipOffstage: false), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the SMS review sheet', () {
    setUp(() async {
      // Deliberately *not* demo data: `loadDemoData` writes subscription
      // receipts at `J.addDays(start, 1 + rnd.nextInt(12))` with no clamp to
      // today, so the newest entry in a demo ledger can be a future-dated
      // business receipt. The whole point of this test is which entry the
      // sheet would have copied its section from, so the ordering has to be
      // exact rather than random. An empty store still seeds its categories.
      await openStore();
      await repo.reload();
      // One contact, so the business side of the sheet is the populated one a
      // seller actually sees (its chip strip also offers "all contacts" and
      // "new contact" when there is nobody yet).
      await repo.addCustomer(name: 'Alex');
      // The situation the old guess got wrong: a business ledger whose most
      // recent entry happens to be personal (one tap on a quick button on the
      // landing tab).
      await repo.addTxn(
        repo.buildTxn(
          kind: TxnKind.income,
          amount: 250000,
          currency: 'IRT',
          date: J.addDays(DateTime.now(), -1),
          scope: TxnScope.business,
        ),
      );
      await repo.addTxn(
        repo.buildTxn(
          kind: TxnKind.expense,
          amount: 50000,
          currency: 'IRT',
          date: DateTime.now(),
          scope: TxnScope.personal,
        ),
      );
    });
    tearDown(closeStore);

    final sms = ParsedSms(
      message: SmsMessage(
        id: 'deposit-sms',
        address: 'BANK',
        body: 'واریز مبلغ 100,000 تومان',
        date: DateTime.now(),
      ),
      bankName: 'Test Bank',
      amount: 100000,
      direction: SmsDirection.deposit,
      confident: true,
    );

    testWidgets('opens on the business side, not on the newest entry\'s', (
      tester,
    ) async {
      // The precondition is synchronous, so it is safe to check it here.
      expect(repo.transactions.first.scope, TxnScope.personal);

      await tester.pumpWidget(wrap(SmsReviewSheet(sms: sms)));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<SegmentedButton<TxnScope>>(
              find.byType(SegmentedButton<TxnScope>),
            )
            .selected,
        {TxnScope.business},
      );

      // Still one tap from being recorded, as the review queue promises.
      final record = find.widgetWithText(FilledButton, 'Record transaction');
      expect(tester.widget<FilledButton>(record).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  });
}
