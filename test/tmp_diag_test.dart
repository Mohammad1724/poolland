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

/// TEMP diagnostic round 6:
///  - DL: dump the expense ListView's actual child elements + the length of
///    its children list (the 'Add category' button is missing there).
///  - DN: the delete flow with a drain loop after the fire-and-forget write
///    (validates the tearDown-deadlock fix).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late LocalStore store;
  late AppRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('poolland_diag6');
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
        'dropdowns=${find.byType(DropdownButtonFormField<String?>).evaluate().length}');
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

    testWidgets('DN delete flow with drain loop', (tester) async {
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
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();
      print('DN-1 right after tap, fresh child parentId='
          '${repo.categoriesOf(TxnKind.expense, scope: TxnScope.business)
                .firstWhere((c) => c.name == 'Fuel and oil')
                .parentId}');
      // Drain the fire-and-forget repository writes before asserting.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final child = repo
          .categoriesOf(TxnKind.expense, scope: TxnScope.business)
          .firstWhere((c) => c.name == 'Fuel and oil');
      print('DN-2 after drain, child parentId=${child.parentId}');
      expect(child.parentId, isNull);
      await tester.scrollUntilVisible(
        find.text('Fuel and oil'),
        100,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('Fuel and oil'), findsOneWidget);
      expect(tester.takeException(), isNull);
      print('DN-3 all assertions passed');
    });
  });
}
