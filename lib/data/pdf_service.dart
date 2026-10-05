import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/format_utils.dart';
import '../core/jalali_utils.dart';
import '../core/localization.dart';
import 'ledger.dart';
import 'models.dart';
import 'repository.dart';

/// Generate PDF reports and customer statements.
class PdfService {
  static pw.Font? _regular;
  static pw.Font? _bold;

  static Future<void> _loadFonts() async {
    if (_regular != null) return;
    final r = await rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf');
    final b = await rootBundle.load('assets/fonts/Vazirmatn-Bold.ttf');
    _regular = pw.Font.ttf(r);
    _bold = pw.Font.ttf(b);
  }

  static String _kindLabel(TxnKind kind, {bool short = false}) => short
      ? switch (kind) {
          TxnKind.income => 'Income',
          TxnKind.expense => 'Expense',
          TxnKind.receive => 'Receive',
          TxnKind.refund => 'Refund',
          TxnKind.payablePayment => 'Paid out',
        }
      : switch (kind) {
          TxnKind.income => 'Sale / income',
          TxnKind.expense => 'Expense',
          TxnKind.receive => 'Customer payment',
          TxnKind.refund => 'Refund to customer',
          TxnKind.payablePayment => 'Payable settlement',
        };

  static pw.Widget _t(
    String text, {
    bool bold = false,
    double size = 9,
    PdfColor? color,
    pw.TextAlign? align,
    String? languageCode,
    bool localize = true,
  }) => pw.Text(
    localize ? AppLocalization.text(text, languageCode: languageCode) : text,
    textAlign: align,
    style: pw.TextStyle(
      font: bold ? _bold : _regular,
      fontSize: size,
      color: color,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    ),
  );

  static pw.Widget _table({
    required List<List<String>> rows,
    required List<double> widths,
    List<String>? headers,
    String? languageCode,
  }) {
    final headerRow = headers == null
        ? null
        : pw.TableRow(
            decoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFEEF2FF),
            ),
            children: headers
                .map(
                  (h) => pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: _t(
                      h,
                      bold: true,
                      align: pw.TextAlign.start,
                      languageCode: languageCode,
                    ),
                  ),
                )
                .toList(),
          );

    return pw.Table(
      border: pw.TableBorder.all(
        color: const PdfColor.fromInt(0xFFE2E8F0),
        width: 0.5,
      ),
      columnWidths: {
        for (var i = 0; i < widths.length; i++)
          i: pw.FlexColumnWidth(widths[i]),
      },
      children: [
        ?headerRow,
        for (final r in rows)
          pw.TableRow(
            children: r
                .map(
                  (c) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 4,
                    ),
                    child: _t(
                      c,
                      align: pw.TextAlign.start,
                      languageCode: languageCode,
                      localize: false,
                    ),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  static pw.Widget _box({
    required String label,
    required String value,
    PdfColor? color,
    String? languageCode,
  }) => pw.Expanded(
    child: pw.Container(
      margin: const pw.EdgeInsets.all(3),
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(
          color: const PdfColor.fromInt(0xFFDDE3EE),
          width: 0.6,
        ),
        borderRadius: pw.BorderRadius.circular(6),
        color: const PdfColor.fromInt(0xFFFAFBFD),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _t(
            label,
            size: 8,
            color: const PdfColor.fromInt(0xFF64748B),
            languageCode: languageCode,
          ),
          pw.SizedBox(height: 3),
          _t(
            value,
            bold: true,
            size: 11,
            color: color,
            languageCode: languageCode,
            localize: false,
          ),
        ],
      ),
    ),
  );

  static pw.Widget _header(
    String businessName,
    String title,
    String subtitle, {
    String? languageCode,
  }) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _t(
            businessName,
            bold: true,
            size: 14,
            languageCode: languageCode,
            localize: false,
          ),
          _t(
            'Poolland Ledger',
            size: 9,
            color: const PdfColor.fromInt(0xFF64748B),
            languageCode: languageCode,
          ),
        ],
      ),
      pw.SizedBox(height: 2),
      _t(title, bold: true, size: 12, languageCode: languageCode),
      _t(
        subtitle,
        size: 9,
        color: const PdfColor.fromInt(0xFF64748B),
        languageCode: languageCode,
      ),
      pw.SizedBox(height: 8),
      pw.Divider(thickness: 0.7, color: const PdfColor.fromInt(0xFFE2E8F0)),
    ],
  );

  // ---------------- Period report ----------------
  static Future<Uint8List> buildReport({
    required AppRepository repo,
    required DateTime from,
    required DateTime to,
    TxnScope? scope,
  }) async {
    await _loadFonts();
    final s = repo.settings;
    final languageCode = s.languageCode;
    final persianDigits = s.persianDigits;
    final isPersian = languageCode == 'fa';
    final reportScope = scope ?? repo.scopeFilter;
    final includesBusinessBalances = reportScope != TxnScope.personal;
    final scopedTransactions = repo.scopeTxns(reportScope);
    final symbol = AppLocalization.text(
      s.base.symbol,
      languageCode: languageCode,
    );

    String tr(String source) =>
        AppLocalization.text(source, languageCode: languageCode);
    String trArgs(String source, Map<String, Object?> values) =>
        AppLocalization.format(source, values, languageCode: languageCode);
    pw.Widget pdfText(
      String text, {
      bool bold = false,
      double size = 9,
      PdfColor? color,
      pw.TextAlign? align,
      bool localize = true,
    }) => _t(
      text,
      bold: bold,
      size: size,
      color: color,
      align: align,
      languageCode: languageCode,
      localize: localize,
    );
    pw.Widget pdfBox({
      required String label,
      required String value,
      PdfColor? color,
    }) => _box(
      label: label,
      value: value,
      color: color,
      languageCode: languageCode,
    );
    pw.Widget pdfHeader(String businessName, String title, String subtitle) =>
        _header(businessName, title, subtitle, languageCode: languageCode);
    pw.Widget pdfTable({
      required List<List<String>> rows,
      required List<double> widths,
      List<String>? headers,
    }) => _table(
      rows: rows,
      widths: widths,
      headers: headers,
      languageCode: languageCode,
    );

    final summary = repo.summary(from: from, to: to, scope: reportScope);
    final incomeByCategory = Ledger.byCategory(
      scopedTransactions,
      repo.categories,
      from: from,
      to: to,
      kind: TxnKind.income,
      scope: reportScope,
    );
    final byCategory = Ledger.byCategory(
      scopedTransactions,
      repo.categories,
      from: from,
      to: to,
      kind: TxnKind.expense,
      scope: reportScope,
    );
    final topCustomers = Ledger.topCustomers(
      repo.customers,
      scopedTransactions,
      from: from,
      to: to,
      limit: 8,
      scope: reportScope,
    );
    final totals = repo.totals;
    final rows = Ledger.filter(
      scopedTransactions,
      from: from,
      to: to,
      scope: reportScope,
    ).toList()..sort((a, b) => b.date.compareTo(a.date));

    String money(num v, {String? cur}) => Fmt.money(
      v,
      symbol: cur == null
          ? symbol
          : AppLocalization.text(cur, languageCode: languageCode),
      persian: persianDigits,
      withSymbol: false,
    );

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: _regular, bold: _bold),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        textDirection: isPersian ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        header: (ctx) => ctx.pageNumber == 1
            ? pw.SizedBox()
            : pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pdfText(
                  trArgs('{business} — Report {from} to {to}', {
                    'business': s.businessName,
                    'from': J.d(from, persian: persianDigits),
                    'to': J.d(to, persian: persianDigits),
                  }),
                  size: 8,
                  color: const PdfColor.fromInt(0xFF64748B),
                ),
              ),
        footer: (ctx) => pw.Container(
          alignment: isPersian
              ? pw.Alignment.centerRight
              : pw.Alignment.centerLeft,
          child: pdfText(
            trArgs('Page {page} of {pages}', {
              'page': persianDigits
                  ? Fmt.toFaDigits('${ctx.pageNumber}')
                  : '${ctx.pageNumber}',
              'pages': persianDigits
                  ? Fmt.toFaDigits('${ctx.pagesCount}')
                  : '${ctx.pagesCount}',
            }),
            size: 8,
            color: const PdfColor.fromInt(0xFF94A3B8),
          ),
        ),
        build: (ctx) => [
          pdfHeader(
            s.businessName,
            'Financial and performance report',
            trArgs('{from} to {to} • Scope: {scope} • Issued: {issued}', {
              'from': J.dFull(from, persian: persianDigits),
              'to': J.dFull(to, persian: persianDigits),
              'scope': tr(
                reportScope == null
                    ? 'All'
                    : reportScope == TxnScope.business
                    ? 'Business'
                    : 'Personal',
              ),
              'issued': J.d(DateTime.now(), persian: persianDigits),
            }),
          ),
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              pdfBox(
                label: 'Income received',
                value: money(summary.income),
                color: const PdfColor.fromInt(0xFF16A34A),
              ),
              pdfBox(
                label: 'Expenses',
                value: money(summary.expense),
                color: const PdfColor.fromInt(0xFFDC2626),
              ),
              pdfBox(
                label: 'Net profit',
                value: money(summary.profit),
                color: summary.profit >= 0
                    ? const PdfColor.fromInt(0xFF16A34A)
                    : const PdfColor.fromInt(0xFFDC2626),
              ),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Row(
            children: [
              if (includesBusinessBalances)
                pdfBox(
                  label: 'Received from customers',
                  value: money(summary.received),
                ),
              pdfBox(label: 'Cash received', value: money(summary.cashIn)),
              pdfBox(label: 'Cash paid', value: money(summary.cashOut)),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Row(
            children: [
              if (includesBusinessBalances)
                pdfBox(
                  label: 'Business receivables',
                  value: money(totals.receivable),
                ),
              if (includesBusinessBalances)
                pdfBox(
                  label: 'Business payables',
                  value: money(totals.payable),
                ),
              pdfBox(
                label: 'Transactions',
                value: persianDigits
                    ? Fmt.toFaDigits('${summary.txnCount}')
                    : '${summary.txnCount}',
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          if (incomeByCategory.isNotEmpty) ...[
            pdfText('Income sources', bold: true, size: 11),
            pw.SizedBox(height: 5),
            pdfTable(
              headers: const ['Category', 'Amount', 'Share'],
              widths: const [2.4, 1.4, 0.8],
              rows:
                  (incomeByCategory.entries.toList()
                        ..sort((a, b) => b.value.compareTo(a.value)))
                      .map(
                        (e) => [
                          e.key,
                          money(e.value),
                          summary.income > 0
                              ? Fmt.percent(
                                  e.value / summary.income,
                                  persian: persianDigits,
                                )
                              : '-',
                        ],
                      )
                      .toList(),
            ),
            pw.SizedBox(height: 14),
          ],
          if (byCategory.isNotEmpty) ...[
            pdfText('Expenses by category', bold: true, size: 11),
            pw.SizedBox(height: 5),
            pdfTable(
              headers: const ['Category', 'Amount', 'Share'],
              widths: const [2.4, 1.4, 0.8],
              rows:
                  (byCategory.entries.toList()
                        ..sort((a, b) => b.value.compareTo(a.value)))
                      .map(
                        (e) => [
                          e.key,
                          money(e.value),
                          summary.expense > 0
                              ? Fmt.percent(
                                  e.value / summary.expense,
                                  persian: persianDigits,
                                )
                              : '-',
                        ],
                      )
                      .toList(),
            ),
            pw.SizedBox(height: 14),
          ],
          if (includesBusinessBalances && topCustomers.isNotEmpty) ...[
            pdfText('Top customers this period', bold: true, size: 11),
            pw.SizedBox(height: 5),
            pdfTable(
              headers: const ['Customer', 'Purchase amount'],
              widths: const [2.4, 1.6],
              rows: topCustomers
                  .map((e) => [e.key.name, money(e.value)])
                  .toList(),
            ),
            pw.SizedBox(height: 14),
          ],
          pdfText('Transaction details', bold: true, size: 11),
          pw.SizedBox(height: 5),
          if (rows.isEmpty)
            pdfText(
              'No transactions were recorded in this period.',
              size: 9,
              color: const PdfColor.fromInt(0xFF64748B),
            )
          else
            pdfTable(
              headers: const [
                'Date',
                'Type',
                'Description',
                'Contact',
                'Amount',
                'Currency',
                'Status',
              ],
              widths: const [1.15, 1.05, 2.2, 1.5, 1.25, 0.6, 0.95],
              rows: rows
                  .map(
                    (t) => [
                      J.d(t.date, persian: persianDigits),
                      tr(_kindLabel(t.kind, short: true)),
                      t.note.isEmpty ? repo.categoryName(t.categoryId) : t.note,
                      t.customerId == null
                          ? '-'
                          : repo.customerName(t.customerId),
                      money(t.amount),
                      t.currency,
                      t.kind.isProfitKind
                          ? tr(t.credit ? 'Credit' : 'Cash')
                          : '-',
                    ],
                  )
                  .toList(),
            ),
        ],
      ),
    );
    return doc.save();
  }

  // ---------------- Customer statement ----------------
  static Future<Uint8List> buildCustomerStatement({
    required AppRepository repo,
    required Customer customer,
    required DateTime from,
    required DateTime to,
  }) async {
    await _loadFonts();
    final s = repo.settings;
    final languageCode = s.languageCode;
    final persianDigits = s.persianDigits;
    final isPersian = languageCode == 'fa';
    final symbol = AppLocalization.text(
      s.base.symbol,
      languageCode: languageCode,
    );
    String tr(String source) =>
        AppLocalization.text(source, languageCode: languageCode);
    String trArgs(String source, Map<String, Object?> values) =>
        AppLocalization.format(source, values, languageCode: languageCode);
    pw.Widget pdfText(
      String text, {
      bool bold = false,
      double size = 9,
      PdfColor? color,
      pw.TextAlign? align,
      bool localize = true,
    }) => _t(
      text,
      bold: bold,
      size: size,
      color: color,
      align: align,
      languageCode: languageCode,
      localize: localize,
    );
    pw.Widget pdfBox({
      required String label,
      required String value,
      PdfColor? color,
    }) => _box(
      label: label,
      value: value,
      color: color,
      languageCode: languageCode,
    );
    pw.Widget pdfHeader(String businessName, String title, String subtitle) =>
        _header(businessName, title, subtitle, languageCode: languageCode);
    pw.Widget pdfTable({
      required List<List<String>> rows,
      required List<double> widths,
      List<String>? headers,
    }) => _table(
      rows: rows,
      widths: widths,
      headers: headers,
      languageCode: languageCode,
    );
    final txns =
        repo
            .txnsOfCustomer(customer.id)
            .where((t) => Ledger.inRange(t.date, from, to))
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));
    final balance = repo.balanceOf(customer);

    String money(num v, {String? cur}) => Fmt.money(
      v,
      symbol: cur == null
          ? symbol
          : AppLocalization.text(cur, languageCode: languageCode),
      persian: persianDigits,
      withSymbol: false,
    );

    // Opening balance = initial balance plus all effects before the period.
    var running = customer.openingBalance;
    for (final t in repo.txnsOfCustomer(customer.id)) {
      if (t.date.isBefore(J.startOfDay(from))) {
        running += Ledger.balanceEffect(t);
      }
    }
    final opening = running;

    final rows = <List<String>>[];
    var debitTotal = 0.0, creditTotal = 0.0;
    for (final t in txns) {
      final effect = Ledger.balanceEffect(t);
      running += effect;
      if (effect > 0) {
        debitTotal += effect;
      } else {
        creditTotal += -effect;
      }
      rows.add([
        J.d(t.date, persian: persianDigits),
        t.note.isEmpty ? tr(_kindLabel(t.kind)) : t.note,
        effect > 0 ? money(effect) : '-',
        effect < 0 ? money(-effect) : '-',
        money(running),
      ]);
    }

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: _regular, bold: _bold),
    );
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        textDirection: isPersian ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        footer: (ctx) => pw.Container(
          alignment: isPersian
              ? pw.Alignment.centerRight
              : pw.Alignment.centerLeft,
          child: pdfText(
            trArgs('Generated with Poolland Ledger — page {page}', {
              'page': persianDigits
                  ? Fmt.toFaDigits('${ctx.pageNumber}')
                  : '${ctx.pageNumber}',
            }),
            size: 8,
            color: const PdfColor.fromInt(0xFF94A3B8),
          ),
        ),
        build: (ctx) => [
          pdfHeader(
            s.businessName,
            trArgs('Statement for {customer}', {'customer': customer.name}),
            trArgs('Period: {from} to {to} • Issued: {issued}', {
              'from': J.d(from, persian: persianDigits),
              'to': J.d(to, persian: persianDigits),
              'issued': J.d(DateTime.now(), persian: persianDigits),
            }),
          ),
          if (customer.phone.isNotEmpty || customer.note.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pdfText(
              [
                if (customer.phone.isNotEmpty)
                  trArgs('Phone: {value}', {
                    'value': persianDigits
                        ? Fmt.toFaDigits(customer.phone)
                        : customer.phone,
                  }),
                if (customer.note.isNotEmpty)
                  trArgs('Note: {value}', {'value': customer.note}),
              ].join('   •   '),
              size: 9,
              color: const PdfColor.fromInt(0xFF64748B),
            ),
          ],
          pw.SizedBox(height: 10),
          pw.Row(
            children: [
              pdfBox(label: 'Opening balance', value: money(opening)),
              pdfBox(label: 'Total debits', value: money(debitTotal)),
              pdfBox(label: 'Total credits', value: money(creditTotal)),
            ],
          ),
          pw.SizedBox(height: 2),
          pw.Row(
            children: [
              pdfBox(
                label: 'Transactions',
                value: persianDigits
                    ? Fmt.toFaDigits('${txns.length}')
                    : '${txns.length}',
              ),
              pdfBox(
                label: balance >= 0
                    ? 'Current balance (debit)'
                    : 'Current balance (credit)',
                value: money(balance.abs()),
                color: balance >= 0
                    ? const PdfColor.fromInt(0xFFDC2626)
                    : const PdfColor.fromInt(0xFF16A34A),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          if (rows.isEmpty)
            pdfText(
              'No transactions were recorded in this period.',
              size: 9,
              color: const PdfColor.fromInt(0xFF64748B),
            )
          else
            pdfTable(
              headers: const [
                'Date',
                'Description',
                'Debit',
                'Credit',
                'Balance',
              ],
              widths: const [1.1, 2.6, 1.2, 1.2, 1.2],
              rows: rows,
            ),
          pw.SizedBox(height: 10),
          pdfText(
            'Positive balance = customer owes you  |  Negative balance = you owe the customer',
            size: 8,
            color: const PdfColor.fromInt(0xFF64748B),
          ),
        ],
      ),
    );
    return doc.save();
  }
}
