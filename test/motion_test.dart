import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/core/money.dart';
import 'package:flutter/services.dart';
import 'package:poolland/core/localization.dart';
import 'package:poolland/ui/design.dart';
import 'package:poolland/ui/gesture_tour.dart';
import 'package:poolland/ui/motion_kit.dart';
import 'package:poolland/ui/widgets/ledger_nav_bar.dart';
import 'package:poolland/ui/widgets/widgets.dart';

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

  testWidgets('SwipeActions opens on a trailing drag and fires the action', (
    tester,
  ) async {
    var fired = false;
    await tester.pumpWidget(
      wrap(
        Center(
          child: SizedBox(
            width: 320,
            child: SwipeActions(
              actions: [
                SwipeAction(
                  icon: Icons.edit_rounded,
                  label: 'Act',
                  color: const Color(0xFF0F766E),
                  onTap: () => fired = true,
                ),
              ],
              child: Container(height: 64, color: const Color(0xFFEEEEEE),
                  child: const Center(child: Text('row'))),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('row'), findsOneWidget);
    await tester.drag(find.text('row'), const Offset(-160, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Act'));
    await tester.pumpAndSettle();
    expect(fired, isTrue);
  });

  testWidgets('CopyMoney copies the plain number on long-press', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.pumpWidget(
      wrap(
        const Center(
          child: CopyMoney(value: 1250.4, child: Text('1,250')),
        ),
      ),
    );
    await tester.longPress(find.text('1,250'));
    await tester.pumpAndSettle();
    expect(copied, '1250');
  });

  testWidgets('ledger sheet closes on a pull-down at the top', (tester) async {
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (c) => FilledButton(
            onPressed: () => showLedgerSheet<void>(
              c,
              builder: (ctx) => SizedBox(
                height: 300,
                child: ListView(
                  children: [
                    for (var i = 0; i < 30; i++)
                      SizedBox(height: 40, child: Text('row $i')),
                  ],
                ),
              ),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('row 0'), findsOneWidget);
    // Pull down while the list is already at its top: overscroll closes.
    await tester.drag(find.byType(ListView), const Offset(0, 260));
    await tester.pumpAndSettle();
    expect(find.text('row 0'), findsNothing);
  });

  testWidgets('ledger sheet ignores a horizontal pull at the row start', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (c) => FilledButton(
            onPressed: () => showLedgerSheet<void>(
              c,
              builder: (ctx) => SizedBox(
                height: 300,
                child: Column(
                  children: [
                    SizedBox(
                      height: 60,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (var i = 0; i < 30; i++)
                            SizedBox(width: 120, child: Text('h $i')),
                        ],
                      ),
                    ),
                    const Expanded(child: Center(child: Text('sheet body'))),
                  ],
                ),
              ),
            ),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('sheet body'), findsOneWidget);
    // Dragging a horizontal chip row to (and past) its start edge reports
    // the same negative overscroll; it must never close the sheet sideways.
    await tester.drag(find.text('h 0'), const Offset(300, 0));
    await tester.pumpAndSettle();
    expect(find.text('sheet body'), findsOneWidget);
  });

  testWidgets('AmbientAurora renders a frozen layer without motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(const SizedBox(height: 240, width: 400, child: AmbientAurora())),
    );
    // pumpAndSettle returning means nothing ticks forever: with motion
    // disabled the aurora freezes on a static frame.
    await tester.pumpAndSettle();
    expect(find.byType(AmbientAurora), findsOneWidget);
    expect(find.byType(Icon), findsNWidgets(4)); // the four sparks
  });

  testWidgets('SheetHandle stays centered inside stretch columns', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        Center(
          child: SizedBox(
            width: 300,
            height: 200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: const [SheetHandle()],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final rect = tester.getRect(
      find.descendant(
        of: find.byType(SheetHandle),
        matching: find.byType(Container),
      ),
    );
    expect(rect.width, 44);
    expect(rect.center.dx, 400); // centered in the 800-wide test surface
  });

  testWidgets('Gesture tour lists every gesture', (tester) async {
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (c) => FilledButton(
            onPressed: () => showGestureTour(c),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    for (final key in ['Gesture guide', 'Swipe actions', 'Copy money']) {
      expect(find.text(key.tr), findsOneWidget, reason: key);
    }
    // The card list scrolls (and the sheet absorbs part of any drag), so
    // drive the scrollable until the last card is really on screen.
    await tester.scrollUntilVisible(
      find.text('Customer shortcuts'.tr),
      150,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    for (final key in [
      'Quick menu',
      'Dismiss sheets',
      'Customer shortcuts',
      'Got it',
    ]) {
      expect(find.text(key.tr), findsOneWidget, reason: key);
    }
    await tester.tap(find.text('Got it'.tr));
    await tester.pumpAndSettle();
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
