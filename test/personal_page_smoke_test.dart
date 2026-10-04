import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/data/repository.dart';
import 'package:poolland/data/store.dart';
import 'package:poolland/ui/personal_page.dart';
import 'package:poolland/ui/theme.dart';
import 'package:provider/provider.dart';

/// تست دودِ صفحه‌ی حسابداری شخصی:
/// صفحه (با دکمه‌های سریع، بودجه، قوانین تکرار و نمودار) باید
/// بدون استثنا رندر شود.
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
          locale: const Locale('fa', 'IR'),
          supportedLocales: const [Locale('fa', 'IR'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.light(),
          builder: (context, c) => Directionality(
              textDirection: TextDirection.rtl, child: c ?? const SizedBox()),
          home: Scaffold(body: child),
        ),
      );

  testWidgets('صفحه‌ی شخصی رندر می‌شود', (tester) async {
    await tester.pumpWidget(wrap(const PersonalPage()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('ثبت سریع'), findsOneWidget);
    expect(repo.quickExpenses.length, 6);
    expect(find.text('بودجه‌ی ماهانه'), findsOneWidget);
    expect(find.text('تراکنش‌های تکرارشونده'), findsOneWidget);
  });

}
