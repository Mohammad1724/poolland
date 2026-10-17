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

/// TEMP diagnostic: one small test per chunk of the failing flows, with a
/// print before every step. The last printed line locates the hang.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late LocalStore store;
  late AppRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('poolland_diag');
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

  Future<void> addChild() async {
    final parent = repo
        .topCategories(TxnKind.expense, scope: TxnScope.business)
        .first;
    print('D-PRE adding child under ${parent.name} (${parent.id})');
    await repo.addCategory('Fuel and oil', TxnKind.expense,
        parentId: parent.id);
    print('D-PRE child added, expense cats now '
        '${repo.categoriesOf(TxnKind.expense, scope: TxnScope.business).length}');
  }

  testWidgets('diag A: categories page, no child', (tester) async {
    print('DA-1 pumpWidget');
    await tester.pumpWidget(wrap(const CategoriesPage()));
    print('DA-2 pumpAndSettle');
    await tester.pumpAndSettle();
    print('DA-3 settled OK');
  });

  testWidgets('diag B: categories page, with child', (tester) async {
    await addChild();
    print('DB-1 pumpWidget');
    await tester.pumpWidget(wrap(const CategoriesPage()));
    print('DB-2 pumpAndSettle');
    await tester.pumpAndSettle();
    print('DB-3 settled OK');
  });

  testWidgets('diag C: expense tab + add button', (tester) async {
    print('DC-1 pumpWidget');
    await tester.pumpWidget(wrap(const CategoriesPage()));
    await tester.pumpAndSettle();
    print('DC-2 settle done');
    final expenseTab = find.text('Expense').evaluate().length;
    final addBtn = find.text('Add category').evaluate().length;
    print('DC-3 expenseTab=$expenseTab addBtn=$addBtn '
        'cards=${find.byType(CardBox).evaluate().length} '
        'buttons=${find.byType(FilledButton).evaluate().length} '
        'lists=${find.byType(ListView).evaluate().length}');
    await tester.tap(find.text('Expense'));
    print('DC-4 tapped expense tab');
    await tester.pumpAndSettle();
    print('DC-5 settle done');
    final addBtn2 = find.text('Add category').evaluate().length;
    print('DC-6 addBtn after tab=$addBtn2 '
        'cards=${find.byType(CardBox).evaluate().length}');
  });

  testWidgets('diag D: entry form, with child, open sheet, tap child',
      (tester) async {
    await addChild();
    print('DD-1 pumpWidget');
    await tester.pumpWidget(
      wrap(
        const TransactionEditPage(
          initialKind: TxnKind.expense,
          autofocusAmount: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    print('DD-2 settle done');
    await tester.scrollUntilVisible(
      find.text('Category'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    print('DD-3 category visible');
    await tester.tap(find.byType(SelectField<Category>));
    print('DD-4 tapped SelectField');
    await tester.pumpAndSettle();
    print('DD-5 sheet settled, fuel tiles='
        '${find.text('Fuel and oil').evaluate().length}');
    await tester.tap(find.text('Fuel and oil'));
    print('DD-6 tapped child tile');
    await tester.pumpAndSettle();
    print('DD-7 sheet closed, settled OK');
  });

  testWidgets('diag E: delete parent with child', (tester) async {
    final parent = repo
        .topCategories(TxnKind.expense, scope: TxnScope.business)
        .first;
    await repo.addCategory('Fuel and oil', TxnKind.expense,
        parentId: parent.id);
    print('DE-1 child added under ${parent.name}');
    await tester.pumpWidget(wrap(const CategoriesPage()));
    await tester.pumpAndSettle();
    print('DE-2 settled');
    await tester.tap(find.text('Expense'));
    await tester.pumpAndSettle();
    print('DE-3 expense tab settled');
    final parentRow = find
        .ancestor(
          of: find.text(parent.name),
          matching: find.byType(CardBox),
        )
        .first;
    await tester.tap(
      find.descendant(of: parentRow, matching: find.byTooltip('Delete')),
    );
    print('DE-4 tapped delete icon');
    await tester.pumpAndSettle();
    print('DE-5 confirm dialog settled, deleteBtn='
        '${find.text('Delete').evaluate().length}');
    await tester.tap(find.text('Delete'));
    print('DE-6 tapped Delete');
    await tester.pumpAndSettle();
    print('DE-7 settled OK');
  });
}
