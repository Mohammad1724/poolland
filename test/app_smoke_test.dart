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
import 'package:poolland/ui/motion_kit.dart';
import 'package:poolland/ui/onboarding.dart';
import 'package:poolland/ui/permissions_intro_page.dart';
import 'package:poolland/ui/personal_page.dart';
import 'package:poolland/ui/reports_page.dart';
import 'package:poolland/ui/settings_page.dart';
import 'package:poolland/ui/sms_page.dart';
import 'package:poolland/ui/sms_rules_page.dart';
import 'package:poolland/ui/forms/sms_review_sheet.dart';
import 'package:poolland/ui/subscriptions_page.dart';
import 'package:poolland/ui/theme.dart';
import 'package:poolland/ui/transactions_page.dart';
import 'package:poolland/ui/widgets/quick_buttons.dart';
import 'package:poolland/ui/widgets/widgets.dart';
import 'package:poolland/ui/widgets/ledger_nav_bar.dart';

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
    final bar = find.byType(LedgerNavBar);
    final rect = tester.getRect(bar);
    await tester.tapAt(
      Offset(rect.left + rect.width * (index + 0.5) / 5, rect.center.dy),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('Dashboard renders with sample data', (tester) async {
    await tester.pumpWidget(
      wrap(
        DashboardPage(
          onNavigate: (_) {},
          initialScope: TxnScope.business,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('This month'), findsOneWidget);
    expect(find.text('Total expense'), findsOneWidget);
    expect(find.text('Total income'), findsOneWidget);
    expect(find.text('Business receivables'), findsOneWidget);
    expect(find.text('Business cash balance'), findsOneWidget);
  });

  testWidgets('Personal-only dashboard hides business-only balances', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(DashboardPage(onNavigate: (_) {})));
    await tester.pumpAndSettle();

    expect(find.text('Business receivables'), findsNothing);
    expect(find.text('Business payables'), findsNothing);
    expect(find.text('Business cash balance'), findsNothing);
    expect(find.text('Total expense'), findsOneWidget);
    expect(find.text('Total income'), findsOneWidget);
    expect(find.text('Personal'), findsWidgets);
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
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Dashboard'),
      ),
      findsOneWidget,
      reason: 'Unified Dashboard should be the first screen for daily use',
    );

    const tabs = <(int, String)>[
      (0, 'Dashboard'),
      (1, 'Customers'),
      (2, 'Subscriptions'),
      (3, 'Transactions'),
      (4, 'Reports'),
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
    expect(find.byType(ReportsPage), findsOneWidget);
    expect(find.byTooltip('Reports'), findsNothing);
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

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Personal expense').last);
    await tester.pumpAndSettle();

    final scopeSelector = tester.widget<ScopeMagneticBar>(
      find.byType(ScopeMagneticBar),
    );
    expect(scopeSelector.personalProgress, 1.0);
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
    expect(find.byType(LedgerNavBar), findsNothing);
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

    await tapTab(tester, 2);
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

  testWidgets('System back closes a pushed page before leaving its tab', (
    tester,
  ) async {
    await tester.pumpWidget(wrapShell());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tapTab(tester, 1);
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

  testWidgets(
    'ReportsPage supports 3 tabs, date ranges, category breakdown, and sources report',
    (tester) async {
      await tester.pumpWidget(wrap(const ReportsPage()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Statistics'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Sources & balances'), findsOneWidget);
      expect(find.text('Income and expense report'), findsOneWidget);
      expect(find.text('Income and expense chart'), findsOneWidget);

      // Switch between Daily, Weekly, and All ranges.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Daily'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Weekly'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      await tester.tap(find.widgetWithText(ChoiceChip, 'All').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);

      // Switch to Categories tab and verify category breakdown & summary.
      await tester.tap(find.text('Categories'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Category income and expense report'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Switch to Sources & balances tab and verify balances & sources report.
      await tester.tap(find.text('Sources & balances'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Balances report'), findsOneWidget);
      expect(find.text('Bank and payment sources'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Settings and subpages render', (tester) async {
    for (final page in [
      const SettingsPage(),
      const PlansPage(),
      const CategoriesPage(),
      const RatesPage(),
      const ArchivedCustomersPage(),
      const BudgetsManagePage(),
      const RecurringManagePage(),
      const SmsRulesPage(),
      const SmsRuleEditPage(),
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
    expect(find.text('To account'), findsOneWidget);
    expect(find.byType(FormActionBar), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(wrap(const ContactEditPage()));
    await tester.pumpAndSettle();
    expect(find.text('Opening balance'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the entry form refuses to record without an amount', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const TransactionEditPage(initialKind: TxnKind.expense)),
    );
    await tester.pumpAndSettle();

    Finder button() => find.descendant(
      of: find.byType(FormActionBar),
      matching: find.byType(FilledButton),
    );

    // An empty amount used to leave the action live and silently refusing:
    // validate() failed on a field that is scrolled out of view by then, so
    // the tap looked swallowed. Now the button says so.
    expect(tester.widget<FilledButton>(button()).onPressed, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '1500');
    await tester.pump();
    expect(tester.widget<FilledButton>(button()).onPressed, isNotNull);

    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '');
    await tester.pump();
    expect(tester.widget<FilledButton>(button()).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Switching the direction swaps the category to the new kind', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const TransactionEditPage(
          initialKind: TxnKind.income,
          // Autofocus would scroll the lazy form past the kind chips on the
          // very first frame and dispose them before the test can tap one.
          autofocusAmount: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Flip income -> expense while the kind chips are on screen at the top
    // of the form.
    await tester.tap(find.text('Expense').last);
    await tester.pumpAndSettle();

    final expected = repo.categoryById(
      repo.defaultCategoryId(TxnKind.expense, scope: TxnScope.business),
    );
    expect(expected, isNotNull);
    expect(find.text('To account'), findsOneWidget);
    // The category row now carries the re-derived default for the new kind.
    expect(find.text(expected!.name), findsOneWidget);
    expect(expected.kind, TxnKind.expense);
    expect(expected.scope, TxnScope.business);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Quick amount sheet returns the picked day with the amount', (
    tester,
  ) async {
    QuickAmountResult? result;
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (c) => FilledButton(
            onPressed: () async => result =
                await showLedgerSheet<QuickAmountResult>(
                  c,
                  builder: (_) => const QuickAmountSheet(
                    quick: QuickExpense(id: 'q1', label: 'Snack'),
                  ),
                ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Amount'),
      '2500',
    );
    await tester.pump();
    // Record only lives once there is an amount to record; an empty sheet used
    // to sit there ignoring the tap with no explanation.
    expect(
      tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Record'),
      ).onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.amount, 2500);
    // The sheet offers a date picker; the chosen day must travel back with
    // the amount so recordQuickExpense can post entries that are not today.
    final now = DateTime.now();
    expect(result!.date.year, now.year);
    expect(result!.date.month, now.month);
    expect(result!.date.day, now.day);
  });

  testWidgets('Permissions intro renders', (tester) async {
    await tester.pumpWidget(wrap(const PermissionsIntroPage()));
    await tester.pumpAndSettle();
    expect(find.text('Permissions'), findsOneWidget);
    expect(find.text('Skip for now'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Bank SMS page renders', (tester) async {
    await tester.pumpWidget(wrap(const SmsPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('SMS notification opens the matching approval sheet', (
    tester,
  ) async {
    final message = SmsMessage(
      id: 'arrival-sms',
      address: 'BANKMELAT',
      body: 'بانک ملت\nواریز مبلغ 100,000 ریال',
      date: DateTime(2026, 10, 17, 12),
    );
    repo.importInboxSms([message]);
    final reviewKey = repo.smsSuggestions.single.key;
    final initialTransactionCount = repo.transactions.length;

    await tester.pumpWidget(wrap(SmsPage(openReviewKey: reviewKey)));
    await tester.pumpAndSettle();

    expect(find.text('Record this SMS transaction'), findsOneWidget);
    expect(find.text('Record transaction'), findsOneWidget);
    expect(repo.transactions.length, initialTransactionCount);
    expect(tester.takeException(), isNull);

    // Exercise the real approval route rather than a generic test sheet. The
    // visible pill is only 4 px tall, so start the swipe on its center as a
    // user would. A short deliberate pull must close without recording.
    final handle = find.descendant(
      of: find.byType(SmsReviewSheet),
      matching: find.byType(SheetHandle),
    );
    await tester.dragFrom(tester.getCenter(handle), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(find.text('Record this SMS transaction'), findsNothing);
    expect(repo.transactions.length, initialTransactionCount);
  });

  testWidgets('SMS review sheet closes when pulled down from its content', (
    tester,
  ) async {
    final sms = ParsedSms(
      message: SmsMessage(
        id: 'review-dismiss-sms',
        address: 'BANK',
        body: 'واریز مبلغ 100,000 ریال',
        date: DateTime.now(),
      ),
      bankName: 'Test Bank',
      amount: 100000,
      direction: SmsDirection.deposit,
      confident: true,
    );
    final initialTransactionCount = repo.transactions.length;

    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => FilledButton(
            onPressed: () => showLedgerSheet<void>(
              context,
              builder: (_) => SmsReviewSheet(sms: sms),
            ),
            child: const Text('Open SMS review'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open SMS review'));
    await tester.pumpAndSettle();
    expect(find.text('Record this SMS transaction'), findsOneWidget);

    final sheet = tester.getRect(find.byType(SmsReviewSheet));
    await tester.dragFrom(
      Offset(sheet.center.dx, sheet.top + 82),
      const Offset(0, 140),
    );
    await tester.pumpAndSettle();
    expect(find.text('Record this SMS transaction'), findsNothing);
    expect(repo.transactions.length, initialTransactionCount);
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

    // New contract: the sheet opens ready to save — the section is the
    // business side (a visible, fixed default rather than a guess taken from
    // whichever entry happens to be newest), kind and category follow it, and
    // frequent categories / regular contacts are offered as one-tap chips.
    final buttonFinder = find.widgetWithText(
      FilledButton,
      'Record transaction',
    );
    expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNotNull);
    expect(find.text('Amount'), findsOneWidget);
    // The redesigned sheet uses _ScopeChip instead of SegmentedButton.
    expect(find.text('Business'), findsOneWidget);
    expect(find.text('Personal'), findsOneWidget);

    // It opens on the business side, where regular contacts are shown
    // as a card. The default is fixed, not derived from the newest entry,
    // so the sheet cannot open a bank deposit on the personal side.
    expect(find.byType(ContactBalanceCard), findsNothing);

    // Switching the section still re-derives kind and category.
    await tester.tap(find.text('Personal'));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNotNull);

    // And switching back does not lose the one-tap contacts.
    await tester.tap(find.text('Business'));
    await tester.pumpAndSettle();
    expect(find.byType(ContactBalanceCard), findsNothing);
    expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNotNull);
  });

  testWidgets(
    'SMS review supports horizontal scope swipe, To/From account picker, and subcategory shortcuts',
    (tester) async {
      final withdrawSms = ParsedSms(
        message: SmsMessage(
          id: 'review-withdraw-sms',
          address: 'BANK',
          body: 'برداشت مبلغ 250,000 تومان',
          date: DateTime.now(),
        ),
        bankName: 'Test Bank',
        amount: 250000,
        direction: SmsDirection.withdraw,
        confident: true,
      );

      await tester.pumpWidget(wrap(SmsReviewSheet(sms: withdrawSms)));
      await tester.pumpAndSettle();

      // Opens on Personal scope (first tab) with "To account" («به حساب») button for expense.
      expect(find.text('To account'), findsOneWidget);
      expect(find.text('Contact (optional)'), findsNothing);
      final personalHeight = tester.getSize(find.byType(SmsReviewSheet)).height;

      // A short drag (~1/5 of the sheet) springs back without switching scopes.
      await tester.drag(find.byType(SmsReviewSheet), const Offset(-80, 0));
      await tester.pumpAndSettle();
      expect(find.text('Contact (optional)'), findsNothing);

      // Horizontal swipe past the magnetic threshold switches from Personal to
      // Business scope while keeping the sheet height locked.
      await tester.drag(find.byType(SmsReviewSheet), const Offset(-260, 0));
      await tester.pumpAndSettle();
      expect(find.text('Contact (optional)'), findsOneWidget);
      final businessHeight = tester.getSize(find.byType(SmsReviewSheet)).height;
      expect(businessHeight, closeTo(personalHeight, 1.0));

      // Swipe back to Personal scope.
      await tester.drag(find.byType(SmsReviewSheet), const Offset(260, 0));
      await tester.pumpAndSettle();
      expect(find.text('Contact (optional)'), findsNothing);

      // In Personal expense scope, the seeded "Fuel" («بنزین») shortcut chip
      // is shown directly on the main sheet.
      expect(find.text('Fuel'), findsOneWidget);
      await tester.tap(find.text('Fuel'));
      await tester.pumpAndSettle();

      // Selecting the "Fuel" shortcut updates the "To account" button to
      // show "Transport and fuel › Fuel".
      expect(find.text('Transport and fuel › Fuel'), findsOneWidget);

      // Inline category & subcategory search finds "Car maintenance" directly on the sheet.
      await tester.enterText(
        find.byKey(const ValueKey('inline_category_search_personal_expense')),
        'maintenance',
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Transport and fuel › Car maintenance'),
        findsOneWidget,
      );
      await tester.tap(find.text('Transport and fuel › Car maintenance'));
      await tester.pumpAndSettle();

      // Tapping "To account" opens the hierarchical category -> subcategory sheet.
      await tester.tap(find.text('To account'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Tap a category to view its subcategories or pin shortcuts',
        ),
        findsOneWidget,
      );
      expect(find.text('Taxi and ride-share'), findsOneWidget);

      // Selecting another subcategory updates the main sheet selection.
      await tester.tap(find.text('Taxi and ride-share'));
      await tester.pumpAndSettle();
      expect(
        find.text('Transport and fuel › Taxi and ride-share'),
        findsOneWidget,
      );

      // Tapping "Income" («درآمد») in the top header switches the sheet from
      // Expense ("To account") to Income ("From account").
      await tester.tap(find.text('Income'));
      await tester.pumpAndSettle();
      expect(find.text('From account'), findsOneWidget);
      expect(find.text('To account'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'SMS review auto-settles debtor contact balance and auto-renews settled contact subscription',
    (tester) async {
      // 1. Debtor customer: selecting them on a deposit SMS auto-switches to
      // Receive («دریافت بدهی») and settles their balance.
      final now = DateTime.now();
      final debtor = await repo.addCustomer(name: 'Debtor Customer');
      await repo.sellSubscription(
        customer: debtor,
        title: '1 Month Pro',
        price: 300000,
        currencyCode: 'IRT',
        start: now,
        end: now.add(const Duration(days: 30)),
        received: 0,
      );
      expect(repo.balanceOf(debtor), 300000);

      final depositSms1 = ParsedSms(
        message: SmsMessage(
          id: 'debtor-deposit-sms',
          address: 'BANK',
          body: 'واریز مبلغ 300,000 تومان',
          date: DateTime.now(),
        ),
        bankName: 'Test Bank',
        amount: 300000,
        direction: SmsDirection.deposit,
        confident: true,
      );

      await tester.pumpWidget(
        wrap(SmsReviewSheet(sms: depositSms1, initialCustomer: debtor)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Settling contact previous debt'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Record transaction'));
      await tester.pumpAndSettle();

      expect(repo.balanceOf(repo.customerById(debtor.id)!), 0);

      // 2. Settled customer with an existing subscription: selecting them on a
      // deposit SMS auto-selects Renew subscription and renews their service.
      final subCountBefore = repo.subsOfCustomer(debtor.id).length;
      final depositSms2 = ParsedSms(
        message: SmsMessage(
          id: 'renew-deposit-sms',
          address: 'BANK',
          body: 'واریز مبلغ 300,000 تومان',
          date: DateTime.now(),
        ),
        bankName: 'Test Bank',
        amount: 300000,
        direction: SmsDirection.deposit,
        confident: true,
      );

      await tester.pumpWidget(
        wrap(
          SmsReviewSheet(
            sms: depositSms2,
            initialCustomer: repo.customerById(debtor.id),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Renew: 1 Month Pro'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Record transaction'));
      await tester.pumpAndSettle();

      expect(repo.subsOfCustomer(debtor.id).length, subCountBefore + 1);
      expect(repo.balanceOf(repo.customerById(debtor.id)!), 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Onboarding page renders', (tester) async {
    await tester.pumpWidget(wrap(const OnboardingPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Poolland Ledger'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
