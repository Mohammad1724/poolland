import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format_utils.dart';
import '../core/jalali_utils.dart';
import '../core/money.dart';
import '../data/ledger.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'forms/transaction_edit_page.dart';
import 'widgets/widgets.dart';

import '../core/localization.dart';

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  final _searchController = TextEditingController();
  int _monthOffset = 0; // 0 = current month
  TxnKind? _kind;
  String _q = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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

    final monthTransactions =
        (repo.scopeFilter == null
                ? repo.transactions
                : repo.transactions.where((t) => t.scope == repo.scopeFilter))
            .where((t) => Ledger.inRange(t.date, monthStart, monthEnd))
            .toList();
    var list = monthTransactions;
    if (_kind != null) list = list.where((t) => t.kind == _kind).toList();
    final query = Fmt.normalizeSearchText(_q);
    if (query.isNotEmpty) {
      list = list
          .where(
            (t) =>
                Fmt.normalizeSearchText(t.note).contains(query) ||
                Fmt.normalizeSearchText(repo.customerName(t.customerId))
                    .contains(query) ||
                Fmt.normalizeSearchText(repo.categoryName(t.categoryId))
                    .contains(query),
          )
          .toList();
    }
    final hasActiveFilters = query.isNotEmpty || _kind != null;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    // Group by date
    final groups = <String, List<Txn>>{};
    for (final t in list) {
      final key = J.d(t.date);
      groups.putIfAbsent(key, () => []).add(t);
    }

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
                icon: Icon(
                  isRtl
                      ? Icons.chevron_right_rounded
                      : Icons.chevron_left_rounded,
                ),
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
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 10,
                        runSpacing: 2,
                        children: [
                          _monthAmount(context, 'Income', summary.income),
                          _monthAmount(context, 'Expense', summary.expense),
                        ],
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
                icon: Icon(
                  isRtl
                      ? Icons.chevron_left_rounded
                      : Icons.chevron_right_rounded,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              AppSearchField(
                controller: _searchController,
                hint: 'Search descriptions, customers, and categories...',
                isDense: true,
                onChanged: (v) => setState(() => _q = v),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    'Scope'.tr,
                    style: TextStyle(
                      fontSize: 11,
                      color: onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final opt in <TxnScope?>[
                            null,
                            TxnScope.business,
                            TxnScope.personal,
                          ])
                            Padding(
                              padding: const EdgeInsetsDirectional.only(
                                start: 6,
                              ),
                              child: ChoiceChip(
                                label: Text(
                                  opt == null ? 'All'.tr : opt.label,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                showCheckmark: false,
                                selected: repo.scopeFilter == opt,
                                onSelected: (_) => repo.setScopeFilter(opt),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Type'.tr,
                    style: TextStyle(
                      fontSize: 11,
                      color: onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            label: Text('All'.tr),
                            showCheckmark: false,
                            selected: _kind == null,
                            onSelected: (_) => setState(() => _kind = null),
                          ),
                          for (final k in TxnKind.values) ...[
                            const SizedBox(width: 8),
                            ChoiceChip(
                              avatar: Icon(k.icon, size: 15),
                              label: Text(k.shortLabel),
                              showCheckmark: false,
                              selected: _kind == k,
                              onSelected: (_) => setState(() => _kind = k),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
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
                      ? 'No transactions match these filters'
                      : 'No transactions this month',
                  text: hasActiveFilters
                      ? 'Try changing or clearing the search and transaction type.'
                      : 'Tap + to record a sale, receipt, or expense.',
                  actionLabel: hasActiveFilters
                      ? 'Clear search and type filter'
                      : null,
                  onAction: hasActiveFilters
                      ? () => setState(() {
                          _searchController.clear();
                          _q = '';
                          _kind = null;
                        })
                      : null,
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  children: [
                    for (final entry in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                        child: Row(
                          children: [
                            Text(
                              entry.key,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                Money.text(
                                  entry.value.fold<double>(
                                    0,
                                    (a, t) =>
                                        a +
                                        (t.kind == TxnKind.expense ||
                                                t.kind == TxnKind.refund ||
                                                t.kind == TxnKind.payablePayment
                                            ? -Ledger.base(t)
                                            : Ledger.base(t)),
                                  ),
                                  compact: true,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textDirection: TextDirection.ltr,
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Card(
                        child: Column(
                          children: [
                            for (var i = 0; i < entry.value.length; i++) ...[
                              TxnTile(
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
                  ],
                ),
        ),
      ],
    );
  }

  Widget _monthAmount(BuildContext context, String label, double amount) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '${label.tr}:',
        style: TextStyle(
          fontSize: 10.5,
          color: Theme.of(context).colorScheme.onSurface
              .withValues(alpha: 0.62),
        ),
      ),
      const SizedBox(width: 3),
      MoneyText(
        amount,
        compact: true,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: label == 'Income'
              ? const Color(0xFF16A34A)
              : const Color(0xFFE11D48),
        ),
      ),
    ],
  );
}
