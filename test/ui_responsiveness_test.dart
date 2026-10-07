import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/core/debounce.dart';
import 'package:poolland/core/localization.dart';
import 'package:poolland/data/repository.dart';
import 'package:poolland/data/store.dart';
import 'package:poolland/ui/customers_page.dart';
import 'package:poolland/ui/dashboard_page.dart';
import 'package:poolland/ui/home_shell.dart';
import 'package:poolland/ui/personal_page.dart';
import 'package:poolland/ui/theme.dart';
import 'package:provider/provider.dart';

/// Phase 1 responsiveness work: debounced search, lazily mounted tabs, and the
/// debounce helper itself.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Debouncer', () {
    testWidgets('runs only after the pause', (tester) async {
      final debouncer = Debouncer(duration: const Duration(milliseconds: 200));
      addTearDown(debouncer.dispose);
      var calls = 0;

      debouncer.run(() => calls++);
      await tester.pump(const Duration(milliseconds: 100));
      expect(calls, 0, reason: 'must not fire while the user is still typing');

      await tester.pump(const Duration(milliseconds: 150));
      expect(calls, 1);
    });

    testWidgets('collapses a burst of calls into one', (tester) async {
      final debouncer = Debouncer(duration: const Duration(milliseconds: 200));
      addTearDown(debouncer.dispose);
      var calls = 0;

      for (var i = 0; i < 6; i++) {
        debouncer.run(() => calls++);
        await tester.pump(const Duration(milliseconds: 30));
      }
      expect(calls, 0);

      await tester.pump(const Duration(milliseconds: 250));
      expect(calls, 1, reason: 'a burst of keystrokes must cause one update');
    });

    testWidgets('cancel and dispose drop a pending call', (tester) async {
      final cancelled = Debouncer(
        duration: const Duration(milliseconds: 100),
      );
      final disposed = Debouncer(duration: const Duration(milliseconds: 100));
      var calls = 0;

      cancelled.run(() => calls++);
      cancelled.cancel();
      disposed.run(() => calls++);
      disposed.dispose();

      await tester.pump(const Duration(milliseconds: 300));
      expect(calls, 0);
    });
  });

  group('HomeShell lazy tabs', () {
    late Directory tmp;
    late LocalStore store;
    late AppRepository repo;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('poolland_lazy');
      store = await LocalStore.openAt(tmp.path);
      repo = AppRepository(store: store);
      await repo.loadDemoData();
    });

    tearDown(() async {
      await store.close();
      await tmp.delete(recursive: true);
    });

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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('builds only the tab that is open', (tester) async {
      await tester.pumpWidget(wrapShell());
      await settleShell(tester);

      // The first tab is open, so its page is mounted...
      expect(find.byType(PersonalPage), findsOneWidget);
      // ...while the tabs that were never opened are still blank slots.
      expect(find.byType(CustomersPage), findsNothing);
      expect(find.byType(DashboardPage), findsNothing);
      expect(tester.takeException(), isNull);

      // ...and opening another tab mounts that page.
      await tapTab(tester, 1);
      expect(find.byType(DashboardPage), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tapTab(tester, 2);
      expect(find.byType(CustomersPage), findsOneWidget);
      // Previously opened tabs stay mounted so their state is not lost.
      expect(find.byType(DashboardPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('CustomersPage search', () {
    late Directory tmp;
    late LocalStore store;
    late AppRepository repo;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('poolland_search');
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

    testWidgets('filters after the typing pause, not on every keystroke', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(const CustomersPage()));
      await tester.pumpAndSettle();
      expect(repo.customers, isNotEmpty);

      await tester.enterText(find.byType(TextField), 'no-such-customer');

      // Right after typing the list has not been re-filtered yet.
      await tester.pump();
      expect(find.text('No items found'), findsNothing);

      // Once typing stops, the filter is applied.
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('No items found'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
