// ignore_for_file: avoid_print
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:poolland/core/localization.dart';
import 'package:poolland/data/models.dart';
import 'package:poolland/data/repository.dart';
import 'package:poolland/data/store.dart';
import 'package:poolland/ui/settings_page.dart';
import 'package:poolland/ui/theme.dart';
import 'package:poolland/ui/widgets/widgets.dart';

/// TEMP (run 8): step-by-step diagnostics for the create-subcategory test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late LocalStore store;
  late AppRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('poolland_subcat_cd');
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

  Finder formScrollable() => find
      .descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      )
      .first;

  testWidgets('create diag', (tester) async {
    await tester.pumpWidget(wrap(const CategoriesPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();
    print('::error::CD1 tab=expense');

    await tester.scrollUntilVisible(
      find.text('Add category'),
      200,
      scrollable: formScrollable(),
    );
    await tester.pumpAndSettle();
    print('::error::CD2 addBtn=${find.text('Add category').evaluate().length}');

    await tester.tap(find.text('Add category'));
    await tester.pumpAndSettle();
    print(
      '::error::CD3 title=${find.text('New expense category').evaluate().length} '
      'textFields=${find.byType(TextField).evaluate().length} '
      'dropdowns=${find.byType(DropdownButtonFormField<String?>).evaluate().length}',
    );

    await tester.enterText(find.byType(TextField), 'Fuel and oil');
    print('::error::CD4 entered=${find.text('Fuel and oil').evaluate().length}');

    final firstParent = repo
        .categoriesOf(TxnKind.expense, scope: TxnScope.business)
        .where((c) => c.parentId == null)
        .first;
    print('::error::CD5 firstParent=${firstParent.name}');

    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    final all = find.text(firstParent.name);
    print(
      '::error::CD6 menuOpen parentMatches=${all.evaluate().length} '
      'topLevel=${find.text('Top-level category').evaluate().length}',
    );

    // Where are the matches, and which is last?
    for (final el in all.evaluate()) {
      final rect = tester.getRect(el);
      print('::error::CD7 match rect=$rect');
    }

    await tester.tap(all.last);
    await tester.pumpAndSettle();
    print(
      '::error::CD8 afterSelect '
      'selectedShown=${find.descendant(of: find.byType(DropdownButtonFormField<String?>), matching: find.text(firstParent.name)).evaluate().length} '
      'menuGone=${find.text('Top-level category').evaluate().length}',
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    print('::error::CD9 canceled');

    await tester.runAsync(() => repo.addCategory('Fuel and oil',
        TxnKind.expense, parentId: firstParent.id));
    await tester.pumpAndSettle();
    final inData = repo
        .categoriesOf(TxnKind.expense, scope: TxnScope.business)
        .firstWhere((c) => c.name == 'Fuel and oil');
    print('::error::CD10 inData parent=${inData.parentId == firstParent.id}');

    var count = find.text('Fuel and oil').evaluate().length;
    print('::error::CD11 foundUnscrolled=$count');
    if (count == 0) {
      await tester.scrollUntilVisible(
        find.text('Fuel and oil'),
        100,
        scrollable: formScrollable(),
      );
      count = find.text('Fuel and oil').evaluate().length;
      print('::error::CD12 foundAfterScroll=$count');
    }

    final ex = tester.takeException();
    print('::error::CD13 exception=${ex == null ? 'none' : '$ex'}');
  });
}
