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
}
