import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/backup.dart';
import '../core/format_utils.dart';
import '../core/jalali_utils.dart';
import '../core/localization.dart';
import '../core/money.dart';
import '../core/sms/sms_models.dart';
import '../data/ledger.dart';
import '../data/models.dart';
import '../data/pdf_service.dart';
import '../data/repository.dart';
import 'customer_detail_page.dart';
import 'forms/transaction_edit_page.dart';
import 'motion_kit.dart';
import 'theme.dart';
import 'widgets/common_charts.dart';
import 'widgets/date_picker.dart';
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
  custom,
}

enum _ReportTab { stats, categories, sources }

enum _CategoryFilter { all, expense, income }

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

class _SourceStat {
  final String key;
  final String title;
  final String? cardMask;
  final IconData icon;
  final Color accent;
  final double inflow;
  final double outflow;
  final int txnCount;
  final List<Txn> transactions;

  const _SourceStat({
    required this.key,
    required this.title,
    this.cardMask,
    required this.icon,
    required this.accent,
    required this.inflow,
    required this.outflow,
    required this.txnCount,
    required this.transactions,
  });

  double get net => inflow - outflow;
}

class _ReportsPageState extends State<ReportsPage> {
  _Range _range = _Range.thisMonth;
  _ReportTab _tab = _ReportTab.stats;
  int _periodOffset = 0;
  DateTime? _customFrom;
  DateTime? _customTo;
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
      case _Range.custom:
        final from = _customFrom ?? J.startOfMonth(now);
        final to = _customTo ?? J.endOfDay(now);
        if (to.isBefore(from)) {
          return (J.startOfDay(to), J.endOfDay(from));
        }
        return (J.startOfDay(from), J.endOfDay(to));
      case _Range.all:
        if (repo.transactions.isEmpty) {
          return (J.startOfMonth(now), J.endOfMonth(now));
        }
        // `repo.transactions` is sorted descending by `date`, so `.last.date`
        // is the earliest recorded date in O(1).
        final first = repo.transactions.last.date;
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

  static final RegExp _cardMaskRe = RegExp(r'(\d{4}[*•xX\-]+\d{4}|\d{4}\s*\d{4})');

  List<_SourceStat> _computeSourceStats(
    AppRepository repo, {
    required DateTime from,
    required DateTime to,
    required TxnScope? scope,
  }) {
    final smsByTxnId = <String, SmsHistoryEntry>{
      for (final h in repo.smsHistory)
        if (h.transactionId != null && h.transactionId!.isNotEmpty)
          h.transactionId!: h,
    };

    final inflows = <String, double>{};
    final outflows = <String, double>{};
    final titles = <String, String>{};
    final masks = <String, String>{};
    final icons = <String, IconData>{};
    final accents = <String, Color>{};
    final txnsByKey = <String, List<Txn>>{};

    (String key, String title, IconData icon, Color accent) detectBank(Txn t) {
      final sms = smsByTxnId[t.id];
      if (sms?.bankName != null && sms!.bankName!.trim().isNotEmpty) {
        final b = sms.bankName!.trim();
        return ('bank:$b', b.tr, Icons.account_balance_rounded, const Color(0xFF0EA5A4));
      }
      final noteLower = t.note.toLowerCase();
      if (noteLower.contains('بلوبانک') ||
          noteLower.contains('بلو') ||
          noteLower.contains('blu')) {
        return (
          'bank:Blu Bank',
          'Blu Bank'.tr,
          Icons.account_balance_rounded,
          const Color(0xFF2563EB),
        );
      }
      for (final rule in repo.activeSmsRules) {
        final faName = rule.bankName.tr.toLowerCase();
        final enName = rule.bankName.toLowerCase();
        if (noteLower.contains(faName) ||
            noteLower.contains(enName) ||
            rule.bodyHints.any((h) => noteLower.contains(h.toLowerCase()))) {
          return (
            'bank:${rule.id}',
            rule.bankName.tr,
            Icons.account_balance_rounded,
            const Color(0xFF0F766E),
          );
        }
      }
      if (t.credit) {
        return (
          'source:credit',
          'Customer credit accounts'.tr,
          Icons.switch_account_rounded,
          const Color(0xFF6366F1),
        );
      }
      return (
        'source:cash',
        'Cash and wallet'.tr,
        Icons.account_balance_wallet_rounded,
        const Color(0xFF087F78),
      );
    }

    for (final t in Ledger.filter(
      repo.transactions,
      from: from,
      to: to,
      scope: scope,
    )) {
      final isIn = Ledger.isRecognizedIncome(t) ||
          (t.kind == TxnKind.income && t.credit);
      final isOut = t.kind == TxnKind.expense ||
          t.kind == TxnKind.refund ||
          t.kind == TxnKind.payablePayment;
      if (!isIn && !isOut) continue;

      final (key, title, icon, accent) = detectBank(t);
      final v = Ledger.base(t);
      titles[key] = title;
      icons[key] = icon;
      accents[key] = accent;
      if (isIn) {
        inflows[key] = (inflows[key] ?? 0) + v;
      } else {
        outflows[key] = (outflows[key] ?? 0) + v;
      }
      (txnsByKey[key] ??= <Txn>[]).add(t);

      if (!masks.containsKey(key)) {
        final match = _cardMaskRe.firstMatch(t.note);
        if (match != null) {
          masks[key] = match.group(0)!;
        }
      }
    }

    final allKeys = {...inflows.keys, ...outflows.keys};
    final out = <_SourceStat>[
      for (final k in allKeys)
        _SourceStat(
          key: k,
          title: titles[k] ?? k,
          cardMask: masks[k],
          icon: icons[k] ?? Icons.account_balance_rounded,
          accent: accents[k] ?? AppTheme.seed,
          inflow: inflows[k] ?? 0,
          outflow: outflows[k] ?? 0,
          txnCount: txnsByKey[k]?.length ?? 0,
          transactions: (txnsByKey[k] ?? const <Txn>[])
            ..sort((a, b) => b.date.compareTo(a.date)),
        ),
    ]..sort((a, b) => (b.inflow + b.outflow).compareTo(a.inflow + a.outflow));
    return out;
  }

  Future<void> _pickCustomDateRange(
    BuildContext context,
    DateTime currentFrom,
    DateTime currentTo,
  ) async {
    var tempFrom = _customFrom ?? currentFrom;
    var tempTo = _customTo ?? currentTo;

    final applied = await showLedgerSheet<bool>(
      context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final onSurface = Theme.of(ctx).colorScheme.onSurface;
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(ctx).cardColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SheetHandle(),
                  const SizedBox(height: 12),
                  Text(
                    'Select date range'.tr,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _dateBox(
                          ctx,
                          label: 'From date'.tr,
                          date: tempFrom,
                          onSurface: onSurface,
                          onTap: () async {
                            final picked = await showJalaliPicker(
                              ctx,
                              initial: tempFrom,
                            );
                            if (picked != null) {
                              setSheetState(() => tempFrom = picked);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _dateBox(
                          ctx,
                          label: 'To date'.tr,
                          date: tempTo,
                          onSurface: onSurface,
                          onTap: () async {
                            final picked = await showJalaliPicker(
                              ctx,
                              initial: tempTo,
                            );
                            if (picked != null) {
                              setSheetState(() => tempTo = picked);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text('Apply'.tr),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (applied == true && mounted) {
      setState(() {
        _customFrom = tempFrom;
        _customTo = tempTo;
        _range = _Range.custom;
        _periodOffset = 0;
        _chartModeOverride = null;
      });
    }
  }

  Widget _dateBox(
    BuildContext context, {
    required String label,
    required DateTime date,
    required Color onSurface,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: onSurface.withValues(alpha: 0.62),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 14,
                  color: scheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    J.d(date),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final (from, to) = _bounds(repo);
    final scope = _scope;
    final scopedTxns = repo.scopeTxns(scope);
    final s = repo.summary(from: from, to: to, scope: scope);
    final prevRange = _tab == _ReportTab.stats ? _previousBounds(from, to) : null;
    final prevSummary = prevRange == null
        ? null
        : repo.summary(from: prevRange.$1, to: prevRange.$2, scope: scope);

    final daysSpan = J.daysBetween(from, to).clamp(1, 3660);
    final monthsSpan = _monthsBetween(from, to);

    // Only compute the chart series needed for the active tab & chart mode.
    final chartMode = _effectiveChartMode;
    final dailyChartDays = _range == _Range.daily
        ? 14
        : _range == _Range.weekly
        ? 7
        : daysSpan.clamp(7, 30);
    final dailyPoints = (_tab == _ReportTab.stats && chartMode == 0)
        ? Ledger.dailySeries(
            scopedTxns,
            days: dailyChartDays,
            endDay: to,
            scope: scope,
          )
        : const <DayPoint>[];
    final weeklyChartWeeks =
        (_range == _Range.weekly ? 8 : (daysSpan / 7).ceil()).clamp(4, 12);
    final weeklyPoints = (_tab == _ReportTab.stats && chartMode == 1)
        ? Ledger.weeklySeries(
            scopedTxns,
            weeks: weeklyChartWeeks,
            endDay: to,
            scope: scope,
          )
        : const <DayPoint>[];
    final monthlyPoints = (_tab == _ReportTab.stats && chartMode == 2)
        ? Ledger.monthlySeries(
            scopedTxns,
            months: math.max(monthsSpan, 6),
            endMonth: to,
            scope: scope,
          )
        : const <MonthPoint>[];

    final expenseStats = _tab == _ReportTab.categories
        ? _computeCategoryStats(
            repo,
            from: from,
            to: to,
            kind: TxnKind.expense,
            scope: scope,
          )
        : const <_CategoryStat>[];
    final incomeStats = _tab == _ReportTab.categories
        ? _computeCategoryStats(
            repo,
            from: from,
            to: to,
            kind: TxnKind.income,
            scope: scope,
          )
        : const <_CategoryStat>[];

    final expenseCatsMap = <String, double>{
      for (final c in expenseStats) c.name: c.amount,
    };
    final incomeCatsMap = <String, double>{
      for (final c in incomeStats) c.name: c.amount,
    };

    final top = _tab == _ReportTab.sources
        ? Ledger.topCustomers(
            repo.customers,
            scopedTxns,
            from: from,
            to: to,
            limit: 6,
            scope: scope,
          )
        : const <MapEntry<Customer, double>>[];
    final debtors = _tab == _ReportTab.sources
        ? repo.debtorsList()
        : const <MapEntry<Customer, double>>[];
    final margin = s.income > 0 ? s.profit / s.income : 0.0;

    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
      children: [
        // 1. Three-Tab Report Switcher (Statistics | Categories | Sources & Balances)
        _buildReportTabBar(context),
        const SizedBox(height: 10),

        // 2. Unified Filter & Period Stepper Card
        CardBox(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Scope & Range selector row
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
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          label: Text(
                            opt == null ? 'All'.tr : opt.label,
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          showCheckmark: false,
                          selected: _scope == opt,
                          onSelected: (_) => setState(() => _scope = opt),
                        ),
                      ),
                    Container(
                      width: 1,
                      height: 20,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.14),
                    ),
                    for (final r in _Range.values) ...[
                      ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        label: Text(
                          _rangeLabel(r).tr,
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        showCheckmark: false,
                        selected: _range == r,
                        onSelected: (_) {
                          if (r == _Range.custom) {
                            _pickCustomDateRange(context, from, to);
                          } else {
                            setState(() {
                              _range = r;
                              _periodOffset = 0;
                              _chartModeOverride = null;
                            });
                          }
                        },
                      ),
                      const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Period / Month navigator bar
              _buildPeriodNavigator(context, from, to),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Tab 0: Statistics & Trend
        if (_tab == _ReportTab.stats) ...[
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
          const SectionTitle('Export', icon: Icons.ios_share_rounded),
          _buildExportCard(context, repo, from, to),
        ]
        // Tab 1: Categories & Subcategories Breakdown
        else if (_tab == _ReportTab.categories) ...[
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
          ),
        ]
        // Tab 2: Sources (Banks) & Account Balances
        else ...[
          SectionTitle(
            'Bank and payment sources',
            icon: Icons.account_balance_rounded,
          ),
          _buildSourcesSection(
            context,
            repo: repo,
            from: from,
            to: to,
            scope: scope,
          ),
          SectionTitle(
            'Balances report',
            icon: Icons.account_balance_wallet_outlined,
          ),
          _buildBalancesReportCard(
            context,
            repo: repo,
            summary: s,
            scope: scope,
          ),
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
          if (scope != TxnScope.personal) ...[
            const SectionTitle(
              'Debtors',
              icon: Icons.people_outline_rounded,
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
        ],
      ],
    );
  }

  Widget _buildReportTabBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = <(_ReportTab, String, IconData)>[
      (_ReportTab.stats, 'Statistics'.tr, Icons.bar_chart_rounded),
      (_ReportTab.categories, 'Categories'.tr, Icons.donut_large_rounded),
      (
        _ReportTab.sources,
        'Sources & balances'.tr,
        Icons.account_balance_rounded,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          for (final (tab, label, icon) in items)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _tab = tab),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _tab == tab
                        ? Theme.of(context).cardColor
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10.5),
                    border: Border.all(
                      color: _tab == tab
                          ? scheme.primary.withValues(alpha: 0.42)
                          : Colors.transparent,
                    ),
                    boxShadow: _tab == tab
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : const [],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        icon,
                        size: 15,
                        color: _tab == tab
                            ? scheme.primary
                            : scheme.onSurface.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: _tab == tab
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: _tab == tab
                                ? scheme.primary
                                : scheme.onSurface.withValues(alpha: 0.68),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPeriodNavigator(
    BuildContext context,
    DateTime from,
    DateTime to,
  ) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final scheme = Theme.of(context).colorScheme;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final isMonthly =
        _range == _Range.thisMonth || _range == _Range.lastMonth;
    final String primaryTitle;
    final String? secondarySub;
    if (isMonthly) {
      primaryTitle = J.mLabel(from);
      secondarySub = '${J.dShort(from)} - ${J.dShort(to)}';
    } else if (_range == _Range.daily) {
      primaryTitle = J.dFull(from);
      secondarySub = null;
    } else if (_range == _Range.weekly) {
      primaryTitle = '${J.dShort(from)} - ${J.dLong(to)}';
      secondarySub = null;
    } else {
      primaryTitle = '${J.dLong(from)} - ${J.dLong(to)}';
      secondarySub = null;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          if (_canStepPeriod)
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              tooltip: 'Previous period'.tr,
              icon: Icon(
                isRtl
                    ? Icons.chevron_right_rounded
                    : Icons.chevron_left_rounded,
                textDirection: TextDirection.ltr,
                size: 20,
              ),
              onPressed: () => setState(() => _periodOffset -= 1),
            ),
          Expanded(
            child: InkWell(
              onTap: () => _pickCustomDateRange(context, from, to),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.calendar_month_rounded,
                      size: 15,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        primaryTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: onSurface.withValues(alpha: 0.90),
                        ),
                      ),
                    ),
                    if (secondarySub != null) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '($secondarySub)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: onSurface.withValues(alpha: 0.56),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (_periodOffset != 0)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _periodOffset = 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Today'.tr,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          if (_canStepPeriod)
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              tooltip: 'Next period'.tr,
              icon: Icon(
                isRtl
                    ? Icons.chevron_left_rounded
                    : Icons.chevron_right_rounded,
                textDirection: TextDirection.ltr,
                size: 20,
              ),
              onPressed: _periodOffset < 0
                  ? () => setState(() => _periodOffset += 1)
                  : null,
            ),
        ],
      ),
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

    final (healthLabel, healthColor) =
        summary.income <= 0 && summary.expense <= 0
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
          palette: _expensePalette,
        );
        final incomeChart = _MiniCategoryDonutCard(
          title: 'Total income'.tr,
          total: totalIncome,
          accentColor: AppTheme.revenue,
          data: incomeData,
          palette: _incomePalette,
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
    final countText = '{count} txns'.trArgs({
      'count': Fmt.number(stat.txnCount),
    });
    final subCountText = subEntries.isNotEmpty
        ? ' • ${'Subcategories count: {count}'.trArgs({'count': Fmt.number(subEntries.length)})}'
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CardBox(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        onTap: () => _showCategoryTransactionsSheet(
          context,
          repo: repo,
          title: stat.name.tr,
          total: stat.amount,
          color: color,
          subEntries: subEntries,
          transactions: stat.transactions,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    stat.kind == TxnKind.income
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                    size: 18,
                    color: color,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stat.name.tr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$countText$subCountText',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: onSurface.withValues(alpha: 0.58),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Money.text(stat.amount),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    if (totalOfKind > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        Fmt.percent(share),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: onSurface.withValues(alpha: 0.45),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: share,
                minHeight: 6,
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
          ],
        ),
      ),
    );
  }

  Widget _buildSourcesSection(
    BuildContext context, {
    required AppRepository repo,
    required DateTime from,
    required DateTime to,
    required TxnScope? scope,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final sources = _computeSourceStats(
      repo,
      from: from,
      to: to,
      scope: scope,
    );

    if (sources.isEmpty) {
      return CardBox(
        child: Text(
          'No transactions recorded in this period'.tr,
          style: TextStyle(
            fontSize: 12.5,
            color: onSurface.withValues(alpha: 0.65),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (final src in sources)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: CardBox(
              padding: const EdgeInsets.all(14),
              onTap: () => _showCategoryTransactionsSheet(
                context,
                repo: repo,
                title: src.title,
                total: src.net,
                color: src.accent,
                subEntries: const [],
                transactions: src.transactions,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: src.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(src.icon, size: 19, color: src.accent),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              src.title,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (src.cardMask != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                src.cardMask!,
                                textDirection: TextDirection.ltr,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: onSurface.withValues(alpha: 0.58),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: onSurface.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '{count} txns'.trArgs({
                            'count': Fmt.number(src.txnCount),
                          }),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _sourcePill(
                          context,
                          label: 'Paid out'.tr,
                          amount: src.outflow,
                          color: AppTheme.expense,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _sourcePill(
                          context,
                          label: 'Received'.tr,
                          amount: src.inflow,
                          color: AppTheme.revenue,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _sourcePill(
                          context,
                          label: 'Net balance'.tr,
                          amount: src.net,
                          color: const Color(0xFF4F46E5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _sourcePill(
    BuildContext context, {
    required String label,
    required double amount,
    required Color color,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: onSurface.withValues(alpha: 0.68),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              Money.text(amount, compact: true),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBalancesReportCard(
    BuildContext context, {
    required AppRepository repo,
    required Summary summary,
    required TxnScope? scope,
  }) {
    final rows = <(String, double, IconData, Color)>[
      (
        'Expense'.tr,
        summary.expense,
        Icons.trending_down_rounded,
        AppTheme.expense,
      ),
      (
        'Income'.tr,
        summary.income,
        Icons.trending_up_rounded,
        AppTheme.revenue,
      ),
      (
        'Cash + bank'.tr,
        scope == TxnScope.personal ? summary.netCash : repo.cashBalance,
        Icons.account_balance_rounded,
        const Color(0xFF0EA5A4),
      ),
      if (scope != TxnScope.personal) ...[
        (
          'Debtors'.tr,
          repo.totals.receivable,
          Icons.person_add_alt_1_rounded,
          AppTheme.receivable,
        ),
        (
          'Creditors'.tr,
          repo.totals.payable,
          Icons.person_remove_alt_1_rounded,
          AppTheme.payable,
        ),
      ],
    ];

    return Column(
      children: [
        for (final (title, value, icon, color) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CardBox(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, size: 19, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  MoneyText(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildExportCard(
    BuildContext context,
    AppRepository repo,
    DateTime from,
    DateTime to,
  ) {
    return CardBox(
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
    );
  }

  void _showCategoryTransactionsSheet(
    BuildContext context, {
    required AppRepository repo,
    required String title,
    required double total,
    required Color color,
    required List<MapEntry<String, double>> subEntries,
    required List<Txn> transactions,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    String? selectedSubKey;

    showLedgerSheet<void>(
      context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final filteredTxns = selectedSubKey == null
              ? transactions
              : transactions.where((t) {
                  final rawCat = repo.categoryById(t.categoryId);
                  if (rawCat != null && rawCat.parentId != null) {
                    return rawCat.name == selectedSubKey;
                  }
                  return selectedSubKey!.startsWith('General (');
                }).toList();

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.80,
            ),
            decoration: BoxDecoration(
              color: Theme.of(ctx).cardColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
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
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Text(
                      Money.text(total),
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
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Subcategories'.tr,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: onSurface.withValues(alpha: 0.72),
                          ),
                        ),
                      ),
                      if (selectedSubKey != null)
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () =>
                              setSheetState(() => selectedSubKey = null),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            child: Text(
                              'All subcategories'.tr,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final sub in subEntries) ...[
                    Builder(
                      builder: (_) {
                        final subShare = total > 0
                            ? (sub.value / total).clamp(0.0, 1.0)
                            : 0.0;
                        final isSelected = selectedSubKey == sub.key;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(11),
                            onTap: () => setSheetState(() {
                              selectedSubKey = isSelected ? null : sub.key;
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 11,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? color.withValues(alpha: 0.14)
                                    : color.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(
                                  color: isSelected
                                      ? color.withValues(alpha: 0.55)
                                      : color.withValues(alpha: 0.18),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          sub.key.tr,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: isSelected
                                                ? FontWeight.w800
                                                : FontWeight.w700,
                                            color: onSurface.withValues(
                                              alpha: 0.9,
                                            ),
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${Money.text(sub.value)} (${Fmt.percent(subShare)})',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: color,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(99),
                                    child: LinearProgressIndicator(
                                      value: subShare,
                                      minHeight: 4.5,
                                      backgroundColor: color.withValues(
                                        alpha: 0.12,
                                      ),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        color,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
                const SizedBox(height: 8),
                Divider(color: Theme.of(ctx).dividerColor),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: filteredTxns.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: Theme.of(ctx).dividerColor),
                    itemBuilder: (_, index) {
                      final t = filteredTxns[index];
                      final catLabel = repo.categoryName(t.categoryId);
                      final hasNote = t.note.trim().isNotEmpty;
                      final noteText = hasNote ? t.note.trim().tr : '';
                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () {
                          Navigator.pop(ctx);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => TransactionEditPage(existing: t),
                            ),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 4,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      catLabel,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (hasNote && noteText != catLabel) ...[
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.notes_rounded,
                                            size: 12,
                                            color: color.withValues(alpha: 0.8),
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              noteText,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                                color: onSurface.withValues(
                                                  alpha: 0.82,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 2),
                                    Text(
                                      J.d(t.date),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: onSurface.withValues(
                                          alpha: 0.56,
                                        ),
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
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
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

    Txn? largestExpenseTxn;
    var expenseCount = 0;
    var incomeCount = 0;
    final dayExpenses = <DateTime, double>{};
    final weekdayExpense = List<double>.filled(7, 0);
    final weekdayIncome = List<double>.filled(7, 0);

    int iranianWeekdayIndex(DateTime d) {
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
    _Range.custom => 'Select date range',
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
                SizedBox(
                  width: 58,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: MoneyText(
                      total,
                      compact: true,
                      withSymbol: false,
                      style: TextStyle(
                        fontSize: 12,
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
