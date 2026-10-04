import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/format_utils.dart';
import '../core/jalali_utils.dart';
import 'ledger.dart';
import 'models.dart';
import 'repository.dart';

/// ساخت گزارش PDF و صورت‌حساب مشتری
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
                    child: _t(h, bold: true, align: pw.TextAlign.right)))
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
                    child: _t(c, align: pw.TextAlign.right)))
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
              _t('دفتر وی‌پی‌ان', size: 9, color: const PdfColor.fromInt(0xFF64748B)),
            ],
          ),
          pw.SizedBox(height: 2),
          _t(title, bold: true, size: 12),
          _t(subtitle, size: 9, color: const PdfColor.fromInt(0xFF64748B)),
          pw.SizedBox(height: 8),
          pw.Divider(thickness: 0.7, color: const PdfColor.fromInt(0xFFE2E8F0)),
        ],
      );

  // ---------------- گزارش دوره ----------------
  static Future<Uint8List> buildReport({
    required AppRepository repo,
    required DateTime from,
    required DateTime to,
    String? bookId,
  }) async {
    await _loadFonts();
    final s = repo.settings;
    final persian = s.persianDigits;
    final symbol = s.base.symbol;
    final book = bookId ?? repo.bookFilter;
    final bookName = book == null ? 'همه‌ی دفترها' : s.book(book).name;
    final showBusiness = book == null || book == BookIds.business;
    final summary = Ledger.summarize(repo.transactions, from: from, to: to, bookId: book);
    final byCategory = Ledger.byCategory(repo.transactions, repo.categories,
        from: from, to: to, kind: TxnKind.expense, bookId: book);
    final topCustomers = showBusiness
        ? Ledger.topCustomers(repo.customers, repo.transactions,
            from: from, to: to, limit: 8, bookId: book)
        : <MapEntry<Customer, double>>[];
    final totals = repo.totals;
    final rows = Ledger.filter(repo.transactions, from: from, to: to, bookId: book).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    String money(num v, {String? cur}) => Fmt.money(v,
        symbol: cur ?? symbol, persian: persian, withSymbol: false);

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: _regular, bold: _bold),
    );

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      textDirection: pw.TextDirection.rtl,
      header: (ctx) => ctx.pageNumber == 1
          ? pw.SizedBox()
          : pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: _t('${s.businessName} - گزارش ${J.d(from, persian: persian)} تا ${J.d(to, persian: persian)}',
                  size: 8, color: const PdfColor.fromInt(0xFF64748B))),
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        child: _t('صفحه ${persian ? Fmt.toFaDigits('${ctx.pageNumber}') : ctx.pageNumber} از ${persian ? Fmt.toFaDigits('${ctx.pagesCount}') : ctx.pagesCount}',
            size: 8, color: const PdfColor.fromInt(0xFF94A3B8)),
      ),
      build: (ctx) => [
        _header(
          s.businessName,
          'گزارش حساب و عملکرد — $bookName',
          'از ${J.dFull(from, persian: persian)}  تا  ${J.dFull(to, persian: persian)}  •  تاریخ صدور: ${J.d(DateTime.now(), persian: persian)}',
        ),
        pw.SizedBox(height: 10),
        pw.Row(children: [
          _box(label: 'درآمد (فروش)', value: money(summary.income), color: const PdfColor.fromInt(0xFF16A34A)),
          _box(label: 'هزینه', value: money(summary.expense), color: const PdfColor.fromInt(0xFFDC2626)),
          _box(
              label: 'سود خالص',
              value: money(summary.profit),
              color: summary.profit >= 0
                  ? const PdfColor.fromInt(0xFF16A34A)
                  : const PdfColor.fromInt(0xFFDC2626)),
        ]),
        pw.SizedBox(height: 2),
        pw.Row(children: [
          _box(label: 'وصولی از مشتری‌ها', value: money(summary.received)),
          _box(label: 'نقد دریافتی', value: money(summary.cashIn)),
          _box(label: 'نقد پرداختی', value: money(summary.cashOut)),
        ]),
        if (showBusiness) ...[
          pw.SizedBox(height: 2),
          pw.Row(children: [
            _box(label: 'جمع طلب از مشتری‌ها', value: money(totals.receivable)),
            _box(label: 'جمع بدهی ما', value: money(totals.payable)),
            _box(label: 'تعداد تراکنش', value: persian ? Fmt.toFaDigits('${summary.txnCount}') : '${summary.txnCount}'),
          ]),
        ],
        if (book == null && s.books.length > 1) ...[
          pw.SizedBox(height: 12),
          _t('سود هر دفتر', bold: true, size: 11),
          pw.SizedBox(height: 5),
          _table(
            headers: const ['دفتر', 'درآمد', 'هزینه', 'سود'],
            widths: const [1.6, 1.3, 1.3, 1.3],
            rows: [
              for (final e in repo.summaryByBook(from: from, to: to))
                [e.key.name, money(e.value.income), money(e.value.expense), money(e.value.profit)],
            ],
          ),
        ],
        pw.SizedBox(height: 14),
        if (byCategory.isNotEmpty) ...[
          _t('هزینه‌ها به تفکیک دسته‌بندی', bold: true, size: 11),
          pw.SizedBox(height: 5),
          _table(
            headers: const ['دسته', 'مبلغ', 'سهم'],
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
          _t('مشتریان برتر این دوره', bold: true, size: 11),
          pw.SizedBox(height: 5),
          _table(
            headers: const ['مشتری', 'مبلغ خرید'],
            widths: const [2.4, 1.6],
            rows: topCustomers.map((e) => [e.key.name, money(e.value)]).toList(),
          ),
          pw.SizedBox(height: 14),
        ],
        _t('ریز تراکنش‌ها', bold: true, size: 11),
        pw.SizedBox(height: 5),
        if (rows.isEmpty)
          _t('در این بازه تراکنشی ثبت نشده است.', size: 9, color: const PdfColor.fromInt(0xFF64748B))
        else
          _table(
            headers: const ['تاریخ', 'دفتر', 'نوع', 'شرح', 'طرف حساب', 'مبلغ', 'وضعیت'],
            widths: const [1.1, 0.95, 1.0, 2.1, 1.4, 1.2, 0.9],
            rows: rows
                .map((t) => [
                      J.d(t.date, persian: persian),
                      s.book(t.bookId).name,
                      t.kind.shortLabel,
                      t.note.isEmpty ? repo.categoryName(t.categoryId) : t.note,
                      t.customerId == null ? '-' : repo.customerName(t.customerId),
                      money(t.amount),
                      t.kind.isProfitKind ? (t.credit ? 'نسیه' : 'نقدی') : '-',
                    ])
                .toList(),
          ),
      ],
    ));
    return doc.save();
  }

  // ---------------- صورت‌حساب مشتری ----------------
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

    // مانده‌ی ابتدای دوره = بدهی اولیه + همه‌ی اثرها قبل از بازه
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
      textDirection: pw.TextDirection.rtl,
      footer: (ctx) => pw.Container(
        alignment: pw.Alignment.centerRight,
        child: _t('این صورت‌حساب با «دفتر وی‌پی‌ان» ساخته شده است — صفحه ${persian ? Fmt.toFaDigits('${ctx.pageNumber}') : ctx.pageNumber}',
            size: 8, color: const PdfColor.fromInt(0xFF94A3B8)),
      ),
      build: (ctx) => [
        _header(
          s.businessName,
          'صورت‌حساب ${customer.name}',
          'دوره: ${J.d(from, persian: persian)} تا ${J.d(to, persian: persian)}  •  تاریخ صدور: ${J.d(DateTime.now(), persian: persian)}',
        ),
        if (customer.phone.isNotEmpty || customer.note.isNotEmpty) ...[
          pw.SizedBox(height: 6),
          _t([
            if (customer.phone.isNotEmpty) 'تلفن: ${persian ? Fmt.toFaDigits(customer.phone) : customer.phone}',
            if (customer.note.isNotEmpty) 'یادداشت: ${customer.note}',
          ].join('   •   '), size: 9, color: const PdfColor.fromInt(0xFF64748B)),
        ],
        pw.SizedBox(height: 10),
        pw.Row(children: [
          _box(label: 'مانده ابتدای دوره', value: money(opening)),
          _box(label: 'جمع بدهکار دوره', value: money(debitTotal)),
          _box(label: 'جمع بستانکار دوره', value: money(creditTotal)),
        ]),
        pw.SizedBox(height: 2),
        pw.Row(children: [
          _box(label: 'تعداد تراکنش', value: persian ? Fmt.toFaDigits('${txns.length}') : '${txns.length}'),
          _box(
              label: balance >= 0 ? 'مانده فعلی (بدهکار)' : 'مانده فعلی (بستانکار)',
              value: money(balance.abs()),
              color: balance >= 0
                  ? const PdfColor.fromInt(0xFFDC2626)
                  : const PdfColor.fromInt(0xFF16A34A)),
        ]),
        pw.SizedBox(height: 12),
        if (rows.isEmpty)
          _t('در این بازه تراکنشی ثبت نشده است.', size: 9, color: const PdfColor.fromInt(0xFF64748B))
        else
          _table(
            headers: const ['تاریخ', 'شرح', 'بدهکار', 'بستانکار', 'مانده'],
            widths: const [1.1, 2.6, 1.2, 1.2, 1.2],
            rows: rows,
          ),
        pw.SizedBox(height: 10),
        _t('مانده مثبت = بدهی مشتری به شما  |  مانده منفی = طلب مشتری از شما',
            size: 8, color: const PdfColor.fromInt(0xFF64748B)),
      ],
    ));
    return doc.save();
  }
}
