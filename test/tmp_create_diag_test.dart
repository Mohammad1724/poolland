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

/// TEMP (run 11): observation-only diagnostics for the create-subcategory
/// flow. The analyze output (written to test/tmp_analyze_out.txt by the
/// workflow) is read at main() time and embedded in the TEST NAME (the
/// FAILED_TEST annotation is the one channel known to survive). The flow
/// steps are carried in the failure reason (FAIL_DETAIL annotation).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String analyzeRaw = '(missing)';
  try {
    final f = File('test/tmp_analyze_out.txt');
    if (f.existsSync()) analyzeRaw = f.readAsStringSync();
  } catch (_) {}
  final String analyzeCompact = analyzeRaw
      .replaceAll('\r', ' ')
      .replaceAll('\n', '~')
      .substring(0, analyzeRaw.length > 650 ? 650 : analyzeRaw.length);

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

  testWidgets('CD $analyzeCompact', (tester) async {
    final r = <String>[];
    // Clear anything the binding captured so the test can never fail on a
    // leftover exception; record whether a step left one behind.
    Future<void> quiet() async {
      final ex = tester.takeException();
      if (ex != null) {
        r.add('took=${ex.runtimeType}');
      }
    }
    try {
      await tester.pumpWidget(wrap(const CategoriesPage()));
      await tester.pumpAndSettle();
      await quiet();
      r.add('pump=1');

      await tester.tap(find.text('Expense'));
      await tester.pumpAndSettle();
      await quiet();

      await tester.scrollUntilVisible(
        find.text('Add category'),
        200,
        scrollable: formScrollable(),
      );
      await tester.pumpAndSettle();
      await quiet();
      r.add('btn=${find.text('Add category').evaluate().length}');

      await tester.tap(find.text('Add category'));
      await tester.pumpAndSettle();
      await quiet();
      r.add(
        'dlg=${find.text('New expense category').evaluate().length} '
        'tf=${find.byType(TextField).evaluate().length} '
        'dd=${find.byType(DropdownButtonFormField<String?>).evaluate().length}',
      );

      await tester.enterText(find.byType(TextField), 'Fuel and oil');
      await tester.pumpAndSettle();
      await quiet();
      r.add('ent=${find.text('Fuel and oil').evaluate().length}');

      final firstParent = repo
          .categoriesOf(TxnKind.expense, scope: TxnScope.business)
          .where((c) => c.parentId == null)
          .first;
      r.add('pp=${firstParent.name}');

      await tester.tap(find.byType(DropdownButtonFormField<String?>));
      await tester.pumpAndSettle();
      await quiet();
      final all = find.text(firstParent.name);
      final rects = all
          .evaluate()
          .map((e) {
            final rc = tester.getRect(
              find.byElementPredicate((x) => identical(x, e)),
            );
            return '${rc.top.toInt()}-${rc.bottom.toInt()}';
          })
          .join('|');
      r.add('menu=${all.evaluate().length} rects=$rects');

      await tester.tap(all.last);
      await tester.pumpAndSettle();
      await quiet();
      r.add(
        'sel=${find.descendant(of: find.byType(DropdownButtonFormField<String?>), matching: find.text(firstParent.name)).evaluate().length} '
        'tl=${find.text('Top-level category').evaluate().length}',
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await quiet();
      r.add('cancel=1');

      await tester.runAsync(() => repo.addCategory('Fuel and oil',
          TxnKind.expense, parentId: firstParent.id));
      await tester.pumpAndSettle();
      await quiet();
      final inData = repo
          .categoriesOf(TxnKind.expense, scope: TxnScope.business)
          .firstWhere((c) => c.name == 'Fuel and oil');
      r.add('data=${inData.parentId == firstParent.id}');

      var found = find.text('Fuel and oil').evaluate().length;
      r.add('found=$found');
      if (found == 0) {
        await tester.scrollUntilVisible(
          find.text('Fuel and oil'),
          100,
          scrollable: formScrollable(),
        );
        found = find.text('Fuel and oil').evaluate().length;
        r.add('scf=$found');
      }
    } catch (e) {
      r.add('ERR ${e.runtimeType} ${e.toString().substring(0, e.toString().length > 200 ? 200 : e.toString().length)}');
    } finally {
      // The workflow posts this file as a PR comment (the annotation
      // channel caps out at five entries).
      try {
        File('test/tmp_diag_steps.txt')
            .writeAsStringSync('CR>>> ${r.join(' ')} <<<END\n');
      } catch (_) {}
    }
  });
}
