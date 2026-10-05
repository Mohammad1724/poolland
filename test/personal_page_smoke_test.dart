import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/data/models.dart';
import 'package:poolland/data/repository.dart';
import 'package:poolland/data/store.dart';
import 'package:poolland/ui/personal_page.dart';
import 'package:poolland/ui/theme.dart';
import 'package:provider/provider.dart';

/// Smoke test for the personal finance page:
/// The page (quick buttons, budgets, recurring rules, and chart) should
/// render without exceptions.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late LocalStore store;
  late AppRepository repo;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('poolland_personal_ui');
    store = await LocalStore.openAt(tmp.path);
    repo = AppRepository(store: store);
    await repo.reload();
  });

  tearDown(() async {
    await store.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
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
          builder: (context, c) => Directionality(
              textDirection: TextDirection.ltr, child: c ?? const SizedBox()),
          home: Scaffold(body: child),
        ),
      );

  testWidgets('Personal finance page renders', (tester) async {
    await tester.pumpWidget(wrap(const PersonalPage()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Quick add'), findsOneWidget);
    expect(repo.quickExpenses.length, 6);
    expect(find.text('Monthly budgets'), findsOneWidget);
    expect(find.text('Recurring transactions'), findsOneWidget);
  });


  testWidgets('Personal finance page renders with sample data', (tester) async {
    // Loading sample data performs real I/O.
    await tester.runAsync(() async {
      await repo.loadDemoData();
    });
    await tester.pumpWidget(wrap(const PersonalPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    expect(repo.budgets, isNotEmpty);
    expect(repo.recurringRules, isNotEmpty);
    expect(repo.transactions.where((t) => t.scope == TxnScope.personal),
        isNotEmpty);
  });
}
