import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:poolland/core/localization.dart';
import 'package:poolland/core/sms/sms_models.dart';
import 'package:poolland/data/models.dart';
import 'package:poolland/data/repository.dart';
import 'package:poolland/data/store.dart';
import 'package:poolland/ui/customer_detail_page.dart';
import 'package:poolland/ui/customers_page.dart';
import 'package:poolland/ui/dashboard_page.dart';
import 'package:poolland/ui/forms/contact_edit_page.dart';
import 'package:poolland/ui/forms/plan_edit_page.dart';
import 'package:poolland/ui/forms/sell_subscription_page.dart';
import 'package:poolland/ui/forms/transaction_edit_page.dart';
import 'package:poolland/ui/home_shell.dart';
import 'package:poolland/ui/onboarding.dart';
import 'package:poolland/ui/personal_page.dart';
import 'package:poolland/ui/reports_page.dart';
import 'package:poolland/ui/settings_page.dart';
import 'package:poolland/ui/sms_page.dart';
import 'package:poolland/ui/sms_rules_page.dart';
import 'package:poolland/ui/subscriptions_page.dart';
import 'package:poolland/ui/unrecognized_sms_page.dart';
import 'package:poolland/ui/theme.dart';
import 'package:poolland/ui/transactions_page.dart';
import 'package:poolland/ui/widgets/widgets.dart';

/// Smoke test: all pages should render without errors.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late LocalStore store;
  late AppRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('vpnledger_ui');
    store = await LocalStore.openAt(tmp.path);
    repo = AppRepository(store: store);
    await repo.loadDemoData();
  });

  tearDown(() async {
    await store.close();
    await tmp.delete(recursive: true);
  });

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

  Widget wrapShell() {
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
        home: const HomeShell(),
      ),
    );
  }

  Future<void> tapTab(WidgetTester tester, int index) async {
    final bar = find.byType(NavigationBar);
    final rect = tester.getRect(bar);
    await tester.tapAt(
      Offset(rect.left + rect.width * (index + 0.5) / 5, rect.center.dy),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('Dashboard renders with sample data', (tester) async {
    await tester.pumpWidget(wrap(DashboardPage(onNavigate: (_) {})));
    await tester.pumpAndSettle();

    expect(find.text('This month'), findsOneWidget);
    expect(find.text('Business receivables'), findsOneWidget);
    expect(find.text('Business cash balance'), findsOneWidget);
  });

  testWidgets('Personal-only dashboard hides business-only balances', (
    tester,
  ) async {
    repo.setScopeFilter(TxnScope.personal);
    await tester.pumpWidget(wrap(DashboardPage(onNavigate: (_) {})));
    await tester.pumpAndSettle();

    expect(find.text('Business receivables'), findsNothing);
    expect(find.text('Business payables'), findsNothing);
    expect(find.text('Business cash balance'), findsNothing);
    expect(find.text('Personal'), findsOneWidget);
  });

  testWidgets('Main shell navigates between tabs', (tester) async {
    await tester.pumpWidget(wrapShell());
    // Startup tasks (posting due recurring transactions) perform real I/O.
    // Widget tests must use runAsync to let them complete.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Personal')),
      findsOneWidget,
      reason: 'Personal finance should be the first screen for daily use',
    );

    const tabs = <(int, String)>[
      (0, 'Personal'),
      (2, 'Customers'),
      (3, 'Subscriptions'),
      (4, 'Transactions'),
      (1, 'Dashboard'),
    ];
    for (final (index, tab) in tabs) {
      await tapTab(tester, index);
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text(tab)),
        findsOneWidget,
        reason: 'Tab $tab was not selected',
      );
      expect(
        tester.takeException(),
        isNull,
        reason: 'Tab $tab threw an exception',
      );
    }
    await tester.tap(find.byTooltip('Reports'));
    await tester.pumpAndSettle();
    expect(find.text('Reports'), findsOneWidget);
    expect(find.byType(ReportsPage), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
  });

  testWidgets('Personal quick add opens a personal expense form', (
    tester,
  ) async {
    await tester.pumpWidget(wrapShell());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(
      find.widgetWithText(FloatingActionButton, 'Add personal entry'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personal expense').last);
    await tester.pumpAndSettle();

    final scopeSelector = tester.widget<SegmentedButton<TxnScope>>(
      find.byType(SegmentedButton<TxnScope>),
    );
    expect(scopeSelector.selected, {TxnScope.personal});
    expect(find.byType(FormActionBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Wide layout switches to a navigation rail', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrapShell());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('System back returns from a tab to the personal home', (
    tester,
  ) async {
    await tester.pumpWidget(wrapShell());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tapTab(tester, 3);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Subscriptions'),
      ),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('Personal')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('System back closes a pushed page before leaving its tab', (
    tester,
  ) async {
    await tester.pumpWidget(wrapShell());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tapTab(tester, 2);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Customers'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Customer list and details render', (tester) async {
    await tester.pumpWidget(wrap(const CustomersPage()));
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsWidgets);
    expect(tester.takeException(), isNull);

    final customer = repo.customers.first;
    await tester.pumpWidget(wrap(CustomerDetailPage(customer: customer)));
    await tester.pumpAndSettle();

    expect(find.text(customer.name), findsWidgets);
    expect(
      find.text('Subscriptions (${repo.subsOfCustomer(customer.id).length})'),
      findsOneWidget,
    );
  });

  testWidgets('Subscription, transaction, and report pages render', (
    tester,
  ) async {
    for (final page in [
      const PersonalPage(),
      const SubscriptionsPage(),
      const TransactionsPage(),
      const ReportsPage(),
    ]) {
      await tester.pumpWidget(wrap(page));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.takeException(),
        isNull,
        reason: '${page.runtimeType} threw an exception',
      );
    }
  });

  testWidgets('Report scope is independent of the global transaction filter', (
    tester,
  ) async {
    repo.setScopeFilter(TxnScope.business);
    await tester.pumpWidget(wrap(const ReportsPage()));
    await tester.pump();

    final reportScopeChips = find.descendant(
      of: find.byType(ReportsPage),
      matching: find.byType(ChoiceChip),
    );
    expect(reportScopeChips, findsWidgets);
    await tester.tap(reportScopeChips.first);
    await tester.pump();

    expect(repo.scopeFilter, TxnScope.business);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings and subpages render', (tester) async {
    for (final page in [
      const SettingsPage(),
      const PlansPage(),
      const CategoriesPage(),
      const RatesPage(),
      const SmsRulesPage(),
      const SmsRuleEditPage(),
      const UnrecognizedSmsPage(),
    ]) {
      await tester.pumpWidget(wrap(page));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.takeException(),
        isNull,
        reason: '${page.runtimeType} threw an exception',
      );
    }
  });

  testWidgets('Subscription sale form renders', (tester) async {
    await tester.pumpWidget(
      wrap(SellSubscriptionPage(contact: repo.customers.first)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Service name'), findsOneWidget);
    expect(find.text('Duration:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Transaction and new-customer forms render', (tester) async {
    await tester.pumpWidget(
      wrap(const TransactionEditPage(initialKind: TxnKind.expense)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Category'), findsOneWidget);
    expect(find.byType(FormActionBar), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(wrap(const ContactEditPage()));
    await tester.pumpAndSettle();
    expect(find.text('Opening balance'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bank SMS page renders', (tester) async {
    await tester.pumpWidget(wrap(const SmsPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('SMS review requires a scope before recording', (tester) async {
    final sms = ParsedSms(
      message: SmsMessage(
        id: 'review-sms',
        address: 'BANK',
        body: 'واریز مبلغ 100,000 تومان',
        date: DateTime.now(),
      ),
      bankName: 'Test Bank',
      amount: 100000,
      direction: SmsDirection.deposit,
      confident: true,
    );

    await tester.pumpWidget(wrap(SmsReviewSheet(sms: sms)));
    await tester.pumpAndSettle();

    expect(
      find.text('Choose where this transaction belongs before recording'),
      findsOneWidget,
    );
    expect(find.text('Amount'), findsNothing);
    final buttonFinder = find.widgetWithText(
      FilledButton,
      'Record transaction',
    );
    expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNull);

    await tester.tap(find.text('VPN business'));
    await tester.pumpAndSettle();

    expect(find.text('Amount'), findsOneWidget);
    expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNotNull);
  });

  testWidgets('Onboarding page renders', (tester) async {
    await tester.pumpWidget(wrap(const OnboardingPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Poolland Ledger'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
