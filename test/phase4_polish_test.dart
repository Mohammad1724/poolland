import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/core/localization.dart';
import 'package:poolland/data/repository.dart';
import 'package:poolland/data/store.dart';
import 'package:poolland/ui/customers_page.dart';
import 'package:poolland/ui/home_shell.dart';
import 'package:poolland/ui/subscriptions_page.dart';
import 'package:poolland/ui/theme.dart';
import 'package:poolland/ui/transactions_page.dart';
import 'package:poolland/ui/widgets/widgets.dart';
import 'package:provider/provider.dart';

/// Cross-cutting polish tests: accessible text sizes, clearable search,
/// accurate filtered-empty states, and persistent actions for assistive tech.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late LocalStore store;
  late AppRepository repo;

  setUp(() async {
    AppLocalization.languageCode = 'en';
    tmp = await Directory.systemTemp.createTemp('poolland_phase4');
    store = await LocalStore.openAt(tmp.path);
    repo = AppRepository(store: store);
    await repo.loadDemoData();
  });

  tearDown(() async {
    await store.close();
    await tmp.delete(recursive: true);
  });

  Widget app(
    Widget home, {
    bool accessibleNavigation = false,
    bool disableAnimations = false,
  }) {
    return ChangeNotifierProvider<AppRepository>.value(
      value: repo,
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en'), Locale('fa')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            accessibleNavigation: accessibleNavigation,
            disableAnimations: disableAnimations,
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home: home,
      ),
    );
  }

  Future<void> settleShell(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 400)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  group('shared search field', () {
    testWidgets('offers a labeled clear action with a comfortable target', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final changes = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: SearchField(
                controller: controller,
                hint: 'Search name or phone...',
                onChanged: changes.add,
              ),
            ),
          ),
        ),
      );

      expect(find.byTooltip('Clear search'), findsNothing);
      await tester.enterText(find.byType(TextField), 'alex');
      await tester.pump();

      final clear = find.byTooltip('Clear search');
      expect(clear, findsOneWidget);
      expect(tester.getSize(clear).shortestSide, greaterThanOrEqualTo(48));

      await tester.tap(clear);
      await tester.pump();
      expect(controller.text, isEmpty);
      expect(changes.last, isEmpty);
      expect(find.byTooltip('Clear search'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('filtered empty states', () {
    testWidgets('customer search can be cleared without a false first-run state', (
      tester,
    ) async {
      await tester.pumpWidget(app(const Scaffold(body: CustomersPage())));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'no-such-customer-123');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('No items found'), findsOneWidget);
      expect(find.text('No customers yet'), findsNothing);

      await tester.tap(find.byTooltip('Clear search'));
      await tester.pumpAndSettle();
      expect(find.text('No items found'), findsNothing);
      expect(find.byType(Dismissible), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('subscription search results offer reset, not a new sale', (
      tester,
    ) async {
      await tester.pumpWidget(app(const Scaffold(body: SubscriptionsPage())));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'no-such-plan-123');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('No items found'), findsOneWidget);
      expect(find.text('Sell a subscription'), findsNothing);
      expect(find.text('Clear search and filters'), findsOneWidget);

      await tester.tap(find.text('Clear search and filters'));
      await tester.pumpAndSettle();
      expect(find.text('No items found'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('transaction search empty state can restore the list', (
      tester,
    ) async {
      await tester.pumpWidget(app(const Scaffold(body: TransactionsPage())));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'no-such-transaction-123');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('No items found'), findsOneWidget);
      expect(find.text('Clear search and filters'), findsOneWidget);

      await tester.tap(find.text('Clear search and filters'));
      await tester.pumpAndSettle();
      expect(find.text('No items found'), findsNothing);
      expect(find.byTooltip('Clear search'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('empty state remains usable with larger system text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(2),
          ),
          child: child ?? const SizedBox.shrink(),
        ),
        home: const Scaffold(
          body: EmptyState(
            icon: Icons.people_outline_rounded,
            title: 'No items found',
            text: 'Try a different search or filter.',
            actionLabel: 'Clear search and filters',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No items found'), findsOneWidget);
    expect(find.text('Clear search and filters'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced-motion preference disables shell motion', (tester) async {
    await tester.pumpWidget(app(const HomeShell(), disableAnimations: true));
    await settleShell(tester);

    final slide = tester.widget<AnimatedSlide>(find.byType(AnimatedSlide));
    expect(slide.duration, Duration.zero);
    expect(tester.takeException(), isNull);
  });

  testWidgets('assistive navigation keeps the quick action visible on scroll', (
    tester,
  ) async {
    await tester.pumpWidget(app(const HomeShell(), accessibleNavigation: true));
    await settleShell(tester);

    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -240));
    await tester.pumpAndSettle();

    final slide = tester.widget<AnimatedSlide>(find.byType(AnimatedSlide));
    expect(slide.offset, Offset.zero);
    expect(tester.takeException(), isNull);
  });
}
