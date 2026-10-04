import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/jalali_utils.dart';
import '../core/money.dart';
import '../data/ledger.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'forms/transaction_edit_page.dart';
import 'widgets/widgets.dart';

class TransactionsPage extends StatefulWidget {
  const TransactionsPage({super.key});

  @override
  State<TransactionsPage> createState() => _TransactionsPageState();
}

class _TransactionsPageState extends State<TransactionsPage> {
  int _monthOffset = 0; // 0 = ماه جاری
  TxnKind? _kind;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final monthStart = J.startOfMonth(J.addMonths(DateTime.now(), _monthOffset));
    final monthEnd = J.endOfMonth(monthStart);
    final summary =
        repo.summary(from: monthStart, to: monthEnd, scope: repo.scopeFilter);

    var list = (repo.scopeFilter == null
            ? repo.transactions
            : repo.transactions.where((t) => t.scope == repo.scopeFilter))
        .where((t) => Ledger.inRange(t.date, monthStart, monthEnd))
        .toList();
    if (_kind != null) list = list.where((t) => t.kind == _kind).toList();
    if (_q.isNotEmpty) {
      list = list
          .where((t) =>
              t.note.contains(_q) ||
              repo.customerName(t.customerId).contains(_q) ||
              repo.categoryName(t.categoryId).contains(_q))
          .toList();
    }

    // گروه‌بندی بر اساس تاریخ
    final groups = <String, List<Txn>>{};
    for (final t in list) {
      final key = J.d(t.date);
      groups.putIfAbsent(key, () => []).add(t);
    }

    return Column(
      children: [
        // نوار ماه
        Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          child: Row(
            children: [
              IconButton(
                tooltip: 'ماه قبل',
                onPressed: () => setState(() => _monthOffset--),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              Expanded(
                child: Center(
                  child: Column(
                    children: [
                      Text(J.mLabel(monthStart),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        'درآمد ${Money.text(summary.income, compact: true)} • هزینه ${Money.text(summary.expense, compact: true)}',
                        style: TextStyle(
                            fontSize: 11, color: onSurface.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                tooltip: 'ماه بعد',
                onPressed: _monthOffset < 0
                    ? () => setState(() => _monthOffset++)
                    : null,
                icon: const Icon(Icons.chevron_left_rounded),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            children: [
              TextField(
                decoration: const InputDecoration(
                  hintText: 'جست‌وجو در توضیح، مشتری، دسته…',
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
              const SizedBox(height: 10),
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
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ChoiceChip(
                      label: const Text('همه'),
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
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: list.isEmpty
              ? const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'تراکنشی در این ماه نیست',
                  text: 'با دکمه‌ی + یک فروش، دریافت یا هزینه ثبت کنید.',
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  children: [
                    for (final entry in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                        child: Row(
                          children: [
                            Text(entry.key,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: onSurface.withValues(alpha: 0.6))),
                            const Spacer(),
                            Text(
                              Money.text(
                                entry.value.fold<double>(
                                    0,
                                    (a, t) =>
                                        a +
                                        (t.kind == TxnKind.expense ||
                                                t.kind == TxnKind.refund
                                            ? -Ledger.base(t)
                                            : Ledger.base(t))),
                                compact: true,
                              ),
                              style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: onSurface.withValues(alpha: 0.6)),
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
                                categoryName: repo.categoryName(entry.value[i].categoryId),
                                customerName: repo.customerName(entry.value[i].customerId),
                                onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => TransactionEditPage(
                                            existing: entry.value[i]))),
                              ),
                              if (i != entry.value.length - 1)
                                Divider(height: 1, color: Theme.of(context).dividerColor),
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
}
