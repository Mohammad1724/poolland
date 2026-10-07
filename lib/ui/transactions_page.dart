import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/debounce.dart';
import '../core/haptics.dart';
import '../core/jalali_utils.dart';
import '../core/money.dart';
import '../data/ledger.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'design.dart';
import 'forms/transaction_edit_page.dart';
import 'widgets/widgets.dart';

import '../core/localization.dart';

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key, this.controller});
  /// Owned by the shell, so tapping the already-open tab can scroll this page
  /// back to the top. Tests and other callers can leave it null.
  final ScrollController? controller;

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  final _searchDebouncer = Debouncer();
  final _searchController = TextEditingController();
  int _monthOffset = 0; // 0 = current month
  TxnKind? _kind;
  String _q = '';
  bool _filtersOpen = false;

  @override
  void dispose() {
    _searchDebouncer.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    final query = value.trim().toLowerCase();
    _searchDebouncer.cancel();
    if (query.isEmpty) {
      if (_q.isNotEmpty) setState(() => _q = '');
      return;
    }
    _searchDebouncer.run(() {
      if (mounted) setState(() => _q = query);
    });
  }

  void _clearSearchAndFilters() {
    _searchDebouncer.cancel();
    _searchController.clear();
    context.read<AppRepository>().setScopeFilter(null);
    setState(() {
      _q = '';
      _kind = null;
    });
  }

  /// Number of filters currently narrowing the list (scope + type).
  /// Shown on the filter button badge so the state stays visible while the
  /// chips themselves are tucked away inside the panel.
  int get _activeFilterCount =>
      (context.read<AppRepository>().scopeFilter == null ? 0 : 1) +
      (_kind == null ? 0 : 1);

  void _resetFilters() {
    context.read<AppRepository>().setScopeFilter(null);
    setState(() => _kind = null);
  }

  Widget _filterGroupLabel(String label) => Text(
    label.tr,
    style: TextStyle(
      fontSize: FontSizes.small,
      fontWeight: FontWeight.w700,
      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final monthStart = J.startOfMonth(
      J.addMonths(DateTime.now(), _monthOffset),
    );
    final monthEnd = J.endOfMonth(monthStart);
    final summary = repo.summary(
      from: monthStart,
      to: monthEnd,
      scope: repo.scopeFilter,
    );

    var list =
        (repo.scopeFilter == null
                ? repo.transactions
                : repo.transactions.where((t) => t.scope == repo.scopeFilter))
            .where((t) => Ledger.inRange(t.date, monthStart, monthEnd))
            .toList();
    if (_kind != null) list = list.where((t) => t.kind == _kind).toList();
    if (_q.isNotEmpty) {
      list = list
          .where(
            (t) =>
                t.note.toLowerCase().contains(_q) ||
                repo.customerName(t.customerId).toLowerCase().contains(_q) ||
                repo.categoryName(t.categoryId).toLowerCase().contains(_q),
          )
          .toList();
    }

    // Group by date
    final groups = <String, List<Txn>>{};
    for (final t in list) {
      final key = J.d(t.date);
      groups.putIfAbsent(key, () => []).add(t);
    }
    // Materialized once so the list below can lazily build only the days that
    // are actually on screen.
    final groupList = groups.entries.toList(growable: false);
    final hasActiveFilters = _q.isNotEmpty || _activeFilterCount > 0;

    return Column(
      children: [
        // Month navigation bar
        Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Previous month'.tr,
                onPressed: () => setState(() => _monthOffset--),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Center(
                  child: Column(
                    children: [
                      Text(
                        J.mLabel(monthStart),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Income ${Money.text(summary.income, compact: true)} • Expense ${Money.text(summary.expense, compact: true)}',
                        style: TextStyle(
                          fontSize: 11,
                          color: onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next month'.tr,
                onPressed: _monthOffset < 0
                    ? () => setState(() => _monthOffset++)
                    : null,
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              // Search stays in view; the filter chips moved into a panel
              // behind the button below, so the list gets the space instead.
              Row(
                children: [
                  Expanded(
                    child: SearchField(
                      controller: _searchController,
                      hint: 'Search descriptions, customers, and categories...',
                      onChanged: _onSearchChanged,
                    ),
                  ),
                  const SizedBox(width: Insets.sm),
                  FilterToggleButton(
                    activeCount: _activeFilterCount,
                    expanded: _filtersOpen,
                    onPressed: () =>
                        setState(() => _filtersOpen = !_filtersOpen),
                  ),
                ],
              ),
              if (_activeFilterCount > 0) ...[
                const SizedBox(height: Insets.sm),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      if (repo.scopeFilter != null) ...[
                        FilterPill(
                          label: repo.scopeFilter!.label,
                          icon: Icons.pie_chart_outline_rounded,
                          onClear: () => repo.setScopeFilter(null),
                        ),
                        const SizedBox(width: Insets.sm),
                      ],
                      if (_kind != null) ...[
                        FilterPill(
                          label: _kind!.shortLabel,
                          icon: _kind!.icon,
                          onClear: () => setState(() => _kind = null),
                        ),
                        const SizedBox(width: Insets.sm),
                      ],
                    ],
                  ),
                ),
              ],
              AnimatedSize(
                duration: Motion.adaptive(context, Motion.expand),
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _filtersOpen
                    ? Padding(
                        padding: const EdgeInsets.only(top: Insets.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _filterGroupLabel('Scope'),
                            const SizedBox(height: Insets.sm),
                            Wrap(
                              spacing: Insets.sm,
                              runSpacing: Insets.sm,
                              children: [
                                for (final opt in <TxnScope?>[
                                  null,
                                  TxnScope.business,
                                  TxnScope.personal,
                                ])
                                  ChoiceChip(
                                    label: Text(
                                      opt == null ? 'All'.tr : opt.label,
                                      style: const TextStyle(
                                        fontSize: FontSizes.small,
                                      ),
                                    ),
                                    showCheckmark: false,
                                    selected: repo.scopeFilter == opt,
                                    onSelected: (_) =>
                                        repo.setScopeFilter(opt),
                                  ),
                              ],
                            ),
                            const SizedBox(height: Insets.md),
                            _filterGroupLabel('Type'),
                            const SizedBox(height: Insets.sm),
                            Wrap(
                              spacing: Insets.sm,
                              runSpacing: Insets.sm,
                              children: [
                                ChoiceChip(
                                  label: Text('All'.tr),
                                  showCheckmark: false,
                                  selected: _kind == null,
                                  onSelected: (_) =>
                                      setState(() => _kind = null),
                                ),
                                for (final k in TxnKind.values)
                                  ChoiceChip(
                                    avatar: Icon(k.icon, size: 15),
                                    label: Text(k.shortLabel),
                                    showCheckmark: false,
                                    selected: _kind == k,
                                    onSelected: (_) =>
                                        setState(() => _kind = k),
                                  ),
                              ],
                            ),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton.icon(
                                onPressed: _activeFilterCount == 0
                                    ? null
                                    : _resetFilters,
                                icon: const Icon(
                                  Icons.restart_alt_rounded,
                                  size: 16,
                                ),
                                label: Text('Reset'.tr),
                              ),
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: list.isEmpty
              ? EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: hasActiveFilters
                      ? 'No items found'
                      : 'No transactions this month',
                  text: hasActiveFilters
                      ? 'Try a different search or filter.'
                      : 'Tap + to record a sale, receipt, or expense.',
                  actionLabel: hasActiveFilters
                      ? 'Clear search and filters'
                      : null,
                  onAction: hasActiveFilters ? _clearSearchAndFilters : null,
                )
              : ListView.builder(
                  controller: widget.controller,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  itemCount: groupList.length,
                  itemBuilder: (context, groupIndex) {
                    final entry = groupList[groupIndex];
                    final dayTotal = entry.value.fold<double>(
                      0,
                      (a, t) =>
                          a +
                          (t.kind == TxnKind.expense ||
                                  t.kind == TxnKind.refund ||
                                  t.kind == TxnKind.payablePayment
                              ? -Ledger.base(t)
                              : Ledger.base(t)),
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                          child: Row(
                            children: [
                              Text(
                                entry.key,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                Money.text(dayTotal, compact: true),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Card(
                          // Clips the swipe hint to the card's rounded corners,
                          // so a row can slide without spilling over the edge.
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (
                                var i = 0;
                                i < entry.value.length;
                                i++
                              ) ...[
                                // Swiping is a shortcut for the two things done
                                // most often with an old entry: fixing it, or
                                // recording the same thing again. The row snaps
                                // back (nothing is dismissed), and the hint
                                // behind it names the action being performed.
                                Dismissible(
                                  key: ValueKey(
                                    'txn-swipe-${entry.value[i].id}',
                                  ),
                                  direction: DismissDirection.horizontal,
                                  dismissThresholds: const {
                                    // Resolved directions, not
                                    // [DismissDirection.horizontal].
                                    DismissDirection.startToEnd: 0.25,
                                    DismissDirection.endToStart: 0.25,
                                  },
                                  background: SwipeHint(
                                    icon: Icons.edit_rounded,
                                    label: 'Edit',
                                    color: Theme.of(context).colorScheme.primary,
                                    alignment: AlignmentDirectional.centerStart,
                                  ),
                                  secondaryBackground: SwipeHint(
                                    icon: Icons.copy_all_rounded,
                                    label: 'Duplicate',
                                    color: const Color(0xFF2563EB),
                                    alignment: AlignmentDirectional.centerEnd,
                                  ),
                                  confirmDismiss: (direction) async {
                                    Haptics.tap();
                                    final txn = entry.value[i];
                                    if (direction ==
                                        DismissDirection.startToEnd) {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) =>
                                              TransactionEditPage(existing: txn),
                                        ),
                                      );
                                    } else {
                                      await Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => TransactionEditPage(
                                            duplicateOf: txn,
                                          ),
                                        ),
                                      );
                                    }
                                    return false;
                                  },
                                  child: TxnTile(
                                    txn: entry.value[i],
                                    categoryName: repo.categoryName(
                                      entry.value[i].categoryId,
                                    ),
                                    customerName: repo.customerName(
                                      entry.value[i].customerId,
                                    ),
                                    onTap: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => TransactionEditPage(
                                          existing: entry.value[i],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                if (i != entry.value.length - 1)
                                  Divider(
                                    height: 1,
                                    color: Theme.of(context).dividerColor,
                                  ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}
