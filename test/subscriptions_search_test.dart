import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:poolland/core/localization.dart';
import 'package:poolland/data/repository.dart';
import 'package:poolland/data/store.dart';
import 'package:poolland/ui/subscriptions_page.dart';
import 'package:poolland/ui/theme.dart';
import 'package:poolland/ui/widgets/widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late LocalStore store;
  late AppRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('poolland_sub_search');
    store = await LocalStore.openAt(tmp.path);
    repo = AppRepository(store: store);
    await repo.loadDemoData();
  });

  tearDown(() async {
    await store.close();
    await tmp.delete(recursive: true);
  });

  Widget wrap(Widget child, {bool rtl = false}) {
    AppLocalization.languageCode = rtl ? 'fa' : 'en';
    return ChangeNotifierProvider<AppRepository>.value(
      value: repo,
      child: MaterialApp(
        locale: Locale(rtl ? 'fa' : 'en'),
        supportedLocales: const [Locale('en'), Locale('fa')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: AppTheme.light(),
        builder: (context, child) => Directionality(
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          child: child ?? const SizedBox(),
        ),
        home: Scaffold(body: child),
      ),
    );
  }

  Finder searchTextField() => find.descendant(
    of: find.byType(AppSearchField),
    matching: find.byType(TextField),
  );

  testWidgets('Subscription search counts matches and clears filters', (
    tester,
  ) async {
    await tester.pumpWidget(wrap(const SubscriptionsPage()));
    await tester.enterText(searchTextField(), 'no-such-subscription');
    await tester.pump();

    expect(find.text('All (0)'), findsOneWidget);
    expect(find.text('No subscriptions match these filters'), findsOneWidget);
    await tester.tap(find.text('Clear search and status filter'));
    await tester.pump();

    expect(find.text('No subscriptions match these filters'), findsNothing);
    expect(
      tester.widget<TextField>(searchTextField()).controller!.text,
      isEmpty,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Subscriptions page fits a narrow Persian RTL viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(wrap(const SubscriptionsPage(), rtl: true));
    expect(tester.takeException(), isNull);
  });
}
