import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:poolland/core/localization.dart';
import 'package:poolland/data/models.dart';
import 'package:poolland/data/repository.dart';
import 'package:poolland/data/store.dart';
import 'package:poolland/ui/forms/transaction_edit_page.dart';
import 'package:poolland/ui/settings_page.dart';
import 'package:poolland/ui/theme.dart';
import 'package:poolland/ui/widgets/widgets.dart';

/// One level of category nesting: "car" -> "fuel". The picker shows the
/// child right under its parent (indented), the category manager can
/// create and re-parent children, and reports roll them up into the parent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late LocalStore store;
  late AppRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('poolland_subcat');
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

  group('pickOrderCategories', () {
    test('a child sits directly under its parent', () async {
      final parent = repo
          .topCategories(TxnKind.expense, scope: TxnScope.business)
          .first;
      await repo.addCategory('Fuel and oil', TxnKind.expense,
          parentId: parent.id);
      final child = repo
          .categoriesOf(TxnKind.expense, scope: TxnScope.business)
          .firstWhere((c) => c.name == 'Fuel and oil');

      final ordered = repo.pickOrderCategories(
        TxnKind.expense,
        scope: TxnScope.business,
      );
      final pi = ordered.indexWhere((c) => c.id == parent.id);
      final ci = ordered.indexWhere((c) => c.id == child.id);
      expect(pi, isNot(-1));
      expect(ci, pi + 1);
    });

    test('usage of a child lifts its parent in the order', () async {
      await repo.addCategory('UnusedParent A', TxnKind.expense);
      await repo.addCategory('UnusedParent B', TxnKind.expense);
      final b = repo
          .categoriesOf(TxnKind.expense, scope: TxnScope.business)
          .firstWhere((c) => c.name == 'UnusedParent B');
      await repo.addCategory('BusyChild B', TxnKind.expense,
          parentId: b.id);
      final child = repo
          .categoriesOf(TxnKind.expense, scope: TxnScope.business)
          .firstWhere((c) => c.name == 'BusyChild B');
      await repo.addTxn(Txn(
        id: LocalStore.newId(),
        kind: TxnKind.expense,
        amount: 10,
        date: DateTime(2026, 10, 1),
        categoryId: child.id,
        createdAt: DateTime(2026, 10, 1),
      ));
      final a = repo
          .categoriesOf(TxnKind.expense, scope: TxnScope.business)
          .firstWhere((c) => c.name == 'UnusedParent A');

      final ordered = repo.pickOrderCategories(
        TxnKind.expense,
        scope: TxnScope.business,
      );
      // B has no usage of its own, but its child does, so B ranks ahead of
      // the truly unused A.
      expect(
        ordered.indexWhere((c) => c.id == b.id),
        lessThan(ordered.indexWhere((c) => c.id == a.id)),
      );
    });

    test('invalid parents are refused', () async {
      // A parent of the other kind, and one from the other scope.
      final incomeCat = repo
          .topCategories(TxnKind.income, scope: TxnScope.business)
          .first;
      final personalCat = repo
          .topCategories(TxnKind.expense, scope: TxnScope.personal)
          .first;
      await repo.addCategory('WrongKind', TxnKind.expense,
          parentId: incomeCat.id);
      await repo.addCategory('WrongScope', TxnKind.expense,
          parentId: personalCat.id);
      final a = repo
          .categoriesOf(TxnKind.expense, scope: TxnScope.business)
          .firstWhere((c) => c.name == 'WrongKind');
      final b = repo
          .categoriesOf(TxnKind.expense, scope: TxnScope.business)
          .firstWhere((c) => c.name == 'WrongScope');
      expect(a.parentId, isNull);
      expect(b.parentId, isNull);
    });
  });

  group('the entry form picker', () {
    testWidgets('shows a subcategory and can select it', (tester) async {
      final parent = repo
          .topCategories(TxnKind.expense, scope: TxnScope.business)
          .first;
      await repo.addCategory('Fuel and oil', TxnKind.expense,
          parentId: parent.id);

      await tester.pumpWidget(
        wrap(
          const TransactionEditPage(
            initialKind: TxnKind.expense,
            autofocusAmount: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Category'),
        200,
        scrollable: formScrollable(),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(SelectField<Category>));
      await tester.pumpAndSettle();

      // The subcategory is in the list, next to its parent.
      expect(find.text('Fuel and oil'), findsOneWidget);

      await tester.tap(find.text('Fuel and oil'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(SelectField<Category>),
          matching: find.text('Fuel and oil'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the category manager', () {
    testWidgets('creates a subcategory under a chosen parent',
        (tester) async {
      await tester.pumpWidget(wrap(const CategoriesPage()));
      await tester.pumpAndSettle();

      // The expense tab.
      await tester.tap(find.text('Expense'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add category'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Fuel and oil');

      // Choose the first top-level parent from the dropdown.
      final firstParent = repo
          .categoriesOf(TxnKind.expense, scope: TxnScope.business)
          .where((c) => c.parentId == null)
          .first;
      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await tester.tap(find.text(firstParent.name).last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('Fuel and oil'), findsOneWidget);
      final created = repo
          .categoriesOf(TxnKind.expense, scope: TxnScope.business)
          .firstWhere((c) => c.name == 'Fuel and oil');
      expect(created.parentId, firstParent.id);
      expect(tester.takeException(), isNull);
    });

    testWidgets('deleting a parent keeps its children at the top level',
        (tester) async {
      final parent = repo
          .topCategories(TxnKind.expense, scope: TxnScope.business)
          .first;
      await repo.addCategory('Fuel and oil', TxnKind.expense,
          parentId: parent.id);

      await tester.pumpWidget(wrap(const CategoriesPage()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Expense'));
      await tester.pumpAndSettle();

      // Delete the parent through its row.
      final parentRow = find
          .ancestor(
            of: find.text(parent.name),
            matching: find.byType(CardBox),
          )
          .first;
      await tester.tap(
        find.descendant(
          of: parentRow,
          matching: find.byTooltip('Delete'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      final child = repo
          .categoriesOf(TxnKind.expense, scope: TxnScope.business)
          .firstWhere((c) => c.name == 'Fuel and oil');
      // The child survives as a top-level category and stays visible.
      expect(child.parentId, isNull);
      await tester.scrollUntilVisible(
        find.text('Fuel and oil'),
        100,
        scrollable: find.descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        ).first,
      );
      expect(find.text('Fuel and oil'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
