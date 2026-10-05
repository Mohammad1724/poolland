import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
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
import 'package:poolland/ui/subscriptions_page.dart';
import 'package:poolland/ui/theme.dart';
import 'package:poolland/ui/transactions_page.dart';

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

  Widget wrap(Widget child) => ChangeNotifierProvider<AppRepository>.value(
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
          builder: (context, c) =>
              Directionality(textDirection: TextDirection.ltr, child: c ?? const SizedBox()),
          home: Scaffold(body: child),
        ),
      );

  testWidgets('Dashboard renders with sample data', (tester) async {
    await tester.pumpWidget(wrap(DashboardPage(onNavigate: (_) {})));
    await tester.pumpAndSettle();

    expect(find.text('This month'), findsOneWidget);
    expect(find.text('Receivables'), findsOneWidget);
    expect(find.text('Cash balance'), findsOneWidget);
  });

  testWidgets('Main shell navigates between tabs', (tester) async {
    await tester.pumpWidget(wrap(const HomeShell()));
    // Startup tasks (posting due recurring transactions) perform real I/O.
    // Widget tests must use runAsync to let them complete.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    for (final tab in [
      'Personal',
      'Customers',
      'Subscriptions',
      'Transactions',
      'Reports',
      'Dashboard'
    ]) {
      await tester.tap(find.text(tab).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: 'Tab $tab threw an exception');
    }
  });

  testWidgets('System back returns from a tab to the dashboard', (tester) async {
    await tester.pumpWidget(wrap(const HomeShell()));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Subscriptions').last);
    await tester.pumpAndSettle();
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
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Dashboard'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('System back closes a pushed page before leaving its tab',
      (tester) async {
    await tester.pumpWidget(wrap(const HomeShell()));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('Customers').last);
    await tester.pumpAndSettle();
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
    expect(find.text('Subscriptions (${repo.subsOfCustomer(customer.id).length})'),
        findsOneWidget);
  });

  testWidgets('Subscription, transaction, and report pages render', (tester) async {
    for (final page in [
      const PersonalPage(),
      const SubscriptionsPage(),
      const TransactionsPage(),
      const ReportsPage()
    ]) {
      await tester.pumpWidget(wrap(page));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: '${page.runtimeType} threw an exception');
    }
  });

  testWidgets('Settings and subpages render', (tester) async {
    for (final page in [
      const SettingsPage(),
      const PlansPage(),
      const CategoriesPage(),
      const RatesPage(),
    ]) {
      await tester.pumpWidget(wrap(page));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: '${page.runtimeType} threw an exception');
    }
  });

  testWidgets('Subscription sale form renders', (tester) async {
    await tester.pumpWidget(wrap(SellSubscriptionPage(contact: repo.customers.first)));
    await tester.pumpAndSettle();
    expect(find.text('Service name'), findsOneWidget);
    expect(find.text('Duration:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Transaction and new-customer forms render', (tester) async {
    await tester.pumpWidget(wrap(const TransactionEditPage(initialKind: TxnKind.expense)));
    await tester.pumpAndSettle();
    expect(find.text('Category'), findsOneWidget);
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

  testWidgets('Onboarding page renders', (tester) async {
    await tester.pumpWidget(wrap(const OnboardingPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Poolland Ledger'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
