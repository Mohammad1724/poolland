import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/core/localization.dart';
import 'package:poolland/data/models.dart';
import 'package:poolland/data/repository.dart';
import 'package:poolland/data/store.dart';
import 'package:poolland/ui/customers_page.dart';
import 'package:poolland/ui/forms/sell_subscription_page.dart';
import 'package:poolland/ui/forms/transaction_edit_page.dart';
import 'package:poolland/ui/home_shell.dart';
import 'package:poolland/ui/theme.dart';
import 'package:poolland/ui/transactions_page.dart';
import 'package:poolland/ui/widgets/widgets.dart';
import 'package:provider/provider.dart';

/// Phase 3 tests: the gestures that save taps — swiping a row, repeating the
/// last sale, and tapping the tab that is already open — plus the touch target
/// sizes that make them comfortable to use.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late LocalStore store;
  late AppRepository repo;

  // The newest subscription, so "repeat last sale" has a known answer.
  late Customer lastSaleCustomer;
  late Plan lastSalePlan;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('poolland_phase3');
    store = await LocalStore.openAt(tmp.path);
    repo = AppRepository(store: store);
    await repo.loadDemoData();

    // A probe entry, so a swipe can be aimed at a row with a known note and
    // amount instead of guessing what the sample data put on screen.
    await repo.addTxn(
      repo.buildTxn(
        kind: TxnKind.expense,
        amount: 4242,
        currency: repo.settings.baseCurrency,
        date: DateTime.now(),
        categoryId: repo.defaultCategoryId(TxnKind.expense),
        note: 'Swipe probe',
      ),
    );

    // Sold last, with a timestamp clearly after the sample sales.
    lastSaleCustomer = repo.customers.first;
    lastSalePlan = repo.plans.first;
    final now = DateTime.now();
    await repo.saveSubscription(
      Subscription(
        id: LocalStore.newId(),
        customerId: lastSaleCustomer.id,
        planId: lastSalePlan.id,
        planName: lastSalePlan.name,
        startDate: now,
        endDate: now.add(const Duration(days: 30)),
        amount: lastSalePlan.price,
        currency: lastSalePlan.currency,
        createdAt: now.add(const Duration(days: 1)),
      ),
    );
  });

  tearDown(() async {
    await store.close();
    await tmp.delete(recursive: true);
  });

  Widget app(Widget home) {
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
        home: home,
      ),
    );
  }

  Widget wrap(Widget child) => app(Scaffold(body: child));

  Widget wrapShell() => app(const HomeShell());

  /// Startup tasks (posting due recurring transactions) perform real I/O, so
  /// the shell needs a moment outside the test's fake clock.
  Future<void> settleShell(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> tapTab(WidgetTester tester, int index) async {
    final rect = tester.getRect(find.byType(NavigationBar));
    await tester.tapAt(
      Offset(rect.left + rect.width * (index + 0.5) / 5, rect.center.dy),
    );
    await tester.pumpAndSettle();
  }

  /// Which way the payment sheet opened: true is money coming in, false is
  /// money going out. Both labels are always on screen, so the selection is
  /// what says whether the swipe picked the right one.
  bool sheetIsReceive(WidgetTester tester) => tester
      .widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>))
      .selected
      .single;

  /// Closes the modal sheet that a swipe opened, the way backing out of it
  /// does. Popping the route is used instead of tapping above the sheet so the
  /// test does not depend on where the sheet happens to end on screen.
  Future<void> closeSheet(WidgetTester tester) async {
    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
  }

  group('swiping a customer row', () {
    testWidgets('right opens the receipt sheet, left opens the payment sheet', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const CustomersPage()));
      await tester.pumpAndSettle();

      final rows = find.byType(Dismissible).evaluate().length;
      expect(rows, greaterThan(0), reason: 'the list must have swipable rows');

      // Right: money coming in.
      await tester.drag(find.byType(Dismissible).first, const Offset(260, 0));
      await tester.pumpAndSettle();
      expect(find.text('Receive from customer'), findsOneWidget);
      expect(sheetIsReceive(tester), isTrue);

      await closeSheet(tester);
      expect(
        find.text('Receive from customer'),
        findsNothing,
        reason: 'tapping outside the sheet must close it',
      );

      // Left: money going out.
      await tester.drag(find.byType(Dismissible).first, const Offset(-260, 0));
      await tester.pumpAndSettle();
      expect(find.text('Pay customer'), findsOneWidget);
      expect(sheetIsReceive(tester), isFalse);

      await closeSheet(tester);

      // A swipe is a shortcut, never a delete: the row is still there, and so
      // is every other row.
      expect(find.byType(Dismissible).evaluate().length, rows);
      expect(tester.takeException(), isNull);
    });
  });

  group('swiping a transaction row', () {
    testWidgets('right opens it for editing', (tester) async {
      await tester.pumpWidget(wrap(const TransactionsPage()));
      await tester.pumpAndSettle();

      final probe = find.text('Swipe probe');
      expect(probe, findsOneWidget);
      await tester.ensureVisible(probe);
      await tester.pumpAndSettle();

      await tester.drag(probe, const Offset(260, 0));
      await tester.pumpAndSettle();

      expect(find.text('Edit transaction'), findsOneWidget);
      // Deleting is only offered while really editing the original.
      expect(find.byTooltip('Delete'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('left opens a copy pre-filled with the same entry', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const TransactionsPage()));
      await tester.pumpAndSettle();

      final probe = find.text('Swipe probe');
      await tester.ensureVisible(probe);
      await tester.pumpAndSettle();

      await tester.drag(probe, const Offset(-260, 0));
      await tester.pumpAndSettle();

      expect(find.text('Duplicate transaction'), findsOneWidget);
      // The original is not being touched, so it cannot be deleted from here.
      expect(find.byTooltip('Delete'), findsNothing);

      // The amount travelled across, so saving the copy is one tap away.
      final amount = tester.widget<TextField>(
        find
            .descendant(
              of: find.byType(AmountField),
              matching: find.byType(TextField),
            )
            .first,
      );
      expect(
        amount.controller!.text.replaceAll(RegExp(r'[^0-9]'), ''),
        startsWith('4242'),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('repeat last sale', () {
    testWidgets('fills the sale form with the previous customer and plan', (
      tester,
    ) async {
      await tester.pumpWidget(wrapShell());
      await settleShell(tester);

      // The shortcut lives on the subscriptions tab, where sales happen.
      await tapTab(tester, 3);
      final repeat = find.byTooltip('Repeat last sale');
      expect(repeat, findsOneWidget);

      await tester.tap(repeat);
      await tester.pumpAndSettle();

      expect(find.text('Sell a subscription'), findsOneWidget);
      Finder onForm(Finder finder) => find.descendant(
        of: find.byType(SellSubscriptionPage),
        matching: finder,
      );
      expect(onForm(find.text(lastSaleCustomer.name)), findsWidgets);
      expect(onForm(find.text(lastSalePlan.name)), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });

  group('tapping the tab that is already open', () {
    testWidgets('scrolls that page back to the top', (tester) async {
      await tester.pumpWidget(wrapShell());
      await settleShell(tester);

      final top = find.textContaining('Personal summary');
      expect(top, findsOneWidget);

      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(
        top,
        findsNothing,
        reason: 'the list should really be scrolled away from the top',
      );

      await tapTab(tester, 0);
      expect(top, findsOneWidget, reason: 'tapping the open tab means "top"');
      expect(tester.takeException(), isNull);
    });
  });

  group('touch targets', () {
    testWidgets('the scope selector in the entry form is at least 44dp tall', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const TransactionEditPage()));
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(SegmentedButton<TxnScope>));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the duration stepper on the sale form is 44dp square', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const SellSubscriptionPage()));
      await tester.pumpAndSettle();

      // The stepper sits further down the form than the viewport reaches, so
      // bring it into view before measuring it.
      await tester.scrollUntilVisible(
        find.byIcon(Icons.remove_rounded),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      final minus = tester.getSize(
        find
            .ancestor(
              of: find.byIcon(Icons.remove_rounded),
              matching: find.byType(IconButton),
            )
            .first,
      );
      expect(minus.height, greaterThanOrEqualTo(44));
      expect(minus.width, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
    });
  });
}
