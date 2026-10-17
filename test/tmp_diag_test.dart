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

/// TEMP diagnostic round 7:
///  - DL2: is the 'Add category' button reachable by scrolling (expense tab)?
///  - DN3: delete flow = dialog via UI + CANCEL, then the repository write
///    in tester.runAsync (real async). Clean teardown?
///  - DN4: create flow = full dialog SAVE via UI; does the in-zone write
///    complete if we then runAsync a real delay?
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late LocalStore store;
  late AppRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('poolland_diag7');
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

  testWidgets('DL2 reach add button by scrolling', (tester) async {
    await tester.pumpWidget(wrap(const CategoriesPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();
    final before = find.text('Add category').evaluate().length;
    print('DL2-1 before scroll addBtn=$before');
    await tester.scrollUntilVisible(
      find.text('Add category'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    print('DL2-2 after scroll addBtn='
        '${find.text('Add category').evaluate().length}');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add category'));
    await tester.pumpAndSettle();
    print('DL2-3 dialog opened, titleFound='
        '${find.text('New expense category').evaluate().length} '
        'dropdowns='
        '${find.byType(DropdownButtonFormField<String?>).evaluate().length}');
  });

  group('preset child', () {
    late Category theChild;

    setUp(() async {
      final parent = repo
          .topCategories(TxnKind.expense, scope: TxnScope.business)
          .first;
      await repo.addCategory('Fuel and oil', TxnKind.expense,
          parentId: parent.id);
      theChild = repo
          .categoriesOf(TxnKind.expense, scope: TxnScope.business)
          .firstWhere((c) => c.name == 'Fuel and oil');
    });

    testWidgets('DN3 delete: cancel dialog + runAsync write', (tester) async {
      final parent = repo
          .topCategories(TxnKind.expense, scope: TxnScope.business)
          .firstWhere((c) => c.id == theChild.parentId);
      await tester.pumpWidget(wrap(const CategoriesPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expense'));
      await tester.pumpAndSettle();
      final parentRow = find
          .ancestor(
            of: find.text(parent.name),
            matching: find.byType(CardBox),
          )
          .first;
      await tester.tap(
        find.descendant(of: parentRow, matching: find.byTooltip('Delete')),
      );
      await tester.pumpAndSettle();
      // Close the dialog with Cancel: the UI handler then performs no write.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      print('DN3-1 dialog cancelled');
      // Real-async zone: the repository write can actually complete here.
      await tester.runAsync(() => repo.deleteCategory(parent.id));
      print('DN3-2 runAsync delete done');
      await tester.pumpAndSettle();
      final child = repo
          .categoriesOf(TxnKind.expense, scope: TxnScope.business)
          .firstWhere((c) => c.name == 'Fuel and oil');
      print('DN3-3 child parentId after=${child.parentId}');
      expect(child.parentId, isNull);
      print('DN3-4 assertion passed');
    });
  });

  testWidgets('DN4 create: save via UI then runAsync drain', (tester) async {
    await tester.pumpWidget(wrap(const CategoriesPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Add category'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add category'));
    await tester.pumpAndSettle();
    print('DN4-1 dialog open');
    final firstParent = repo
        .categoriesOf(TxnKind.expense, scope: TxnScope.business)
        .where((c) => c.parentId == null)
        .first;
    await tester.enterText(find.byType(TextField), 'Fuel and oil');
    await tester.tap(find.byType(DropdownButtonFormField<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(firstParent.name).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    print('DN4-2 Add tapped, dialog closed');
    // The save handler runs in the FakeAsync zone; give the event loop real
    // time via runAsync and see if the in-zone write completes.
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
    await tester.pumpAndSettle();
    final created = repo
        .categoriesOf(TxnKind.expense, scope: TxnScope.business)
        .where((c) => c.name == 'Fuel and oil')
        .toList();
    print('DN4-3 after drain count=${created.length} '
        'parentIds=${created.map((c) => c.parentId).toList()} '
        'expectedParent=${firstParent.id}');
  });
}
