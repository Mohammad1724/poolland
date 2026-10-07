import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format_utils.dart';
import '../core/jalali_utils.dart';
import '../data/ledger.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'customer_detail_page.dart';
import 'design.dart';
import 'forms/sell_subscription_page.dart';
import 'sms_page.dart';
import 'widgets/common_charts.dart';
import 'widgets/quick_buttons.dart';
import 'widgets/widgets.dart';

import '../core/localization.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.onNavigate});

  final void Function(int index) onNavigate;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final monthStart = J.startOfMonth(DateTime.now());
    final monthEnd = J.endOfMonth(DateTime.now());
    final monthSummary = repo.summary(
      from: monthStart,
      to: monthEnd,
      scope: repo.scopeFilter,
    );
    final totals = repo.totals;
    final alerts = repo.alerts;
    final series = repo.series(months: 6, scope: repo.scopeFilter);
    final recent =
        (repo.scopeFilter == null
                ? repo.transactions
                : repo.transactions.where((t) => t.scope == repo.scopeFilter))
            .take(5)
            .toList();
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
      children: [
        // Welcome message
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hello 👋'.tr,
                    style: TextStyle(
                      fontSize: 13,
                      color: onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    J.mLabel(DateTime.now()),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            TagChip(
              '{count} active subscriptions'.trArgs({
                'count': repo.activeSubsCount,
              }),
              color: const Color(0xFF16A34A),
              icon: Icons.check_circle_rounded,
            ),
          ],
        ),
        const SizedBox(height: 14),

        // Scope filter (all / business / personal)
        Row(
          children: [
            for (final opt in <TxnScope?>[
              null,
              TxnScope.business,
              TxnScope.personal,
            ])
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 6),
                child: ChoiceChip(
                  selected: repo.scopeFilter == opt,
                  showCheckmark: false,
                  onSelected: (_) => repo.setScopeFilter(opt),
                  label: Text(
                    opt == null ? 'All'.tr : opt.label,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // Quick entry for frequent expenses
        if (repo.scopeFilter != TxnScope.business &&
            repo.quickExpenses.isNotEmpty) ...[
          CardBox(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.bolt_rounded, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Quick add'.tr,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: onSurface.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                QuickButtonsRow(),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Monthly summary
        CardBox(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This month'.tr,
                style: TextStyle(
                  fontSize: 12.5,
                  color: onSurface.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _miniStat(
                      context,
                      'Income received',
                      monthSummary.income,
                      const Color(0xFF16A34A),
                      Icons.trending_up_rounded,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 42,
                    color: Theme.of(context).dividerColor,
                  ),
                  Expanded(
                    child: _miniStat(
                      context,
                      'Expense',
                      monthSummary.expense,
                      const Color(0xFFE11D48),
                      Icons.trending_down_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(color: Theme.of(context).dividerColor),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.savings_rounded,
                    size: 18,
                    color: monthSummary.profit >= 0
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFE11D48),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Profit this month'.tr,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                  const Spacer(),
                  MoneyText(
                    monthSummary.profit,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: monthSummary.profit >= 0
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFE11D48),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Business receivables and payables are not meaningful in the personal-only view.
        if (repo.scopeFilter != TxnScope.personal)
          Row(
            children: [
              Expanded(
                child: CardBox(
                  onTap: () => onNavigate(2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Business receivables'.tr,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                      const SizedBox(height: 6),
                      MoneyText(
                        totals.receivable,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F766E),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '{count} debtors'.trArgs({
                          'count': totals.debtorsCount,
                        }),
                        style: TextStyle(
                          fontSize: 11,
                          color: onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CardBox(
                  onTap: () => onNavigate(2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Business payables'.tr,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                      const SizedBox(height: 6),
                      MoneyText(
                        totals.payable,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '{count} creditors'.trArgs({
                          'count': totals.creditorsCount,
                        }),
                        style: TextStyle(
                          fontSize: 11,
                          color: onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        const SizedBox(height: 10),
        if (repo.scopeFilter != TxnScope.personal)
          Row(
            children: [
              Expanded(
                child: CardBox(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Business cash balance'.tr,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                      const SizedBox(height: 6),
                      MoneyText(
                        repo.cashBalance,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF7C3AED),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Cash + bank'.tr,
                        style: TextStyle(
                          fontSize: 11,
                          color: onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: CardBox(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Received this month'.tr,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                      const SizedBox(height: 6),
                      MoneyText(
                        monthSummary.cashIn,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Cash + collections'.tr,
                        style: TextStyle(
                          fontSize: 11,
                          color: onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

        // Bank SMS (Android only)
        if (repo.smsSupported) ...[
          CardBox(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SmsPage()),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color:
                        (repo.smsPendingCount > 0
                                ? const Color(0xFF16A34A)
                                : const Color(0xFF7C3AED))
                            .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    Icons.sms_rounded,
                    size: 19,
                    color: repo.smsPendingCount > 0
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF7C3AED),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bank SMS'.tr,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        !repo.smsPermissionGranted
                            ? 'Grant access to identify incoming payments automatically'
                                  .tr
                            : repo.smsPendingCount > 0
                            ? '{count} transactions awaiting review'.trArgs({
                                'count': repo.smsPendingCount,
                              })
                            : 'No new items found'.tr,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                if (repo.smsPendingCount > 0)
                  TagChip(
                    '${repo.smsPendingCount}',
                    color: const Color(0xFF16A34A),
                    dense: true,
                  )
                else
                  const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],

        // Expiry alerts
        if (alerts.isNotEmpty) ...[
          SectionTitle(
            'Subscriptions expiring soon or expired',
            icon: Icons.notification_important_outlined,
            action: 'All'.tr,
            onAction: () => onNavigate(3),
          ),
          ...alerts.take(4).map((s) {
            final customer = repo.customerById(s.customerId);
            final status = Ledger.subStatus(
              s,
              reminderDays: repo.settings.reminderDays,
            );
            final days = Ledger.daysLeft(s);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CardBox(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                onTap: customer == null
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              CustomerDetailPage(customer: customer),
                        ),
                      ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            customer?.name ?? 'No customer'.tr,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${s.planName.tr} • ${J.d(s.endDate)}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    TagChip(
                      Fmt.expiryLabel(days),
                      color: status.color,
                      dense: true,
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'Renew'.tr,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SellSubscriptionPage(renewFrom: s),
                        ),
                      ),
                      icon: const Icon(Icons.autorenew_rounded, size: 19),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],

        // Chart. Collapsed by default: the title and the six-month total stay
        // in the header, and the bars open on tap so the page stays short.
        const SizedBox(height: 14),
        CollapsibleCard(
          title: 'Last 6 months',
          icon: Icons.bar_chart_rounded,
          summary: MoneyText(
            series.fold<double>(0, (sum, p) => sum + p.profit),
            compact: true,
            signed: true,
            style: const TextStyle(
              fontSize: FontSizes.small,
              fontWeight: FontWeight.w700,
            ),
          ),
          bodyPadding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: SizedBox(height: 190, child: MonthlyBarChart(points: series)),
        ),

        // Recent transactions
        SectionTitle(
          'Recent transactions',
          icon: Icons.receipt_long_outlined,
          action: 'All'.tr,
          onAction: () => onNavigate(4),
        ),
        if (recent.isEmpty)
          const EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'No transactions yet',
            text: 'Tap + to record your first sale or expense.',
          )
        else
          Card(
            child: Column(
              children: [
                for (var i = 0; i < recent.length; i++) ...[
                  TxnTile(
                    txn: recent[i],
                    categoryName: repo.categoryName(recent[i].categoryId),
                    customerName: repo.customerName(recent[i].customerId),
                  ),
                  if (i != recent.length - 1)
                    Divider(height: 1, color: Theme.of(context).dividerColor),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _miniStat(
    BuildContext context,
    String label,
    double value,
    Color color,
    IconData icon,
  ) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                color: onSurface.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        MoneyText(
          value,
          compact: false,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}
