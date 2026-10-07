import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/core/localization.dart';
import 'package:poolland/data/repository.dart';
import 'package:poolland/data/store.dart';
import 'package:poolland/ui/customers_page.dart';
import 'package:poolland/ui/home_shell.dart';
import 'package:poolland/ui/personal_page.dart';
import 'package:poolland/ui/subscriptions_page.dart';
import 'package:poolland/ui/theme.dart';
import 'package:poolland/ui/widgets/widgets.dart';
import 'package:provider/provider.dart';

/// Phase 2 UX tests: collapsible filters, filter pills, collapsible cards, and
/// the floating action button that hides while scrolling down.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late LocalStore store;
  late AppRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('poolland_phase2');
    store = await LocalStore.openAt(tmp.path);
    repo = AppRepository(store: store);
    await repo.loadDemoData();
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

  group('CollapsibleCard', () {
    testWidgets('keeps the header and summary visible while collapsed', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(
          ListView(
            children: [
              CollapsibleCard(
                title: 'Last 6 months',
                summary: const Text('123'),
                child: const SizedBox(height: 100, child: Text('chart body')),
              ),
            ],
          ),
        ),
      );

      // Collapsed by default: the key figure is visible, the body is not.
      expect(find.text('Last 6 months'), findsOneWidget);
      expect(find.text('123'), findsOneWidget);
      expect(find.text('chart body'), findsNothing);

      await tester.tap(find.text('Last 6 months'));
      await tester.pumpAndSettle();
      expect(find.text('chart body'), findsOneWidget);

      await tester.tap(find.text('Last 6 months'));
      await tester.pumpAndSettle();
      expect(find.text('chart body'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('can start expanded', (tester) async {
      await tester.pumpWidget(
        wrap(
          ListView(
            children: [
              CollapsibleCard(
                title: 'Trend',
                initiallyExpanded: true,
                child: const SizedBox(height: 50, child: Text('visible body')),
              ),
            ],
          ),
        ),
      );

      expect(find.text('visible body'), findsOneWidget);
    });
  });

  group('customers page filters', () {
    testWidgets('chips are tucked behind the filter button', (tester) async {
      await tester.pumpWidget(wrap(const CustomersPage()));
      await tester.pumpAndSettle();

      // Collapsed: search field plus the filter button, no chips.
      expect(find.byType(FilterToggleButton), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);

      await tester.tap(find.byType(FilterToggleButton));
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNWidgets(3));

      // Picking a filter shows a removable pill.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Debtors'));
      await tester.pumpAndSettle();
      expect(find.byType(FilterPill), findsOneWidget);

      // Tapping the pill clears the filter again.
      await tester.tap(find.byType(FilterPill));
      await tester.pumpAndSettle();
      expect(find.byType(FilterPill), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('status dots replace the Active/Expired chips', (tester) async {
      // Demo data sells subscriptions, so list rows carry a status dot.
      expect(repo.subscriptions, isNotEmpty);

      await tester.pumpWidget(wrap(const CustomersPage()));
      await tester.pumpAndSettle();

      expect(find.byType(StatusDot), findsWidgets);
      // The old chips are gone; their labels only remain for accessibility.
      expect(find.text('Active'), findsNothing);
      expect(find.text('Expired'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('subscriptions page filters', () {
    testWidgets('filter chips open behind the button and show a pill', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const SubscriptionsPage()));
      await tester.pumpAndSettle();

      expect(find.byType(FilterToggleButton), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);

      await tester.tap(find.byType(FilterToggleButton));
      await tester.pumpAndSettle();
      expect(find.byType(ChoiceChip), findsNWidgets(4));

      // Chips carry their counts ("Expired (2)"), so match on the chip that
      // contains the word rather than on an exact label.
      final expiredChip = find.ancestor(
        of: find.textContaining('Expired'),
        matching: find.byType(ChoiceChip),
      );
      await tester.tap(expiredChip);
      await tester.pumpAndSettle();
      expect(find.byType(FilterPill), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('smart floating action button', () {
    testWidgets('slides away on scroll down and returns on scroll up', (
      tester,
    ) async {
      await tester.pumpWidget(app(const HomeShell()));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(PersonalPage), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);

      Offset fabSlide() =>
          tester.widget<AnimatedSlide>(find.byType(AnimatedSlide)).offset;

      expect(fabSlide(), Offset.zero);

      // Scrolling down moves the button out of the way.
      await tester.drag(find.byType(ListView).first, const Offset(0, -240));
      await tester.pumpAndSettle();
      expect(
        fabSlide().dy,
        greaterThan(0),
        reason: 'the button should slide down and hide',
      );

      // Scrolling back up brings it home.
      await tester.drag(find.byType(ListView).first, const Offset(0, 240));
      await tester.pumpAndSettle();
      expect(fabSlide(), Offset.zero);
      expect(tester.takeException(), isNull);
    });
  });
}
