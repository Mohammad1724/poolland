import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/core/money.dart';
import 'package:poolland/ui/design.dart';
import 'package:poolland/ui/motion_kit.dart';
import 'package:poolland/ui/widgets/ledger_nav_bar.dart';

/// Component tests for the motion kit.
///
/// The suite-wide config disables [Motion.motionEnabled], so every component
/// must render its final state immediately here — which is exactly the
/// contract the reduced-motion and test paths rely on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) => MaterialApp(
    locale: const Locale('en'),
    supportedLocales: const [Locale('en')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(body: child),
  );

  testWidgets('OdometerMoney settles on the exact formatted value', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const OdometerMoney(1250, withSymbol: false)),
    );
    await tester.pumpAndSettle();
    expect(find.text(Money.text(1250, withSymbol: false)), findsOneWidget);
  });

  testWidgets('LedgerNavBar reports the tapped destination', (tester) async {
    int selected = -1;
    await tester.pumpWidget(
      wrap(
        StatefulBuilder(
          builder: (context, setState) => Align(
            alignment: Alignment.bottomCenter,
            child: LedgerNavBar(
              index: 0,
              onDestinationSelected: (i) => setState(() => selected = i),
              destinations: const [
                LedgerNavDestination(
                  icon: Icons.person_outline_rounded,
                  selectedIcon: Icons.person_rounded,
                  label: 'One',
                ),
                LedgerNavDestination(
                  icon: Icons.dashboard_outlined,
                  selectedIcon: Icons.dashboard_rounded,
                  label: 'Two',
                ),
                LedgerNavDestination(
                  icon: Icons.people_outline_rounded,
                  selectedIcon: Icons.people_rounded,
                  label: 'Three',
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('One'), findsOneWidget);
    final rect = tester.getRect(find.byType(LedgerNavBar));
    await tester.tapAt(Offset(rect.left + rect.width * 1.5 / 3, rect.center.dy));
    await tester.pumpAndSettle();
    expect(selected, 1);
  });

  testWidgets('showLedgerSheet opens from the bottom and returns its result', (
    tester,
  ) async {
    String? result;
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              result = await showLedgerSheet<String>(
                context,
                builder: (_) => ElevatedButton(
                  onPressed: () => Navigator.pop(context, 'picked'),
                  child: const Text('Pick me'),
                ),
              );
            },
            child: const Text('Open sheet'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();
    expect(find.text('Pick me'), findsOneWidget);
    await tester.tap(find.text('Pick me'));
    await tester.pumpAndSettle();
    expect(result, 'picked');
  });

  testWidgets('EnterMotion and SlipIn render their child', (tester) async {
    await tester.pumpWidget(
      wrap(
        Column(
          children: const [
            EnterMotion(index: 2, child: Text('entered')),
            SlipIn(child: Text('slipped')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('entered'), findsOneWidget);
    expect(find.text('slipped'), findsOneWidget);
  });
}
