import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/core/localization.dart';
import 'package:poolland/ui/widgets/widgets.dart';

/// Widget tests for the save-feedback and live-preview UX improvements.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLocalization.languageCode = 'en';
  });

  group('FormActionBar save feedback', () {
    testWidgets('shows a spinner and blocks double-tap while saving', (
      tester,
    ) async {
      var calls = 0;
      final completer = Completer<void>();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: const SizedBox(),
            bottomNavigationBar: FormActionBar(
              label: 'Save',
              onPressed: () {
                calls += 1;
                return completer.future;
              },
            ),
          ),
        ),
      );

      // First tap starts the save.
      await tester.tap(find.text('Save'));
      await tester.pump();

      // While in flight the button shows a spinner and "Saving…".
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Saving…'), findsOneWidget);

      // A nervous second tap must not start another save.
      await tester.tap(find.text('Saving…'));
      await tester.pump();

      completer.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(calls, 1, reason: 'double-tap must not double-record');
      // After completion the normal label is back and the spinner is gone.
      expect(find.text('Save'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows an error snackbar when the save throws', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: const SizedBox(),
            bottomNavigationBar: FormActionBar(
              label: 'Save',
              onPressed: () async {
                throw StateError('boom');
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Saving failed. Please try again.'), findsOneWidget);
      // The button is usable again after the failure.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('disabled when onPressed is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(),
            bottomNavigationBar: FormActionBar(label: 'Save', onPressed: null),
          ),
        ),
      );

      // Tapping must not throw or show a spinner when there is no action.
      await tester.tap(find.text('Save'), warnIfMissed: false);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Save'), findsOneWidget);
    });
  });

  group('AmountField live preview', () {
    testWidgets('shows a grouped live amount under the field', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: AmountField(controller: controller, currency: 'IRT'),
            ),
          ),
        ),
      );

      // Empty at first: no preview line.
      expect(find.textContaining('='), findsNothing);

      await tester.enterText(find.byType(TextFormField), '1500000');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('= 1,500,000 Toman'), findsOneWidget);
    });

    testWidgets('preview can be disabled', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: AmountField(
                controller: controller,
                currency: 'IRT',
                livePreview: false,
              ),
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextFormField), '1500000');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('='), findsNothing);
    });
  });

  /// The snack bar is the app's only channel for "that worked" and "that did
  /// not", so its contract is tested like any other user-facing behaviour:
  /// a status icon, a readable window, and an action that can be pressed.
  group('Snack feedback', () {
    Future<ScaffoldMessengerState> pumpMessenger(WidgetTester tester) async {
      late ScaffoldMessengerState messenger;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                messenger = ScaffoldMessenger.of(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      return messenger;
    }

    testWidgets('a confirmation shows a tick and stays four seconds', (
      tester,
    ) async {
      final messenger = await pumpMessenger(tester);
      showMessengerSnack(messenger, 'Changes saved');
      await tester.pump();

      expect(find.text('Changes saved'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.duration, kSnackDuration);
      // Four seconds, not Material's default: enough to read a Persian
      // sentence without reaching for the screen.
      expect(bar.duration, const Duration(seconds: 4));
    });

    testWidgets('an error shows a warning and stays longer', (tester) async {
      final messenger = await pumpMessenger(tester);
      showMessengerSnack(messenger, 'Saving failed', error: true);
      await tester.pump();

      expect(find.text('Saving failed'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.duration, kSnackErrorDuration);
      expect(bar.backgroundColor, const Color(0xFFB91C1C));
    });

    testWidgets('an action keeps the bar long enough to be used', (
      tester,
    ) async {
      final messenger = await pumpMessenger(tester);
      var undone = false;
      showMessengerSnack(
        messenger,
        'Transaction deleted',
        actionLabel: 'Undo',
        onAction: () => undone = true,
      );
      await tester.pump();

      final bar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(bar.duration, const Duration(seconds: 5));
      expect(bar.action, isNotNull);

      // Let the bar finish sliding in, otherwise the action is still off
      // screen and cannot be hit.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(undone, isTrue);
    });
  });

  group('ActionHint', () {
    testWidgets('the save bar says what is missing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: const SizedBox(),
            bottomNavigationBar: const FormActionBar(
              label: 'Record',
              onPressed: null,
              hint: 'Enter an amount',
            ),
          ),
        ),
      );

      expect(find.text('Enter an amount'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
      // Still refused, but no longer silent about why.
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('no hint is left behind once the form is complete', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: const SizedBox(),
            bottomNavigationBar: FormActionBar(
              label: 'Record',
              onPressed: () async {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.info_outline_rounded), findsNothing);
    });
  });
}
