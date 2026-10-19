import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/backup.dart';
import '../core/format_utils.dart';
import '../core/jalali_utils.dart';
import '../core/localization.dart';
import '../core/money.dart';
import '../data/ledger.dart';
import '../data/models.dart';
import '../data/pdf_service.dart';
import '../data/repository.dart';
import 'customer_detail_page.dart';
import 'motion_kit.dart';
import 'theme.dart';
import 'widgets/common_charts.dart';
import 'widgets/period_chart.dart';
import 'widgets/widgets.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key, this.controller});

  final ScrollController? controller;

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

enum _Range {
  daily,
  weekly,
  thisMonth,
  all,
  lastMonth,
  threeMonths,
  sixMonths,
  thisYear,
}

enum _CategoryFilter { expense, income, all }

class _CategoryStat {
  final String id;
  final String name;
  final TxnKind kind;
  final double amount;
  final int txnCount;
  final Map<String, double> subcategories;
  final List<Txn> transactions;

  const _CategoryStat({
    required this.id,
    required this.name,
    required this.kind,
    required this.amount,
    required this.txnCount,
    required this.subcategories,
    required this.transactions,
  });
}

class _ReportsPageState extends State<ReportsPage> {
  _Range _range = _Range.thisMonth;
  int _periodOffset = 0; // <= 0; allows stepping back/forward in daily/weekly/monthly
  // Default to "All" so a user who only tracks personal finances does not
  // land on an empty report with no explanation. The scope chips below let
  // the user narrow it down as needed.
  TxnScope? _scope;
  int? _chartModeOverride; // 0 = daily, 1 = weekly, 2 = monthly
  _CategoryFilter _categoryFilter = _CategoryFilter.all;
  bool _busy = false;

  int get _effectiveChartMode {
    if (_chartModeOverride != null) return _chartModeOverride!;
    return switch (_range) {
      _Range.daily => 0,
      _Range.weekly => 1,
      _Range.thisMonth || _Range.lastMonth => 0,
      _ => 2,
    };
  }

  bool get _canStepPeriod =>
      _range == _Range.daily ||
      _range == _Range.weekly ||
      _range == _Range.thisMonth;

  (DateTime, DateTime) _bounds(AppRepository repo) {
    final now = DateTime.now();
    switch (_range) {
      case _Range.daily:
        final d = J.addDays(now, _periodOffset);
        return (J.startOfDay(d), J.endOfDay(d));
      case _Range.weekly:
        final end = J.addDays(now, _periodOffset * 7);
        final start = J.addDays(end, -6);
        return (J.startOfDay(start), J.endOfDay(end));
      case _Range.thisMonth:
        final m = J.addMonths(now, _periodOffset);
        return (J.startOfMonth(m), J.endOfMonth(m));
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

  (DateTime, DateTime)? _previousBounds(DateTime from, DateTime to) {
    if (_range == _Range.all) return null;
    final days = J.daysBetween(from, to).clamp(1, 3660);
    final prevTo = J.endOfDay(J.addDays(from, -1));
    final prevFrom = J.startOfDay(J.addDays(prevTo, -(days - 1)));
    return (prevFrom, prevTo);
  }

  List<_CategoryStat> _computeCategoryStats(
    AppRepository repo, {
    required DateTime from,
    required DateTime to,
    required TxnKind kind,
    required TxnScope? scope,
  }) {
    final byId = {for (final c in repo.categories) c.id: c};
    final parentsWithChildren = {
      for (final c in repo.categories)
        if (c.parentId != null) c.parentId!,
    };
    final amounts = <String, double>{};
    final counts = <String, int>{};
    final names = <String, String>{};
    final subcats = <String, Map<String, double>>{};
    final txnsByCat = <String, List<Txn>>{};

    for (final t in Ledger.filter(
      repo.transactions,
      from: from,
      to: to,
      scope: scope,
    )) {
      final include = kind == TxnKind.income
          ? Ledger.isRecognizedIncome(t)
          : Ledger.isChartedExpense(t);
      if (!include) continue;

      final rawCat = t.categoryId == null ? null : byId[t.categoryId!];
      final parentCat = rawCat?.parentId == null
          ? null
          : byId[rawCat!.parentId!];
      final rootCat = parentCat ?? rawCat;
      final rootKey = rootCat?.id ?? '__uncategorized_${kind.name}';
      final rootName = rootCat?.name ?? 'Uncategorized';
      final v = Ledger.base(t);

      amounts[rootKey] = (amounts[rootKey] ?? 0) + v;
      counts[rootKey] = (counts[rootKey] ?? 0) + 1;
      names[rootKey] = rootName;
      (txnsByCat[rootKey] ??= <Txn>[]).add(t);

      if (parentCat != null && rawCat != null) {
        final map = subcats[rootKey] ??= <String, double>{};
        map[rawCat.name] = (map[rawCat.name] ?? 0) + v;
      } else if (rootCat != null &&
          parentsWithChildren.contains(rootCat.id)) {
        final map = subcats[rootKey] ??= <String, double>{};
        final generalLabel = 'General ({name})'.trArgs({
          'name': rootCat.name.tr,
        });
        map[generalLabel] = (map[generalLabel] ?? 0) + v;
      }
    }

    final list = <_CategoryStat>[
      for (final entry in amounts.entries)
        _CategoryStat(
          id: entry.key,
          name: names[entry.key] ?? 'Uncategorized',
          kind: kind,
          amount: entry.value,
          txnCount: counts[entry.key] ?? 0,
          subcategories: subcats[entry.key] ?? const {},
          transactions: (txnsByCat[entry.key] ?? const <Txn>[])
            ..sort((a, b) => b.date.compareTo(a.date)),
        ),
    ]..sort((a, b) => b.amount.compareTo(a.amount));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final (from, to) = _bounds(repo);
    final scope = _scope;
    final s = repo.summary(from: from, to: to, scope: scope);
    final prevRange = _previousBounds(from, to);
    final prevSummary = prevRange == null
        ? null
        : repo.summary(from: prevRange.$1, to: prevRange.$2, scope: scope);

    final daysSpan = J.daysBetween(from, to).clamp(1, 3660);
    final monthsSpan = _monthsBetween(from, to);

    // Build chart series for Daily, Weekly, and Monthly views.
    final dailyChartDays = _range == _Range.daily
        ? 14
        : _range == _Range.weekly
        ? 7
        : daysSpan.clamp(7, 30);
    final dailyPoints = Ledger.dailySeries(
      repo.transactions,
      days: dailyChartDays,
      endDay: to,
      scope: scope,
    );
    final weeklyChartWeeks = (_range == _Range.weekly ? 8 : (daysSpan / 7).ceil())
        .clamp(4, 12);
    final weeklyPoints = Ledger.weeklySeries(
      repo.transactions,
      weeks: weeklyChartWeeks,
      endDay: to,
      scope: scope,
    );
    final monthlyPoints = Ledger.monthlySeries(
      repo.transactions,
      months: math.max(monthsSpan, 6),
      endMonth: to,
      scope: scope,
    );

    final expenseStats = _computeCategoryStats(
      repo,
      from: from,
      to: to,
      kind: TxnKind.expense,
      scope: scope,
    );
    final incomeStats = _computeCategoryStats(
      repo,
      from: from,
      to: to,
      kind: TxnKind.income,
      scope: scope,
    );

    final expenseCatsMap = <String, double>{
      for (final c in expenseStats) c.name: c.amount,
    };
    final incomeCatsMap = <String, double>{
      for (final c in incomeStats) c.name: c.amount,
    };

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
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        // 1. Scope selector chips (All / Personal / Business)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final opt in <TxnScope?>[
                null,
                TxnScope.personal,
                TxnScope.business,
              ])
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
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

        // 2. Time range selector (Daily, Weekly, Monthly, 3M, 6M, Year, All)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final r in _Range.values) ...[
                ChoiceChip(
                  label: Text(_rangeLabel(r).tr),
                  showCheckmark: false,
                  selected: _range == r,
                  onSelected: (_) => setState(() {
                    _range = r;
                    _periodOffset = 0;
                    _chartModeOverride = null;
                  }),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Period date indicator + stepper for Daily / Weekly / Monthly
        _buildPeriodNavigator(context, from, to),
        const SizedBox(height: 12),

        // 3. Executive Income & Expense Report Card
        SectionTitle(
          'Income and expense report',
          icon: Icons.analytics_outlined,
        ),
        _buildIncomeExpenseSummaryCard(
          context,
          repo: repo,
          summary: s,
          prevSummary: prevSummary,
          margin: margin,
          scope: scope,
        ),

        // 4. Interactive Daily / Weekly / Monthly Trend Chart
        SectionTitle(
          'Income and expense chart',
          icon: Icons.bar_chart_rounded,
        ),
        _buildTrendChartCard(
          context,
          dailyPoints: dailyPoints,
          weeklyPoints: weeklyPoints,
          monthlyPoints: monthlyPoints,
        ),

        // 5. Category & Subcategory Income & Expense Report
        SectionTitle(
          'Category income and expense report',
          icon: Icons.donut_large_rounded,
        ),
        _buildDualCategoryDonutCard(
          context,
          expenseData: expenseCatsMap,
          incomeData: incomeCatsMap,
          totalExpense: s.expense,
          totalIncome: s.income,
        ),
        const SizedBox(height: 10),
        _buildCategoryBreakdownSection(
          context,
          repo: repo,
          expenseStats: expenseStats,
          incomeStats: incomeStats,
          totalExpense: s.expense,
          totalIncome: s.income,
          from: from,
          to: to,
        ),

        // 6. Specialist Financial Insights
        SectionTitle(
          'Specialist financial insights',
          icon: Icons.auto_graph_rounded,
        ),
        _buildSpecialistInsightsSection(
          context,
          repo: repo,
          from: from,
          to: to,
          scope: scope,
          summary: s,
          daysSpan: daysSpan,
        ),

        // 7. Top customers (when business scope is included)
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

        // 8. Business debtors (excluded from personal-only reports)
        if (scope != TxnScope.personal) ...[
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

        // 9. Exports
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

  Widget _buildPeriodNavigator(
    BuildContext context,
    DateTime from,
    DateTime to,
  ) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final dateText = _range == _Range.daily
        ? J.d(from)
        : '{from} to {to}'.trArgs({'from': J.d(from), 'to': J.d(to)});

    return Row(
      children: [
        if (_canStepPeriod) ...[
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Previous period'.tr,
            icon: const Icon(Icons.chevron_left_rounded, size: 20),
            onPressed: () => setState(() => _periodOffset -= 1),
          ),
        ],
        Expanded(
          child: Text(
            dateText,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: onSurface.withValues(alpha: 0.72),
            ),
          ),
        ),
        if (_periodOffset != 0)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 4),
            child: ActionChip(
              visualDensity: VisualDensity.compact,
              label: Text(
                'Back to today'.tr,
                style: const TextStyle(fontSize: 11),
              ),
              onPressed: () => setState(() => _periodOffset = 0),
            ),
          ),
        if (_canStepPeriod)
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Next period'.tr,
            icon: const Icon(Icons.chevron_right_rounded, size: 20),
            onPressed: _periodOffset < 0
                ? () => setState(() => _periodOffset += 1)
                : null,
          ),
      ],
    );
  }

  Widget _buildIncomeExpenseSummaryCard(
    BuildContext context, {
    required AppRepository repo,
    required Summary summary,
    required Summary? prevSummary,
    required double margin,
    required TxnScope? scope,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final totalFlow = summary.income + summary.expense;
    final incomeShare = totalFlow > 0
        ? (summary.income / totalFlow).clamp(0.0, 1.0)
        : 0.5;

    final (healthLabel, healthColor) = summary.income <= 0 && summary.expense <= 0
        ? ('Balanced', const Color(0xFF64748B))
        : summary.profit < 0
        ? ('Deficit', AppTheme.expense)
        : margin >= 0.25
        ? ('Healthy savings', AppTheme.revenue)
        : margin >= 0.10
        ? ('Balanced', const Color(0xFF0EA5A4))
        : ('High spending', const Color(0xFFD97706));

    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _kvWithDelta(
                  context,
                  label: 'Income received',
                  value: Money.text(summary.income),
                  color: const Color(0xFF16A34A),
                  current: summary.income,
                  previous: prevSummary?.income,
                  positiveIsGood: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _kvWithDelta(
                  context,
                  label: 'Expense',
                  value: Money.text(summary.expense),
                  color: const Color(0xFFE11D48),
                  current: summary.expense,
                  previous: prevSummary?.expense,
                  positiveIsGood: false,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Visual Income vs Expense bar
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 7,
              child: Row(
                children: [
                  Expanded(
                    flex: math.max(1, (incomeShare * 100).round()),
                    child: Container(color: const Color(0xFF16A34A)),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    flex: math.max(1, ((1 - incomeShare) * 100).round()),
                    child: Container(color: const Color(0xFFE11D48)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: _kv(
                  context,
                  'Net profit',
                  Money.text(summary.profit),
                  summary.profit >= 0
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFE11D48),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Profit margin'.tr,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          Fmt.percent(margin),
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF7C3AED),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: healthColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            healthLabel.tr,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: healthColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          Row(
            children: [
              Expanded(
                child: _kv(
                  context,
                  'Received from customers',
                  Money.text(summary.received),
                  const Color(0xFF0F766E),
                ),
              ),
              Expanded(
                child: _kv(
                  context,
                  'Cash paid',
                  Money.text(summary.cashOut),
                  const Color(0xFFB45309),
                ),
              ),
            ],
          ),

          if (scope != TxnScope.personal) ...[
            const SizedBox(height: 10),
            Divider(color: Theme.of(context).dividerColor),
            const SizedBox(height: 8),
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
    );
  }

  Widget _buildTrendChartCard(
    BuildContext context, {
    required List<DayPoint> dailyPoints,
    required List<DayPoint> weeklyPoints,
    required List<MonthPoint> monthlyPoints,
  }) {
    final mode = _effectiveChartMode;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return CardBox(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<int>(
            segments: [
              ButtonSegment(value: 0, label: Text('Daily'.tr)),
              ButtonSegment(value: 1, label: Text('Weekly'.tr)),
              ButtonSegment(value: 2, label: Text('Monthly'.tr)),
            ],
            selected: {mode},
            showSelectedIcon: false,
            onSelectionChanged: (s) =>
                setState(() => _chartModeOverride = s.first),
            style: SegmentedButton.styleFrom(
              minimumSize: const Size(0, 36),
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _chartLegendDot(const Color(0xFF16A34A), 'Income'.tr, onSurface),
              const SizedBox(width: 16),
              _chartLegendDot(const Color(0xFFE11D48), 'Expense'.tr, onSurface),
            ],
          ),
          const SizedBox(height: 10),
          if (mode == 0)
            PeriodBarChart(
              points: dailyPoints,
              height: 190,
              labelOf: (p) => Fmt.number(J.of(p.day).day),
            )
          else if (mode == 1)
            PeriodBarChart(
              points: weeklyPoints,
              height: 190,
              labelOf: (p) {
                final j = J.of(p.day);
                return '${Fmt.number(j.day)}/${Fmt.number(j.month)}';
              },
            )
          else
            SizedBox(
              height: 190,
              child: MonthlyBarChart(points: monthlyPoints),
            ),
        ],
      ),
    );
  }

  Widget _chartLegendDot(Color color, String label, Color onSurface) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: onSurface.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }

  Widget _buildDualCategoryDonutCard(
    BuildContext context, {
    required Map<String, double> expenseData,
    required Map<String, double> incomeData,
    required double totalExpense,
    required double totalIncome,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 340;
        final expenseChart = _MiniCategoryDonutCard(
          title: 'Total expense'.tr,
          total: totalExpense,
          accentColor: AppTheme.expense,
          data: expenseData,
          palette: const [
            Color(0xFFE11D48),
            Color(0xFFF97316),
            Color(0xFFF59E0B),
            Color(0xFFEC4899),
            Color(0xFF8B5CF6),
            Color(0xFF6366F1),
          ],
        );
        final incomeChart = _MiniCategoryDonutCard(
          title: 'Total income'.tr,
          total: totalIncome,
          accentColor: AppTheme.revenue,
          data: incomeData,
          palette: const [
            Color(0xFF16A34A),
            Color(0xFF0EA5A4),
            Color(0xFF38BDF8),
            Color(0xFF22C55E),
            Color(0xFF84CC16),
            Color(0xFF14B8A6),
          ],
        );

        if (isNarrow) {
          return Column(
            children: [
              expenseChart,
              const SizedBox(height: 10),
              incomeChart,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: expenseChart),
            const SizedBox(width: 10),
            Expanded(child: incomeChart),
          ],
        );
      },
    );
  }

  Widget _buildCategoryBreakdownSection(
    BuildContext context, {
    required AppRepository repo,
    required List<_CategoryStat> expenseStats,
    required List<_CategoryStat> incomeStats,
    required double totalExpense,
    required double totalIncome,
    required DateTime from,
    required DateTime to,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final budgetsByCat = {
      for (final b in repo.budgets.where((b) => b.enabled)) b.categoryId: b,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<_CategoryFilter>(
          segments: [
            ButtonSegment(
              value: _CategoryFilter.all,
              label: Text('All categories'.tr),
            ),
            ButtonSegment(
              value: _CategoryFilter.expense,
              label: Text('Expense categories'.tr),
            ),
            ButtonSegment(
              value: _CategoryFilter.income,
              label: Text('Income categories'.tr),
            ),
          ],
          selected: {_categoryFilter},
          showSelectedIcon: false,
          onSelectionChanged: (s) =>
              setState(() => _categoryFilter = s.first),
          style: SegmentedButton.styleFrom(
            minimumSize: const Size(0, 36),
            textStyle: const TextStyle(fontSize: 11.5),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Tap any category to inspect its subcategories and transactions'.tr,
          style: TextStyle(
            fontSize: 11,
            color: onSurface.withValues(alpha: 0.58),
          ),
        ),
        const SizedBox(height: 8),

        if (_categoryFilter != _CategoryFilter.income) ...[
          if (expenseStats.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CardBox(
                child: Text(
                  'No expense categories in this period'.tr,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ),
            )
          else ...[
            if (_categoryFilter == _CategoryFilter.all)
              Padding(
                padding: const EdgeInsets.only(bottom: 6, top: 2),
                child: Text(
                  'Expenses by category'.tr,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            for (var i = 0; i < expenseStats.length; i++)
              _buildCategoryStatCard(
                context,
                repo: repo,
                stat: expenseStats[i],
                totalOfKind: totalExpense,
                color: _expensePalette[i % _expensePalette.length],
                budget: budgetsByCat[expenseStats[i].id],
              ),
          ],
        ],

        if (_categoryFilter != _CategoryFilter.expense) ...[
          if (incomeStats.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CardBox(
                child: Text(
                  'No income categories in this period'.tr,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ),
            )
          else ...[
            if (_categoryFilter == _CategoryFilter.all)
              Padding(
                padding: const EdgeInsets.only(bottom: 6, top: 6),
                child: Text(
                  'Income sources'.tr,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            for (var i = 0; i < incomeStats.length; i++)
              _buildCategoryStatCard(
                context,
                repo: repo,
                stat: incomeStats[i],
                totalOfKind: totalIncome,
                color: _incomePalette[i % _incomePalette.length],
                budget: null,
              ),
          ],
        ],
      ],
    );
  }

  static const _expensePalette = [
    Color(0xFFE11D48),
    Color(0xFFF97316),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFF6366F1),
  ];

  static const _incomePalette = [
    Color(0xFF16A34A),
    Color(0xFF0EA5A4),
    Color(0xFF38BDF8),
    Color(0xFF22C55E),
    Color(0xFF84CC16),
    Color(0xFF14B8A6),
  ];

  Widget _buildCategoryStatCard(
    BuildContext context, {
    required AppRepository repo,
    required _CategoryStat stat,
    required double totalOfKind,
    required Color color,
    required Budget? budget,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final share = totalOfKind > 0
        ? (stat.amount / totalOfKind).clamp(0.0, 1.0)
        : 0.0;
    final subEntries = stat.subcategories.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CardBox(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        onTap: () => _showCategoryTransactionsSheet(
          context,
          repo: repo,
          stat: stat,
          color: color,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    stat.name.tr,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: onSurface.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '{count} txns'.trArgs({
                      'count': Fmt.number(stat.txnCount),
                    }),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '{amount} {percent}'.trArgs({
                    'amount': Money.text(stat.amount),
                    'percent': totalOfKind > 0
                        ? '(${Fmt.percent(share)})'
                        : '',
                  }),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 5,
                backgroundColor: color.withValues(alpha: 0.12),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            if (budget != null && budget.limit > 0) ...[
              const SizedBox(height: 6),
              Text(
                'Budget used: {used} of {limit}'.trArgs({
                  'used': Money.text(stat.amount, compact: true),
                  'limit': Money.text(budget.limit, compact: true),
                }),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: stat.amount > budget.limit
                      ? AppTheme.expense
                      : onSurface.withValues(alpha: 0.65),
                ),
              ),
            ],
            if (subEntries.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final sub in subEntries)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: color.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Text(
                        '${sub.key.tr}: ${Money.text(sub.value, compact: true)}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: onSurface.withValues(alpha: 0.82),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showCategoryTransactionsSheet(
    BuildContext context, {
    required AppRepository repo,
    required _CategoryStat stat,
    required Color color,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final subEntries = stat.subcategories.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    showLedgerSheet<void>(
      context,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.78,
        ),
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    stat.name.tr,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  Money.text(stat.amount),
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
            if (subEntries.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Subcategories'.tr,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: onSurface.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final sub in subEntries)
                    Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text(
                        '${sub.key.tr} • ${Money.text(sub.value)}',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Divider(color: Theme.of(ctx).dividerColor),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: stat.transactions.length,
                separatorBuilder: (_, _) =>
                    Divider(height: 1, color: Theme.of(ctx).dividerColor),
                itemBuilder: (_, index) {
                  final t = stat.transactions[index];
                  final catLabel = repo.categoryName(t.categoryId);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                t.note.trim().isNotEmpty ? t.note : catLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${J.d(t.date)} • $catLabel',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: onSurface.withValues(alpha: 0.58),
                                ),
                              ),
                            ],
                          ),
                        ),
                        MoneyText(
                          Ledger.base(t),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecialistInsightsSection(
    BuildContext context, {
    required AppRepository repo,
    required DateTime from,
    required DateTime to,
    required TxnScope? scope,
    required Summary summary,
    required int daysSpan,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final periodTxns = Ledger.filter(
      repo.transactions,
      from: from,
      to: to,
      scope: scope,
    ).toList();

    // Find largest single expense & income count / expense count
    Txn? largestExpenseTxn;
    var expenseCount = 0;
    var incomeCount = 0;
    final dayExpenses = <DateTime, double>{};
    // Iranian week order: Saturday (6) -> Sunday (7) -> Monday (1) ... -> Friday (5)
    final weekdayExpense = List<double>.filled(7, 0);
    final weekdayIncome = List<double>.filled(7, 0);

    int iranianWeekdayIndex(DateTime d) {
      // DateTime.saturday == 6 -> 0, sunday == 7 -> 1, monday == 1 -> 2, ..., friday == 5 -> 6
      return (d.weekday + 1) % 7;
    }

    for (final t in periodTxns) {
      final v = Ledger.base(t);
      final wIdx = iranianWeekdayIndex(t.date);
      if (Ledger.isChartedExpense(t)) {
        expenseCount++;
        weekdayExpense[wIdx] += v;
        final dKey = J.startOfDay(t.date);
        dayExpenses[dKey] = (dayExpenses[dKey] ?? 0) + v;
        if (largestExpenseTxn == null || v > Ledger.base(largestExpenseTxn)) {
          largestExpenseTxn = t;
        }
      } else if (Ledger.isRecognizedIncome(t)) {
        incomeCount++;
        weekdayIncome[wIdx] += v;
      }
    }

    DateTime? peakDay;
    var peakDayAmount = 0.0;
    for (final entry in dayExpenses.entries) {
      if (entry.value > peakDayAmount) {
        peakDayAmount = entry.value;
        peakDay = entry.key;
      }
    }

    final avgExpenseTxn = expenseCount > 0
        ? summary.expense / expenseCount
        : 0.0;
    final avgIncomeTxn = incomeCount > 0 ? summary.income / incomeCount : 0.0;
    final dailyAvgIncome = summary.income / daysSpan;
    final dailyAvgExpense = summary.expense / daysSpan;
    final expenseRatio = summary.income > 0
        ? (summary.expense / summary.income).clamp(0.0, 2.0)
        : (summary.expense > 0 ? 1.0 : 0.0);

    const weekdayNames = [
      'Saturday',
      'Sunday',
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
    ];
    final maxWeekdayFlow = [
      ...weekdayExpense,
      ...weekdayIncome,
    ].fold<double>(0, (a, b) => a > b ? a : b);

    // Personal vs Business comparison when viewing All scopes
    final personalSummary = scope == null
        ? repo.summary(from: from, to: to, scope: TxnScope.personal)
        : null;
    final businessSummary = scope == null
        ? repo.summary(from: from, to: to, scope: TxnScope.business)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CardBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: _kv(
                      context,
                      'Daily average income',
                      Money.text(dailyAvgIncome, compact: true),
                      const Color(0xFF15803D),
                    ),
                  ),
                  Expanded(
                    child: _kv(
                      context,
                      'Daily average expense',
                      Money.text(dailyAvgExpense, compact: true),
                      const Color(0xFFBE123C),
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
                      'Expense to income ratio',
                      Fmt.percent(expenseRatio),
                      expenseRatio <= 0.8
                          ? const Color(0xFF0F766E)
                          : const Color(0xFFE11D48),
                    ),
                  ),
                  Expanded(
                    child: _kv(
                      context,
                      'Transactions count',
                      Fmt.number(summary.txnCount),
                      onSurface,
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
                      'Largest expense',
                      largestExpenseTxn == null
                          ? '—'
                          : Money.text(
                              Ledger.base(largestExpenseTxn),
                              compact: true,
                            ),
                      AppTheme.expense,
                    ),
                  ),
                  Expanded(
                    child: _kv(
                      context,
                      'Peak spending day',
                      peakDay == null
                          ? '—'
                          : '${J.d(peakDay)} (${Money.text(peakDayAmount, compact: true)})',
                      const Color(0xFFD97706),
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
                      'Average expense per transaction',
                      Money.text(avgExpenseTxn, compact: true),
                      const Color(0xFFBE123C),
                    ),
                  ),
                  Expanded(
                    child: _kv(
                      context,
                      'Average income per transaction',
                      Money.text(avgIncomeTxn, compact: true),
                      const Color(0xFF15803D),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        if (personalSummary != null && businessSummary != null) ...[
          const SizedBox(height: 10),
          CardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Personal vs. Business share'.tr,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _scopeShareBox(
                        context,
                        title: 'Personal'.tr,
                        income: personalSummary.income,
                        expense: personalSummary.expense,
                        accent: const Color(0xFF0EA5A4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _scopeShareBox(
                        context,
                        title: 'Business'.tr,
                        income: businessSummary.income,
                        expense: businessSummary.expense,
                        accent: const Color(0xFF6366F1),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],

        if (maxWeekdayFlow > 0) ...[
          const SizedBox(height: 10),
          CardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Weekday spending & income pattern'.tr,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < 7; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 64,
                          child: Text(
                            weekdayNames[i].tr,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: onSurface.withValues(alpha: 0.75),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              if (weekdayIncome[i] > 0)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(99),
                                  child: LinearProgressIndicator(
                                    value: (weekdayIncome[i] / maxWeekdayFlow)
                                        .clamp(0.0, 1.0),
                                    minHeight: 4,
                                    backgroundColor: const Color(
                                      0xFF16A34A,
                                    ).withValues(alpha: 0.1),
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                          Color(0xFF16A34A),
                                        ),
                                  ),
                                ),
                              if (weekdayIncome[i] > 0 &&
                                  weekdayExpense[i] > 0)
                                const SizedBox(height: 3),
                              if (weekdayExpense[i] > 0)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(99),
                                  child: LinearProgressIndicator(
                                    value: (weekdayExpense[i] / maxWeekdayFlow)
                                        .clamp(0.0, 1.0),
                                    minHeight: 4,
                                    backgroundColor: const Color(
                                      0xFFE11D48,
                                    ).withValues(alpha: 0.1),
                                    valueColor:
                                        const AlwaysStoppedAnimation<Color>(
                                          Color(0xFFE11D48),
                                        ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          weekdayExpense[i] > 0
                              ? Money.text(
                                  weekdayExpense[i],
                                  compact: true,
                                  withSymbol: false,
                                )
                              : Money.text(
                                  weekdayIncome[i],
                                  compact: true,
                                  withSymbol: false,
                                ),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: weekdayExpense[i] >= weekdayIncome[i]
                                ? AppTheme.expense
                                : AppTheme.revenue,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _scopeShareBox(
    BuildContext context, {
    required String title,
    required double income,
    required double expense,
    required Color accent,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: accent,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${'Income'.tr}: ${Money.text(income, compact: true)}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: onSurface.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${'Expense'.tr}: ${Money.text(expense, compact: true)}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: onSurface.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  String _rangeLabel(_Range r) => switch (r) {
    _Range.daily => 'Daily',
    _Range.weekly => 'Weekly',
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

  Widget _kvWithDelta(
    BuildContext context, {
    required String label,
    required String value,
    required Color color,
    required double current,
    required double? previous,
    required bool positiveIsGood,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    double? deltaRatio;
    if (previous != null && previous > 0) {
      deltaRatio = (current - previous) / previous;
    }

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
        if (deltaRatio != null && deltaRatio.abs() >= 0.01) ...[
          const SizedBox(height: 4),
          Builder(
            builder: (context) {
              final isUp = deltaRatio! >= 0;
              final isGood = isUp == positiveIsGood;
              final badgeColor = isGood
                  ? const Color(0xFF16A34A)
                  : const Color(0xFFE11D48);
              final sign = isUp ? '+' : '';
              return Text(
                '$sign${Fmt.percent(deltaRatio)} ${'vs previous period'.tr}',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: badgeColor,
                ),
              );
            },
          ),
        ],
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

class _MiniCategoryDonutCard extends StatelessWidget {
  const _MiniCategoryDonutCard({
    required this.title,
    required this.total,
    required this.accentColor,
    required this.data,
    required this.palette,
  });

  final String title;
  final double total;
  final Color accentColor;
  final Map<String, double> data;
  final List<Color> palette;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final entries = data.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final sum = entries.fold<double>(0, (s, e) => s + e.value);

    return CardBox(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: onSurface.withValues(alpha: 0.78),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 112,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sectionsSpace: entries.length > 1 ? 2 : 0,
                    centerSpaceRadius: 34,
                    startDegreeOffset: -90,
                    sections: entries.isEmpty
                        ? [
                            PieChartSectionData(
                              value: 1,
                              color: onSurface.withValues(alpha: 0.08),
                              radius: 15,
                              showTitle: false,
                            ),
                          ]
                        : [
                            for (var i = 0; i < entries.length; i++)
                              PieChartSectionData(
                                value: entries[i].value,
                                color: palette[i % palette.length],
                                radius: 16,
                                showTitle: false,
                              ),
                          ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: MoneyText(
                      total,
                      compact: true,
                      withSymbol: false,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: entries.isEmpty
                            ? onSurface.withValues(alpha: 0.45)
                            : accentColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (entries.isEmpty)
            Center(
              child: Text(
                '—',
                style: TextStyle(
                  fontSize: 11,
                  color: onSurface.withValues(alpha: 0.45),
                ),
              ),
            )
          else
            Column(
              children: [
                for (var i = 0; i < entries.length && i < 3; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: palette[i % palette.length],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            entries[i].key.tr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: onSurface.withValues(alpha: 0.78),
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          sum > 0 ? Fmt.percent(entries[i].value / sum) : '',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: onSurface.withValues(alpha: 0.62),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
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
