import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:poolland/core/format_utils.dart';
import 'package:poolland/core/localization.dart';
import 'package:poolland/data/models.dart';
import 'package:poolland/data/repository.dart';
import 'package:poolland/data/store.dart';
import 'package:poolland/ui/forms/transaction_edit_page.dart';
import 'package:poolland/ui/theme.dart';
import 'package:poolland/ui/widgets/widgets.dart';

/// UX contract tests for the redesigned transaction entry form.
///
/// The form is built around speed: one line of kind tiles, a full-width
/// auto-focused amount, a "Today" date pill, and one-tap chip rows for the
/// recent entries, the frequent contacts and the categories. These tests
/// pin that behavior down.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late LocalStore store;
  late AppRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('poolland_txnform');
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

  Finder amountField() => find.widgetWithText(TextField, 'Amount');

  Finder recordButton() => find.descendant(
    of: find.byType(FormActionBar),
    matching: find.byType(FilledButton),
  );

  /// The form's main list. The kind strip is a second, inner ListView, so
  /// address the outer one explicitly: it is the first ListView in the tree.
  Finder formScrollable() => find
      .descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      )
      .first;

  testWidgets('all five kind tiles render in one line', (tester) async {
    await tester.pumpWidget(
      wrap(const TransactionEditPage(autofocusAmount: false)),
    );
    await tester.pumpAndSettle();

    for (final label in ['Income', 'Expense', 'Receive', 'Refund', 'Paid out']) {
      expect(find.text(label), findsOneWidget, reason: '$label tile missing');
    }
    // The scope selector stays a real 44dp control (touch-target contract).
    final scope = tester.getSize(find.byType(SegmentedButton<TxnScope>));
    expect(scope.height, greaterThanOrEqualTo(44));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the date reads Today until it is changed', (tester) async {
    await tester.pumpWidget(
      wrap(const TransactionEditPage(autofocusAmount: false)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Today'), findsOneWidget);
    // And the currency picker sits on the same compact row.
    expect(find.text('Currency'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the record button mirrors the entered amount', (tester) async {
    await tester.pumpWidget(
      wrap(const TransactionEditPage(autofocusAmount: false)),
    );
    await tester.pumpAndSettle();

    // Nothing typed: the plain label and a disabled button.
    expect(find.text('Record'), findsOneWidget);
    expect(tester.widget<FilledButton>(recordButton()).onPressed, isNull);

    await tester.enterText(amountField(), '12345');
    await tester.pump();
    expect(find.textContaining('Record 12,345'), findsOneWidget);
    expect(find.text('Record'), findsNothing);
    expect(tester.widget<FilledButton>(recordButton()).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a recent chip repeats the whole entry in one tap', (
    tester,
  ) async {
    final target = repo.recentDistinctTxns(4).first;
    final customer = repo.customerById(target.customerId);

    await tester.pumpWidget(
      wrap(const TransactionEditPage(autofocusAmount: false)),
    );
    await tester.pumpAndSettle();

    // No contact is selected before the repeat.
    expect(find.byType(MoneyText), findsNothing);

    // The strip chip is the first "name · amount" label on the page.
    await tester.tap(find.textContaining(' · ').first);
    await tester.pumpAndSettle();

    final amount = tester.widget<TextField>(amountField());
    expect(parseAmount(amount.controller!.text), target.amount);

    // The description sits at the bottom of the lazy list; bring it into
    // view before reading it.
    await tester.scrollUntilVisible(
      find.byType(AppTextField),
      200,
      scrollable: formScrollable(),
    );
    final note = tester.widget<AppTextField>(find.byType(AppTextField));
    expect(note.controller.text, target.note);

    // A business entry with a contact brings the live balance card, and a
    // category kind brings the cash/credit control with it.
    final hasBusinessCustomer =
        target.customerId != null && target.scope == TxnScope.business;
    if (hasBusinessCustomer) {
      expect(customer, isNotNull);
      await tester.scrollUntilVisible(
        find.byType(MoneyText),
        200,
        scrollable: formScrollable(),
      );
      expect(find.byType(MoneyText), findsOneWidget);
      final categoryKind =
          target.kind == TxnKind.income || target.kind == TxnKind.expense;
      if (categoryKind) {
        await tester.scrollUntilVisible(
          find.text('Credit'),
          200,
          scrollable: formScrollable(),
        );
        expect(find.text('Cash'), findsOneWidget);
        expect(find.text('Credit'), findsOneWidget);
      }
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('contact chips select and clear with one tap each', (tester)
    async {
    final first = repo.topCustomers(limit: 4).first;

    await tester.pumpWidget(
      wrap(const TransactionEditPage(autofocusAmount: false)),
    );
    await tester.pumpAndSettle();

    expect(find.byType(MoneyText), findsNothing);

    // The chip strip can sit right at the bottom of the viewport; make sure
    // the chip is in view before tapping it.
    final nameFinder = find.text(first.name);
    await tester.scrollUntilVisible(nameFinder, 200, scrollable: formScrollable());
    await tester.tap(nameFinder.first);
    await tester.pumpAndSettle();

    // The live balance appears next to the selected contact.
    await tester.scrollUntilVisible(
      find.byType(MoneyText),
      200,
      scrollable: formScrollable(),
    );
    expect(find.byType(MoneyText), findsOneWidget);

    // Tapping the selected chip again clears it. The card now carries the
    // same name, so address the chip through its InkWell ancestor.
    final chipFinder = find
        .ancestor(of: nameFinder, matching: find.byType(InkWell))
        .first;
    await tester.scrollUntilVisible(chipFinder, 200, scrollable: formScrollable());
    await tester.tap(chipFinder);
    await tester.pumpAndSettle();
    expect(find.byType(MoneyText), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // TEMP diagnostics: the runner log is unreadable outside, so the test
  // reports its own progress as check annotations.
  // ignore: avoid_print
  void diag(String s) => print(
    '::notice file=test/transaction_form_ux_test.dart,line=1::DIAG $s',
  );

  // Long payloads are printed as plain lines; the CI workflow greps them
  // and re-emits them as annotations (the in-test commands get lost).
  // ignore: avoid_print
  void raw(String s) => print('DIAGRAW $s');

  testWidgets('cash and credit explain themselves as the amount changes', (
    tester,
  ) async {
    final first = repo.topCustomers(limit: 4).first;

    await tester.pumpWidget(
      wrap(const TransactionEditPage(autofocusAmount: false)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(amountField(), '2000000');
    await tester.pump();

    // The chip strip can sit right at the bottom of the viewport; make sure
    // the chip is in view before tapping it.
    final nameFinder = find.text(first.name);
    diag('name=${first.name} matches=${nameFinder.evaluate().length}');
    await tester.scrollUntilVisible(nameFinder, 200, scrollable: formScrollable());
    await tester.pump();
    if (nameFinder.evaluate().length == 1) {
      final r = tester.getRect(nameFinder.first);
      diag('chipTextRect=$r (viewport 800x600)');
    } else {
      diag('chipText: ${nameFinder.evaluate().length} matches, cannot rect');
    }
    await tester.tap(nameFinder.first);
    await tester.pumpAndSettle();
    diag('afterTap moneyTexts=${find.byType(MoneyText).evaluate().length}');

    // The cash/credit control sits below the fold; drag until it is
    // actually visible (not just built in the list's cache).
    await tester.dragUntilVisible(
      find.text('Credit'),
      formScrollable(),
      const Offset(0, -300),
    );
    diag(
      'afterDrag credit=${find.text('Credit').evaluate().length} '
      'hint=${find.text('Cash goes into the box.').evaluate().length}',
    );
    if (find.text('Credit').evaluate().length == 1) {
      diag('creditRect=${tester.getRect(find.text('Credit'))}');
    }
    final scrollableState = tester.state<ScrollableState>(formScrollable());
    diag(
      'scroll pixels=${scrollableState.position.pixels} '
      'max=${scrollableState.position.maxScrollExtent} '
      'viewportDim=${scrollableState.position.viewportDimension} '
      'minScrollExtent=${scrollableState.position.minScrollExtent}',
    );
    final exc = tester.takeException();
    diag('exception=${exc == null ? 'none' : exc.runtimeType}');
    final texts = find
        .byType(Text)
        .evaluate()
        .map((e) {
          final data = (e.widget as Text).data ?? '<rich>';
          final box = e.renderObject;
          final y =
              box is RenderBox && box.hasSize
                  ? box.localToGlobal(Offset.zero).dy
                  : -1;
          return '$data@${y.toStringAsFixed(0)}';
        })
        .toList();
    final joined = texts.join(' | ');
    diag(
      'treeTexts(${texts.length})='
      '${joined.substring(0, joined.length.clamp(0, 600))}',
    );
    diag(
      'counts scaffold=${find.byType(Scaffold).evaluate().length} '
      'form=${find.byType(Form).evaluate().length} '
      'textField=${find.byType(TextField).evaluate().length} '
      'editableOn=${find.byType(EditableText).evaluate().length} '
      'editableAll=${find.byType(EditableText, skipOffstage: false).evaluate().length} '
      'formatted2m=${find.text('2,000,000', skipOffstage: false).evaluate().length}',
    );
    final editables = find
        .byType(EditableText, skipOffstage: false)
        .evaluate()
        .map((e) {
      final st = (e as StatefulElement).state as EditableTextState;
      final box = e.renderObject;
      final y =
          box is RenderBox && box.hasSize
              ? box.localToGlobal(Offset.zero).dy
              : -1;
      return 'edit[${y.toStringAsFixed(0)}]=[${st.textEditingValue.text}]';
    }).toList();
    final eJoined = editables.join(' | ');
    diag(
      'editables=${eJoined.substring(0, eJoined.length.clamp(0, 400))}',
    );
    String probes(Finder target, String label) {
      final parts = <String>[
        'tf=${find.ancestor(of: target, matching: find.byType(TextField)).evaluate().length}',
        'tff=${find.ancestor(of: target, matching: find.byType(TextFormField)).evaluate().length}',
        'amt=${find.ancestor(of: target, matching: find.byType(AmountField)).evaluate().length}',
        'app=${find.ancestor(of: target, matching: find.byType(AppTextField)).evaluate().length}',
        'sel=${find.ancestor(of: target, matching: find.byType(SelectField)).evaluate().length}',
        'bar=${find.ancestor(of: target, matching: find.byType(FormActionBar)).evaluate().length}',
        'sheet=${find.ancestor(of: target, matching: find.byType(BottomSheet)).evaluate().length}',
        'page=${find.ancestor(of: target, matching: find.byType(TransactionEditPage)).evaluate().length}',
      ];
      return '$label ${parts.join(' ')}';
    }
    final edCount =
        find.byType(EditableText, skipOffstage: false).evaluate().length;
    for (var i = 0; i < edCount; i++) {
      raw(
        'probe#$i '
        '${probes(find.byType(EditableText, skipOffstage: false).at(i), 'edit')}',
      );
    }
    raw('zero ${probes(find.text('0'), 'zero')}');
    final richtexts = find.byType(RichText).evaluate().map((e) {
      final box = e.renderObject;
      final y =
          box is RenderBox && box.hasSize
              ? box.localToGlobal(Offset.zero).dy
              : -1;
      final s = (e.widget as RichText).text.toPlainText();
      return 'rich[${y.toStringAsFixed(0)}]=[$s]';
    }).toList();
    final rJoined = richtexts.join(' | ');
    diag(
      'rich=${rJoined.substring(0, rJoined.length.clamp(0, 400))}',
    );

    // Cash is the default and says where the money lands.
    expect(find.text('Cash goes into the box.'), findsOneWidget);

    await tester.tap(find.text('Credit'));
    await tester.pumpAndSettle();
    // The settled-now field appears with the amount still outstanding.
    diag(
      'afterCreditTap settleField='
      '${find.widgetWithText(TextField, 'Cash received now').evaluate().length} '
      'debtHint=${find.textContaining('customer debt').evaluate().length}',
    );
    expect(find.widgetWithText(TextField, 'Cash received now'), findsOneWidget);
    expect(find.textContaining('customer debt'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.widgetWithText(TextField, 'Cash received now'),
      200,
      scrollable: formScrollable(),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Cash received now'),
      '2000000',
    );
    await tester.pumpAndSettle();
    diag('paidInFull=${find.text('Paid in full').evaluate().length}');
    expect(find.text('Paid in full'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('category chips switch the selected category', (tester) async {
    await tester.pumpWidget(
      wrap(
        const TransactionEditPage(
          initialKind: TxnKind.expense,
          autofocusAmount: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Domain and SSL'),
      200,
      scrollable: formScrollable(),
    );
    await tester.pumpAndSettle();

    Finder chip() => find
        .ancestor(
          of: find.text('Domain and SSL'),
          matching: find.byType(ChoiceChip),
        )
        .first;
    expect(tester.widget<ChoiceChip>(chip()).selected, isFalse);

    await tester.tap(chip());
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(chip()).selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a payable payment refuses to save without a contact', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        const TransactionEditPage(
          initialKind: TxnKind.payablePayment,
          autofocusAmount: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(amountField(), '5000');
    await tester.pump();
    await tester.tap(recordButton());
    await tester.pumpAndSettle();

    expect(find.text('Select a contact for this payment'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('personal scope hides the contact section', (tester) async {
    await tester.pumpWidget(
      wrap(
        const TransactionEditPage(
          initialKind: TxnKind.income,
          initialScope: TxnScope.personal,
          autofocusAmount: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Contact (optional)'), findsNothing);
    // Personal categories are offered instead (Salary is the seeded default).
    expect(find.text('Category'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Salary'),
      200,
      scrollable: formScrollable(),
    );
    expect(find.text('Salary'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
