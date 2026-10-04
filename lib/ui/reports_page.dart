import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/backup.dart';
import '../core/format_utils.dart';
import '../core/jalali_utils.dart';
import '../core/money.dart';
import '../data/ledger.dart';
import '../data/models.dart';
import '../data/pdf_service.dart';
import '../data/repository.dart';
import 'customer_detail_page.dart';
import 'widgets/common_charts.dart';
import 'widgets/widgets.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

enum _Range { thisMonth, lastMonth, threeMonths, sixMonths, thisYear, all }

class _ReportsPageState extends State<ReportsPage> {
  _Range _range = _Range.thisMonth;
  bool _busy = false;

  (DateTime, DateTime) _bounds(AppRepository repo) {
    final now = DateTime.now();
    switch (_range) {
      case _Range.thisMonth:
        return (J.startOfMonth(now), J.endOfMonth(now));
      case _Range.lastMonth:
        final m = J.addMonths(now, -1);
        return (J.startOfMonth(m), J.endOfMonth(m));
      case _Range.threeMonths:
        return (J.startOfMonth(J.addMonths(now, -2)), J.endOfMonth(now));
      case _Range.sixMonths:
        return (J.startOfMonth(J.addMonths(now, -5)), J.endOfMonth(now));
      case _Range.thisYear:
        return (J.startOfYear(now), J.endOfMonth(now));
      case _Range.all:
        if (repo.transactions.isEmpty) return (J.startOfMonth(now), J.endOfMonth(now));
        final first = repo.transactions
            .map((t) => t.date)
            .reduce((a, b) => a.isBefore(b) ? a : b);
        return (J.dateOnly(first), J.endOfMonth(now));
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final (from, to) = _bounds(repo);
    final scope = repo.scopeFilter;
    final s = repo.summary(from: from, to: to, scope: scope);
    final monthsSpan = _monthsBetween(from, to);
    final series = Ledger.monthlySeries(repo.transactions,
        months: monthsSpan, endMonth: to, scope: scope)
        .where((p) => !p.monthStart.isBefore(J.startOfMonth(from)))
        .toList();
    final incomeCats = Ledger.byCategory(repo.transactions, repo.categories,
        from: from, to: to, kind: TxnKind.income, scope: scope);
    final expenseCats = Ledger.byCategory(repo.transactions, repo.categories,
        from: from, to: to, kind: TxnKind.expense, scope: scope);
    final top = Ledger.topCustomers(repo.customers, repo.transactions,
        from: from, to: to, limit: 6, scope: scope);
    final debtors = repo.debtorsList();
    final margin = s.income > 0 ? s.profit / s.income : 0.0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final opt in <TxnScope?>[
                null,
                TxnScope.business,
                TxnScope.personal
              ])
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: ChoiceChip(
                    label: Text(opt == null ? 'همه' : opt.label,
                        style: const TextStyle(fontSize: 12)),
                    showCheckmark: false,
                    selected: repo.scopeFilter == opt,
                    onSelected: (_) => repo.setScopeFilter(opt),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final r in _Range.values) ...[
                ChoiceChip(
                  label: Text(_rangeLabel(r)),
                  showCheckmark: false,
                  selected: _range == r,
                  onSelected: (_) => setState(() => _range = r),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text('${J.d(from)} تا ${J.d(to)}',
            style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.6))),
        const SizedBox(height: 12),

        // خلاصه
        CardBox(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                      child: _kv(context, 'درآمد (فروش)', Money.text(s.income),
                          const Color(0xFF16A34A))),
                  Expanded(
                      child: _kv(context, 'هزینه', Money.text(s.expense),
                          const Color(0xFFE11D48))),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _kv(context, 'سود خالص', Money.text(s.profit),
                          s.profit >= 0 ? const Color(0xFF16A34A) : const Color(0xFFE11D48))),
                  Expanded(
                      child: _kv(context, 'حاشیه سود', Fmt.percent(margin),
                          const Color(0xFF7C3AED))),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _kv(context, 'وصولی از مشتری‌ها', Money.text(s.received),
                          const Color(0xFF0F766E))),
                  Expanded(
                      child: _kv(context, 'نقد پرداختی',
                          Money.text(s.cashOut), const Color(0xFFB45309))),
                ],
              ),
              const SizedBox(height: 12),
              Divider(color: Theme.of(context).dividerColor),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _kv(context, 'طلبات (کل)', Money.text(repo.totals.receivable),
                        const Color(0xFF0F766E)),
                  ),
                  Expanded(
                    child: _kv(context, 'بدهی (کل)', Money.text(repo.totals.payable),
                        const Color(0xFF2563EB)),
                  ),
                ],
              ),
            ],
          ),
        ),

        // نمودار ماهانه
        if (series.length > 1) ...[
          const SectionTitle('درآمد و هزینه ماهانه', icon: Icons.bar_chart_rounded),
          CardBox(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
            child: SizedBox(height: 190, child: MonthlyBarChart(points: series)),
          ),
        ],

        // نمودار دسته‌بندی هزینه
        if (expenseCats.isNotEmpty) ...[
          const SectionTitle('هزینه‌ها به تفکیک دسته‌بندی', icon: Icons.pie_chart_outline_rounded),
          CardBox(child: CategoryPieChart(data: expenseCats, size: 150)),
        ],

        // تفکیک درآمد
        if (incomeCats.isNotEmpty) ...[
          const SectionTitle('منابع درآمد', icon: Icons.trending_up_rounded),
          CardBox(
            child: Column(
              children: [
                for (final e in (incomeCats.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value))))
                  InfoRow(
                    e.key,
                    Text(
                      '${Money.text(e.value)}  ${s.income > 0 ? '(${Fmt.percent(e.value / s.income)})' : ''}',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
        ],

        // مشتریان برتر
        if (top.isNotEmpty) ...[
          const SectionTitle('مشتریان برتر این دوره', icon: Icons.emoji_events_outlined),
          CardBox(
            child: Column(
              children: [
                for (var i = 0; i < top.length; i++)
                  InfoRow(
                    '${Fmt.toFaDigits('${i + 1}')}. ${top[i].key.name}',
                    MoneyText(top[i].value),
                  ),
              ],
            ),
          ),
        ],

        // بدهکاران
        const SectionTitle('بدهکاران', icon: Icons.account_balance_wallet_outlined),
        if (debtors.isEmpty)
          const CardBox(child: Text('همه‌ی حساب‌ها تسویه است ✅', style: TextStyle(fontSize: 12.5)))
        else
          Column(
            children: [
              for (final e in debtors)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: CardBox(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => CustomerDetailPage(customer: e.key))),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(e.key.name,
                              style: const TextStyle(
                                  fontSize: 13.5, fontWeight: FontWeight.w600)),
                        ),
                        MoneyText(e.value,
                            style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF0F766E))),
                      ],
                    ),
                  ),
                ),
            ],
          ),

        // خروجی‌ها
        const SectionTitle('خروجی گرفتن', icon: Icons.ios_share_rounded),
        CardBox(
          child: Column(
            children: [
              _exportTile(
                context,
                icon: Icons.picture_as_pdf_rounded,
                title: 'گزارش PDF',
                subtitle: 'گزارش کامل دوره با نمودار و تراکنش‌ها',
                onTap: () => _exportPdf(repo, from, to),
              ),
              Divider(color: Theme.of(context).dividerColor),
              _exportTile(
                context,
                icon: Icons.table_chart_outlined,
                title: 'خروجی CSV (اکسل)',
                subtitle: 'تراکنش‌های این دوره',
                onTap: () => _exportCsv(repo, from, to),
              ),
              Divider(color: Theme.of(context).dividerColor),
              _exportTile(
                context,
                icon: Icons.groups_outlined,
                title: 'خروجی CSV مشتریان',
                subtitle: 'نام، تماس و مانده حساب',
                onTap: () => _exportCustomersCsv(repo),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _rangeLabel(_Range r) => switch (r) {
        _Range.thisMonth => 'این ماه',
        _Range.lastMonth => 'ماه قبل',
        _Range.threeMonths => '۳ ماه اخیر',
        _Range.sixMonths => '۶ ماه اخیر',
        _Range.thisYear => 'امسال',
        _Range.all => 'همه',
      };

  int _monthsBetween(DateTime a, DateTime b) {
    final ja = J.of(a), jb = J.of(b);
    final months = (jb.year - ja.year) * 12 + (jb.month - ja.month) + 1;
    return months.clamp(1, 36);
  }

  Widget _kv(BuildContext context, String label, String value, Color color) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 11.5, color: onSurface.withValues(alpha: 0.62))),
        const SizedBox(height: 5),
        Text(value,
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }

  Widget _exportTile(BuildContext context,
      {required IconData icon,
      required String title,
      required String subtitle,
      required VoidCallback onTap}) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
      title: Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 11.5)),
      trailing: const Icon(Icons.chevron_left_rounded, size: 18),
    );
  }

  Future<void> _run(Future<void> Function() task, String successMessage) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
      if (mounted) showSnack(context, successMessage);
    } catch (e) {
      if (mounted) showSnack(context, 'خطا در ساخت فایل: $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportPdf(AppRepository repo, DateTime from, DateTime to) async {
    await _run(() async {
      final bytes =
          await PdfService.buildReport(repo: repo, from: from, to: to);
      await Backup.shareBytes(
        fileName: 'gozaresh-${J.d(from, persian: false)}.pdf',
        bytes: bytes,
        mimeType: 'application/pdf',
      );
    }, 'گزارش PDF ساخته شد');
  }

  Future<void> _exportCsv(AppRepository repo, DateTime from, DateTime to) async {
    await _run(() async {
      final rows = <List<String>>[
        [
          'تاریخ',
          'نوع',
          'مبلغ',
          'ارز',
          'معادل تومان',
          'مشتری',
          'دسته',
          'وضعیت پرداخت',
          'توضیح',
        ],
        for (final t in (Ledger.filter(repo.transactions,
                from: from, to: to, scope: repo.scopeFilter).toList()
          ..sort((a, b) => a.date.compareTo(b.date))))
          [
            J.d(t.date, persian: false),
            t.kind.shortLabel,
            Fmt.number(t.amount, decimals: Money.decimals(t.currency), persian: false),
            t.currency,
            Fmt.number(t.amount * t.rateToBase, persian: false),
            t.customerId == null ? '' : repo.customerName(t.customerId),
            repo.categoryName(t.categoryId),
            t.kind.isProfitKind ? (t.credit ? 'نسیه' : 'نقدی') : '',
            t.note,
          ],
      ];
      final csv = FileServiceCsv.fromRows(rows);
      await Backup.shareFile(
        fileName: 'taraakonesh-${J.d(from, persian: false)}.csv',
        content: csv,
        mimeType: 'text/csv',
      );
    }, 'فایل CSV ساخته شد');
  }

  Future<void> _exportCustomersCsv(AppRepository repo) async {
    await _run(() async {
      final balances = repo.balancesMap();
      final rows = <List<String>>[
        ['نام', 'تلفن', 'تلگرام', 'مانده (تومان)', 'وضعیت', 'یادداشت'],
        for (final c in repo.customers)
          [
            c.name,
            c.phone,
            c.telegram,
            Fmt.number(balances[c.id] ?? 0, persian: false),
            (balances[c.id] ?? 0) > 0.5
                ? 'بدهکار'
                : (balances[c.id] ?? 0) < -0.5
                    ? 'بستانکار'
                    : 'تسویه',
            c.note,
          ],
      ];
      await Backup.shareFile(
        fileName: 'moshtari-ha.csv',
        content: FileServiceCsv.fromRows(rows),
        mimeType: 'text/csv',
      );
    }, 'فایل CSV ساخته شد');
  }
}

/// ساخت CSV با BOM تا اکسل فارسی را درست نشان دهد
abstract final class FileServiceCsv {
  static String fromRows(List<List<String>> rows) {
    final sb = StringBuffer('\uFEFF');
    for (final row in rows) {
      sb.write(row.map(_escape).join(','));
      sb.write('\r\n');
    }
    return sb.toString();
  }

  static String _escape(String v) {
    final needsQuote =
        v.contains(',') || v.contains('"') || v.contains('\n') || v.contains('\r');
    final s = v.replaceAll('"', '""');
    return needsQuote ? '"$s"' : s;
  }
}
