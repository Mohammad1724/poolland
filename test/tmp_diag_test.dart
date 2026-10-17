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

/// TEMP diagnostic round 5:
///  - DF/DG run the full previously-hanging flows WITH the fix (category
///    created in a group-scoped setUp, i.e. outside the FakeAsync zone).
///  - DH walks the category-manager create flow step by step to find why the
///    'Add category' button is missing on the expense tab.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late LocalStore store;
  late AppRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('poolland_diag5');
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

  List<String> textData(WidgetTester t) =>
      find.byType(Text).evaluate().map((e) => (e.widget as Text).data ?? '').toList();

  group('preset child (created in group setUp)', () {
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
      print('DSETUP child created in real-async setUp OK');
    });

    testWidgets('DF entry form + sheet + child tap (fixed)', (tester) async {
      print('DF-1 pumpWidget');
      await tester.pumpWidget(
        wrap(
          const TransactionEditPage(
            initialKind: TxnKind.expense,
            autofocusAmount: false,
          ),
        ),
      );
      await tester.pumpAndSettle();
      print('DF-2 settled, child=${theChild.id}');
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
      print('DF-3 category visible');
      await tester.tap(find.byType(SelectField<Category>));
      await tester.pumpAndSettle();
      print('DF-4 sheet settled, fuel tiles='
          '${find.text('Fuel and oil').evaluate().length}');
      await tester.tap(find.text('Fuel and oil'));
      await tester.pumpAndSettle();
      print('DF-5 child selected, settled OK');
    });

    testWidgets('DG delete parent via UI (fixed)', (tester) async {
      final parent = repo
          .topCategories(TxnKind.expense, scope: TxnScope.business)
          .firstWhere((c) => c.id == theChild.parentId);
      print('DG-1 parent=${parent.name}');
      await tester.pumpWidget(wrap(const CategoriesPage()));
      await tester.pumpAndSettle();
      print('DG-2 settled');
      await tester.tap(find.text('Expense'));
      await tester.pumpAndSettle();
      print('DG-3 expense tab settled');
      final parentRow = find
          .ancestor(
            of: find.text(parent.name),
            matching: find.byType(CardBox),
          )
          .first;
      await tester.tap(
        find.descendant(of: parentRow, matching: find.byTooltip('Delete')),
      );
      print('DG-4 tapped delete icon');
      await tester.pumpAndSettle();
      print('DG-5 dialog settled, delete texts='
          '${find.text('Delete').evaluate().length}');
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      print('DG-6 deleted, child now parent=${theChild.parentId}');
    });
  });

  testWidgets('DH create flow walk (find the missing button)', (tester) async {
    print('DH-1 pumpWidget');
    await tester.pumpWidget(wrap(const CategoriesPage()));
    await tester.pumpAndSettle();
    print('DH-2 settled');
    print('DH-3 income texts: ${textData(tester).take(30).toList()}');
    print('DH-4 income buttons=${find.byWidgetPredicate((w) => w is FilledButton).evaluate().length} '
        'addTexts=${find.text('Add category').evaluate().length}');
    await tester.tap(find.text('Expense'));
    print('DH-5 tapped expense tab');
    await tester.pumpAndSettle();
    print('DH-6 expense texts: ${textData(tester).take(40).toList()}');
    print('DH-7 expense buttons=${find.byWidgetPredicate((w) => w is FilledButton).evaluate().length} '
        'addTexts=${find.text('Add category').evaluate().length} '
        'lists=${find.byType(ListView).evaluate().length} '
        'exception=${tester.takeException()}');
    final addBtn = find.text('Add category');
    if (addBtn.evaluate().isEmpty) {
      // Try to reach the dialog through the button widget directly.
      final byType =
          find.byWidgetPredicate((w) => w is FilledButton).evaluate();
      print('DH-8 fallback filled buttons=${byType.length}');
    }
  });
}
