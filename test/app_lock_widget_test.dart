import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:poolland/core/localization.dart';
import 'package:poolland/data/repository.dart';
import 'package:poolland/data/store.dart';
import 'package:poolland/ui/lock/lock_screen.dart';
import 'package:poolland/ui/lock/pin_setup_page.dart';
import 'package:poolland/ui/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late LocalStore store;
  late AppRepository repo;

  setUp(() async {
    // A tall surface so the keypad plus the buttons below it are never
    // scrolled out of reach of tester.tap.
    await TestWidgetsFlutterBinding.ensureInitialized().setSurfaceSize(
      const Size(600, 1200),
    );
    AppLocalization.languageCode = 'en';
    tmp = await Directory.systemTemp.createTemp('poolland_lock');
    store = await LocalStore.openAt(tmp.path);
    repo = AppRepository(store: store);
    await repo.init();
  });

  tearDown(() async {
    await TestWidgetsFlutterBinding.ensureInitialized().setSurfaceSize(null);
    AppLocalization.languageCode = 'fa';
    await store.close();
    await tmp.delete(recursive: true);
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
        textDirection: TextDirection.ltr,
        child: c ?? const SizedBox(),
      ),
      home: child,
    ),
  );

  /// The gate keeps the app mounted behind the lock so the user comes back
  /// to the screen they left; "hidden" therefore means not painted, not
  /// absent from the tree.
  bool appContentVisible(WidgetTester tester) => tester
      .widget<Visibility>(
        find
            .ancestor(
              of: find.text('secret dashboard'),
              matching: find.byType(Visibility),
            )
            .first,
      )
      .visible;

  /// Put [child] on a pushed route, the way Settings opens it, so the page
  /// can pop itself without tearing down the only route in the test.
  Future<void> pumpPushed(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(wrap(_RouteHost(child: child)));
    await tester.pumpAndSettle();
  }

  /// Tap digits on the on-screen keypad.
  Future<void> typePin(WidgetTester tester, String pin) async {
    for (final digit in pin.split('')) {
      await tester.tap(find.widgetWithText(TextButton, digit));
      await tester.pump();
    }
  }

  group('AppLockGate', () {
    testWidgets('Shows the app directly when no PIN is set', (tester) async {
      await tester.pumpWidget(
        wrap(const AppLockGate(child: Text('secret dashboard'))),
      );

      expect(find.text('secret dashboard'), findsOneWidget);
      expect(find.byType(LockScreen), findsNothing);
    });

    testWidgets('Hides the app behind the lock screen when a PIN is set', (
      tester,
    ) async {
      await repo.setPin('2468');

      await tester.pumpWidget(
        wrap(const AppLockGate(child: Text('secret dashboard'))),
      );

      expect(find.byType(LockScreen), findsOneWidget);
      expect(appContentVisible(tester), isFalse);
    });

    testWidgets('A wrong PIN clears the entry and keeps the app hidden', (
      tester,
    ) async {
      await repo.setPin('2468');
      await tester.pumpWidget(
        wrap(const AppLockGate(child: Text('secret dashboard'))),
      );

      await typePin(tester, '1111');
      await tester.tap(find.text('Unlock'));
      await tester.pump();

      expect(find.text('Wrong PIN. Try again.'), findsOneWidget);
      expect(find.byType(LockScreen), findsOneWidget);
      expect(appContentVisible(tester), isFalse);
    });

    testWidgets('The right PIN reveals the app', (tester) async {
      await repo.setPin('2468');
      await tester.pumpWidget(
        wrap(const AppLockGate(child: Text('secret dashboard'))),
      );

      await typePin(tester, '2468');
      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();

      expect(appContentVisible(tester), isTrue);
      expect(find.byType(LockScreen), findsNothing);
    });

    testWidgets('Turning the lock on mid-session does not lock you out', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrap(const AppLockGate(child: Text('secret dashboard'))),
      );
      expect(appContentVisible(tester), isTrue);

      // Exactly what the Settings switch does.
      await repo.setPin('2468');
      await tester.pump();

      expect(appContentVisible(tester), isTrue);
      expect(find.byType(LockScreen), findsNothing);
    });
  });

  group('PinSetupPage', () {
    testWidgets('Creating a PIN requires typing it twice', (tester) async {
      await pumpPushed(tester, const PinSetupPage(mode: PinSetupMode.create));

      await typePin(tester, '1357');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Enter the new PIN again'), findsOneWidget);
      expect(repo.hasAppLock, isFalse, reason: 'not saved after one entry');

      await typePin(tester, '1357');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(repo.hasAppLock, isTrue);
      expect(repo.verifyPin('1357'), isTrue);
    });

    testWidgets('Mismatched entries start over and save nothing', (
      tester,
    ) async {
      await pumpPushed(tester, const PinSetupPage(mode: PinSetupMode.create));

      await typePin(tester, '1357');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      await typePin(tester, '2468');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(find.text('The PINs did not match. Start again.'), findsOneWidget);
      expect(find.text('Choose a new PIN (4-8 digits)'), findsOneWidget);
      expect(repo.hasAppLock, isFalse);
    });

    testWidgets('Removing the lock needs the current PIN', (tester) async {
      await repo.setPin('2468');
      await pumpPushed(tester, const PinSetupPage(mode: PinSetupMode.remove));

      await typePin(tester, '0000');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(find.text('Wrong PIN. Try again.'), findsOneWidget);
      expect(repo.hasAppLock, isTrue, reason: 'a wrong PIN removes nothing');

      await typePin(tester, '2468');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(repo.hasAppLock, isFalse);
    });

    testWidgets('Continue stays disabled until the PIN is long enough', (
      tester,
    ) async {
      await pumpPushed(tester, const PinSetupPage(mode: PinSetupMode.create));

      FilledButton button() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Continue'),
      );

      expect(button().onPressed, isNull);
      await typePin(tester, '123');
      expect(button().onPressed, isNull);
      await typePin(tester, '4');
      expect(button().onPressed, isNotNull);
    });
  });
}

/// Pushes [child] once the first frame is up, leaving a route underneath it.
class _RouteHost extends StatefulWidget {
  const _RouteHost({required this.child});

  final Widget child;

  @override
  State<_RouteHost> createState() => _RouteHostState();
}

class _RouteHostState extends State<_RouteHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute<bool>(builder: (_) => widget.child),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}
