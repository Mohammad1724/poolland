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

import '../core/localization.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

enum _Range { thisMonth, lastMonth, threeMonths, sixMonths, thisYear, all }

class _ReportsPageState extends State<ReportsPage> {
  _Range _range = _Range.thisMonth;
  TxnScope? _scope = TxnScope.business;
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
        if (repo.transactions.isEmpty) {
          return (J.startOfMonth(now), J.endOfMonth(now));
        }
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
    final scope = _scope;
    final s = repo.summary(from: from, to: to, scope: scope);
    final monthsSpan = _monthsBetween(from, to);
    final series = Ledger.monthlySeries(
      repo.transactions,
      months: monthsSpan,
      endMonth: to,
      scope: scope,
    ).where((p) => !p.monthStart.isBefore(J.startOfMonth(from))).toList();
    final incomeCats = Ledger.byCategory(
      repo.transactions,
      repo.categories,
      from: from,
      to: to,
      kind: TxnKind.income,
      scope: scope,
    );
    final expenseCats = Ledger.byCategory(
      repo.transactions,
      repo.categories,
      from: from,
      to: to,
      kind: TxnKind.expense,
      scope: scope,
    );
    final top = Ledger.topCustomers(
      repo.customers,
      repo.transactions,
      from: from,
      to: to,
      limit: 6,
      scope: scope,
    );
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
                TxnScope.personal,
              ])
                Padding(
                  padding: const EdgeInsetsDirectional.only(start: 6),
                  child: ChoiceChip(
                    label: Text(
                      opt == null ? 'All'.tr : opt.label,
                      style: const TextStyle(fontSize: 12),
                    ),
                    showCheckmark: false,
                    selected: _scope == opt,
                    onSelected: (_) => setState(() => _scope = opt),
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
                  label: Text(_rangeLabel(r).tr),
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
        Text(
          '{from} to {to}'.trArgs({'from': J.d(from), 'to': J.d(to)}),
          style: TextStyle(
            fontSize: 12,
            color: onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 12),

        // Summary
        CardBox(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _kv(
                      context,
                      'Income received',
                      Money.text(s.income),
                      const Color(0xFF16A34A),
                    ),
                  ),
                  Expanded(
                    child: _kv(
                      context,
                      'Expense',
                      Money.text(s.expense),
                      const Color(0xFFE11D48),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _kv(
                      context,
                      'Net profit',
                      Money.text(s.profit),
                      s.profit >= 0
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFE11D48),
                    ),
                  ),
                  Expanded(
                    child: _kv(
                      context,
                      'Profit margin',
                      Fmt.percent(margin),
                      const Color(0xFF7C3AED),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _kv(
                      context,
                      'Received from customers',
                      Money.text(s.received),
                      const Color(0xFF0F766E),
                    ),
                  ),
                  Expanded(
                    child: _kv(
                      context,
                      'Cash paid',
                      Money.text(s.cashOut),
                      const Color(0xFFB45309),
                    ),
                  ),
                ],
              ),
              if (scope != TxnScope.personal) ...[
                const SizedBox(height: 12),
                Divider(color: Theme.of(context).dividerColor),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _kv(
                        context,
                        'Business receivables',
                        Money.text(repo.totals.receivable),
                        const Color(0xFF0F766E),
                      ),
                    ),
                    Expanded(
                      child: _kv(
                        context,
                        'Business payables',
                        Money.text(repo.totals.payable),
                        const Color(0xFF2563EB),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        // Monthly chart
        if (series.length > 1) ...[
          const SectionTitle(
            'Monthly income and expenses',
            icon: Icons.bar_chart_rounded,
          ),
          CardBox(
            padding: const EdgeInsets.fromLTRB(8, 14, 8, 6),
            child: SizedBox(
              height: 190,
              child: MonthlyBarChart(points: series),
            ),
          ),
        ],

        // Expense category chart
        if (expenseCats.isNotEmpty) ...[
          const SectionTitle(
            'Expenses by category',
            icon: Icons.pie_chart_outline_rounded,
          ),
          CardBox(child: CategoryPieChart(data: expenseCats, size: 150)),
        ],

        // Income breakdown
        if (incomeCats.isNotEmpty) ...[
          const SectionTitle('Income sources', icon: Icons.trending_up_rounded),
          CardBox(
            child: Column(
              children: [
                for (final e
                    in (incomeCats.entries.toList()
                      ..sort((a, b) => b.value.compareTo(a.value))))
                  InfoRow(
                    e.key,
                    Text(
                      '{amount} {percent}'.trArgs({
                        'amount': Money.text(e.value),
                        'percent': s.income > 0
                            ? '(${Fmt.percent(e.value / s.income)})'
                            : '',
                      }),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],

        // Top customers
        if (top.isNotEmpty) ...[
          const SectionTitle(
            'Top customers this period',
            icon: Icons.emoji_events_outlined,
          ),
          CardBox(
            child: Column(
              children: [
                for (var i = 0; i < top.length; i++)
                  InfoRow(
                    '{rank}. {customer}'.trArgs({
                      'rank': i + 1,
                      'customer': top[i].key.name,
                    }),
                    MoneyText(top[i].value),
                  ),
              ],
            ),
          ),
        ],

        // Business debtors are excluded from personal-only reports.
        if (scope != TxnScope.personal) ...[
          // Debtors
          const SectionTitle(
            'Debtors',
            icon: Icons.account_balance_wallet_outlined,
          ),
          if (debtors.isEmpty)
            CardBox(
              child: Text(
                'All accounts are settled ✅'.tr,
                style: const TextStyle(fontSize: 12.5),
              ),
            )
          else
            Column(
              children: [
                for (final e in debtors)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: CardBox(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CustomerDetailPage(customer: e.key),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              e.key.name.tr,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          MoneyText(
                            e.value,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F766E),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
        ],

        // Exports
        const SectionTitle('Export', icon: Icons.ios_share_rounded),
        CardBox(
          child: Column(
            children: [
              _exportTile(
                context,
                icon: Icons.picture_as_pdf_rounded,
                title: 'PDF report'.tr,
                subtitle: 'Full period report with charts and transactions'.tr,
                onTap: () => _exportPdf(repo, from, to),
              ),
              Divider(color: Theme.of(context).dividerColor),
              _exportTile(
                context,
                icon: Icons.table_chart_outlined,
                title: 'Export CSV (spreadsheet)'.tr,
                subtitle: 'Transactions for this period'.tr,
                onTap: () => _exportCsv(repo, from, to),
              ),
              Divider(color: Theme.of(context).dividerColor),
              _exportTile(
                context,
                icon: Icons.groups_outlined,
                title: 'Export customers CSV'.tr,
                subtitle: 'Name, contact, and balance',
                onTap: () => _exportCustomersCsv(repo),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _rangeLabel(_Range r) => switch (r) {
    _Range.thisMonth => 'This month',
    _Range.lastMonth => 'Previous month',
    _Range.threeMonths => 'Last 3 months',
    _Range.sixMonths => 'Last 6 months',
    _Range.thisYear => 'This year',
    _Range.all => 'All',
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
        Text(
          label.tr,
          style: TextStyle(
            fontSize: 11.5,
            color: onSurface.withValues(alpha: 0.62),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _exportTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(
        icon,
        size: 20,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(
        title.tr,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(subtitle.tr, style: const TextStyle(fontSize: 11.5)),
      trailing: const Icon(Icons.chevron_right_rounded, size: 18),
    );
  }

  Future<void> _run(Future<void> Function() task, String successMessage) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
      if (mounted) showSnack(context, successMessage);
    } catch (e) {
      if (mounted) {
        showSnack(
          context,
          'Could not create file: {error}'.trArgs({'error': '$e'}),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportPdf(
    AppRepository repo,
    DateTime from,
    DateTime to,
  ) async {
    await _run(() async {
      final bytes = await PdfService.buildReport(
        repo: repo,
        from: from,
        to: to,
        scope: _scope,
      );
      await Backup.shareBytes(
        fileName: 'report-${J.d(from, persian: false)}.pdf',
        bytes: bytes,
        mimeType: 'application/pdf',
      );
    }, 'PDF report created');
  }

  Future<void> _exportCsv(
    AppRepository repo,
    DateTime from,
    DateTime to,
  ) async {
    await _run(() async {
      final rows = <List<String>>[
        [
          'Date',
          'Type',
          'Amount',
          'Currency',
          'Equivalent in Toman',
          'Customer',
          'Category',
          'Payment status',
          'Description',
        ],
        for (final t in (Ledger.filter(
          repo.transactions,
          from: from,
          to: to,
          scope: _scope,
        ).toList()..sort((a, b) => a.date.compareTo(b.date))))
          [
            J.d(t.date, persian: false),
            t.kind.shortLabel,
            Fmt.number(
              t.amount,
              decimals: Money.decimals(t.currency),
              persian: false,
            ),
            t.currency,
            Fmt.number(t.amount * t.rateToBase, persian: false),
            t.customerId == null ? '' : repo.customerName(t.customerId),
            repo.categoryName(t.categoryId),
            t.kind.isProfitKind ? (t.credit ? 'Credit' : 'Cash') : '',
            t.note,
          ],
      ];
      final csv = FileServiceCsv.fromRows(rows);
      await Backup.shareFile(
        fileName: 'transactions-${J.d(from, persian: false)}.csv',
        content: csv,
        mimeType: 'text/csv',
      );
    }, 'CSV file created');
  }

  Future<void> _exportCustomersCsv(AppRepository repo) async {
    await _run(() async {
      final balances = repo.balancesMap();
      final rows = <List<String>>[
        ['Name', 'Phone', 'Telegram', 'Balance (Toman)', 'Status', 'Note'],
        for (final c in repo.customers)
          [
            c.name,
            c.phone,
            c.telegram,
            Fmt.number(balances[c.id] ?? 0, persian: false),
            (balances[c.id] ?? 0) > 0.5
                ? 'Debtor'
                : (balances[c.id] ?? 0) < -0.5
                ? 'Creditor'
                : 'Settled',
            c.note,
          ],
      ];
      await Backup.shareFile(
        fileName: 'customers.csv',
        content: FileServiceCsv.fromRows(rows),
        mimeType: 'text/csv',
      );
    }, 'CSV file created');
  }
}

/// Add a BOM so spreadsheet apps display Unicode text correctly.
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
        v.contains(',') ||
        v.contains('"') ||
        v.contains('\n') ||
        v.contains('\r');
    final s = v.replaceAll('"', '""');
    return needsQuote ? '"$s"' : s;
  }
}
