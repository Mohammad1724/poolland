import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/format_utils.dart';
import '../core/jalali_utils.dart';
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

  static pw.Widget _t(String text,
          {bool bold = false, double size = 9, PdfColor? color, pw.TextAlign? align}) =>
      pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
          font: bold ? _bold : _regular,
          fontSize: size,
          color: color,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      );

  static pw.Widget _table(
      {required List<List<String>> rows,
      required List<double> widths,
      List<String>? headers}) {
    final headerRow = headers == null
        ? null
        : pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEEF2FF)),
            children: headers
                .map((h) => pw.Padding(
                    padding: const pw.EdgeInsets.all(5),
                    child: _t(h, bold: true, align: pw.TextAlign.left)))
                .toList(),
          );

    return pw.Table(
      border: pw.TableBorder.all(color: const PdfColor.fromInt(0xFFE2E8F0), width: 0.5),
      columnWidths: {
        for (var i = 0; i < widths.length; i++) i: pw.FlexColumnWidth(widths[i]),
      },
      children: [
        ?headerRow,
        for (final r in rows)
          pw.TableRow(
            children: r
                .map((c) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
                    child: _t(c, align: pw.TextAlign.left)))
                .toList(),
          ),
      ],
    );
  }

  static pw.Widget _box({required String label, required String value, PdfColor? color}) =>
      pw.Expanded(
        child: pw.Container(
          margin: const pw.EdgeInsets.all(3),
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: const PdfColor.fromInt(0xFFDDE3EE), width: 0.6),
            borderRadius: pw.BorderRadius.circular(6),
            color: const PdfColor.fromInt(0xFFFAFBFD),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _t(label, size: 8, color: const PdfColor.fromInt(0xFF64748B)),
              pw.SizedBox(height: 3),
              _t(value, bold: true, size: 11, color: color),
            ],
          ),
        ),
      );

  static pw.Widget _header(String businessName, String title, String subtitle) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              _t(businessName, bold: true, size: 14),
              _t('Poolland Ledger', size: 9, color: const PdfColor.fromInt(0xFF64748B)),
            ],
          ),
          pw.SizedBox(height: 2),
          _t(title, bold: true, size: 12),
          _t(subtitle, size: 9, color: const PdfColor.fromInt(0xFF64748B)),
          pw.SizedBox(height: 8),
          pw.Divider(thickness: 0.7, color: const PdfColor.fromInt(0xFFE2E8F0)),
        ],
      );

  // ---------------- Period report ----------------
  static Future<Uint8List> buildReport({
    required AppRepository repo,
    required DateTime from,
    required DateTime to,
  }) async {
    await _loadFonts();
    final s = repo.settings;
    final persian = s.persianDigits;
    final symbol = s.base.symbol;
    final summary = repo.summary(from: from, to: to);
    final byCategory = Ledger.byCategory(repo.transactions,
        repo.categories, from: from, to: to, kind: TxnKind.expense);
    final topCustomers =
        Ledger.topCustomers(repo.customers, repo.transactions, from: from, to: to, limit: 8);
    final totals = repo.totals;
    final rows = Ledger.filter(repo.transactions, from: from, to: to).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    String money(num v, {String? cur}) => Fmt.money(v,
        symbol: cur ?? symbol, persian: persian, withSymbol: false);

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: _regular, bold: _bold),
    );

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      textDirection: pw.TextDirection.ltr,
      header: (ctx) => ctx.pageNumber == 1
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: _t('${s.businessName} - Report ${J.d(from, persian: persian)} to ${J.d(to, persian: persian)}',
                  size: 8, color: const PdfColor.fromInt(0xFF64748B))),
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerLeft,
        child: _t('Page ${persian ? Fmt.toFaDigits('${ctx.pageNumber}') : ctx.pageNumber} of ${persian ? Fmt.toFaDigits('${ctx.pagesCount}') : ctx.pagesCount}',
            size: 8, color: const PdfColor.fromInt(0xFF94A3B8)),
      ),
      build: (ctx) => [
        _header(
          s.businessName,
          'Financial and performance report',
          'From ${J.dFull(from, persian: persian)} to ${J.dFull(to, persian: persian)} • Issued: ${J.d(DateTime.now(), persian: persian)}',
        ),
        pw.SizedBox(height: 10),
        pw.Row(children: [
          _box(label: 'Income (sales)', value: money(summary.income), color: const PdfColor.fromInt(0xFF16A34A)),
          _box(label: 'Expenses', value: money(summary.expense), color: const PdfColor.fromInt(0xFFDC2626)),
          _box(
              label: 'Net profit',
              value: money(summary.profit),
              color: summary.profit >= 0
                  ? const PdfColor.fromInt(0xFF16A34A)
                  : const PdfColor.fromInt(0xFFDC2626)),
        ]),
        pw.SizedBox(height: 2),
        pw.Row(children: [
          _box(label: 'Received from customers', value: money(summary.received)),
          _box(label: 'Cash received', value: money(summary.cashIn)),
          _box(label: 'Cash paid', value: money(summary.cashOut)),
        ]),
        pw.SizedBox(height: 2),
        pw.Row(children: [
          _box(label: 'Total receivables', value: money(totals.receivable)),
          _box(label: 'Total payables', value: money(totals.payable)),
          _box(label: 'Transactions', value: persian ? Fmt.toFaDigits('${summary.txnCount}') : '${summary.txnCount}'),
        ]),
        pw.SizedBox(height: 14),
        if (byCategory.isNotEmpty) ...[
          _t('Expenses by category', bold: true, size: 11),
          pw.SizedBox(height: 5),
          _table(
            headers: const ['Category', 'Amount', 'Share'],
            widths: const [2.4, 1.4, 0.8],
            rows: (byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value)))
                .map((e) => [
                      e.key,
                      money(e.value),
                      summary.expense > 0 ? Fmt.percent(e.value / summary.expense, persian: persian) : '-',
                    ])
                .toList(),
          ),
          pw.SizedBox(height: 14),
        ],
        if (topCustomers.isNotEmpty) ...[
          _t('Top customers this period', bold: true, size: 11),
          pw.SizedBox(height: 5),
          _table(
            headers: const ['Customer', 'Purchase amount'],
            widths: const [2.4, 1.6],
            rows: topCustomers.map((e) => [e.key.name, money(e.value)]).toList(),
          ),
          pw.SizedBox(height: 14),
        ],
        _t('Transaction details', bold: true, size: 11),
        pw.SizedBox(height: 5),
        if (rows.isEmpty)
          _t('No transactions were recorded in this period.', size: 9, color: const PdfColor.fromInt(0xFF64748B))
        else
          _table(
            headers: const ['Date', 'Type', 'Description', 'Contact', 'Amount', 'Currency', 'Status'],
            widths: const [1.15, 1.05, 2.2, 1.5, 1.25, 0.6, 0.95],
            rows: rows
                .map((t) => [
                      J.d(t.date, persian: persian),
                      t.kind.shortLabel,
                      t.note.isEmpty ? repo.categoryName(t.categoryId) : t.note,
                      t.customerId == null ? '-' : repo.customerName(t.customerId),
                      money(t.amount),
                      t.currency,
                      t.kind.isProfitKind ? (t.credit ? 'Credit' : 'Cash') : '-',
                    ])
                .toList(),
          ),
      ],
    ));
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
    final persian = s.persianDigits;
    final symbol = s.base.symbol;
    final txns = repo
        .txnsOfCustomer(customer.id)
        .where((t) => Ledger.inRange(t.date, from, to))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final balance = repo.balanceOf(customer);

    String money(num v, {String? cur}) => Fmt.money(v,
        symbol: cur ?? symbol, persian: persian, withSymbol: false);

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
        J.d(t.date, persian: persian),
        t.note.isEmpty ? t.kind.label : t.note,
        effect > 0 ? money(effect) : '-',
        effect < 0 ? money(-effect) : '-',
        money(running),
      ]);
    }

    final doc = pw.Document(theme: pw.ThemeData.withFont(base: _regular, bold: _bold));
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      textDirection: pw.TextDirection.ltr,
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerLeft,
        child: _t('Generated with Poolland Ledger — page ${persian ? Fmt.toFaDigits('${ctx.pageNumber}') : ctx.pageNumber}',
            size: 8, color: const PdfColor.fromInt(0xFF94A3B8)),
      ),
      build: (ctx) => [
        _header(
          s.businessName,
          'Statement for ${customer.name}',
          'Period: ${J.d(from, persian: persian)} to ${J.d(to, persian: persian)} • Issued: ${J.d(DateTime.now(), persian: persian)}',
        ),
        if (customer.phone.isNotEmpty || customer.note.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          _t([
            if (customer.phone.isNotEmpty) 'Phone: ${persian ? Fmt.toFaDigits(customer.phone) : customer.phone}',
            if (customer.note.isNotEmpty) 'Note: ${customer.note}',
          ].join('   •   '), size: 9, color: const PdfColor.fromInt(0xFF64748B)),
        ],
        pw.SizedBox(height: 10),
        pw.Row(children: [
          _box(label: 'Opening balance', value: money(opening)),
          _box(label: 'Total debits', value: money(debitTotal)),
          _box(label: 'Total credits', value: money(creditTotal)),
        ]),
        pw.SizedBox(height: 2),
        pw.Row(children: [
          _box(label: 'Transactions', value: persian ? Fmt.toFaDigits('${txns.length}') : '${txns.length}'),
          _box(
              label: balance >= 0 ? 'Current balance (debit)' : 'Current balance (credit)',
              value: money(balance.abs()),
              color: balance >= 0
                  ? const PdfColor.fromInt(0xFFDC2626)
                  : const PdfColor.fromInt(0xFF16A34A)),
        ]),
        pw.SizedBox(height: 12),
        if (rows.isEmpty)
          _t('No transactions were recorded in this period.', size: 9, color: const PdfColor.fromInt(0xFF64748B))
        else
          _table(
            headers: const ['Date', 'Description', 'Debit', 'Credit', 'Balance'],
            widths: const [1.1, 2.6, 1.2, 1.2, 1.2],
            rows: rows,
          ),
        pw.SizedBox(height: 10),
        _t('Positive balance = customer owes you  |  Negative balance = you owe the customer',
            size: 8, color: const PdfColor.fromInt(0xFF64748B)),
      ],
    ));
    return doc.save();
  }
}
