import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format_utils.dart';
import '../core/jalali_utils.dart';
import '../data/ledger.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'customer_detail_page.dart';
import 'forms/sell_subscription_page.dart';
import 'widgets/widgets.dart';

import '../core/localization.dart';

class SubscriptionsPage extends StatefulWidget {
  const SubscriptionsPage({super.key});

  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

enum _SubFilter { all, active, soon, expired }

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  final _searchController = TextEditingController();
  _SubFilter _filter = _SubFilter.all;
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
    final reminder = repo.settings.reminderDays;

    final query = Fmt.normalizeSearchText(_q);
    final matchingSubscriptions = repo.subscriptions.where((s) {
      if (query.isEmpty) return true;
      return Fmt.normalizeSearchText(repo.customerName(s.customerId))
              .contains(query) ||
          Fmt.normalizeSearchText(s.planName).contains(query);
    }).toList();

    SubStatus statusOf(Subscription s) =>
        Ledger.subStatus(s, reminderDays: reminder);

    bool matchesFilter(Subscription s, _SubFilter filter) => switch (filter) {
      _SubFilter.all => true,
      _SubFilter.active => statusOf(s) == SubStatus.active,
      _SubFilter.soon => statusOf(s) == SubStatus.expiringSoon,
      _SubFilter.expired => statusOf(s) == SubStatus.expired,
    };

    int priority(Subscription s) => switch (statusOf(s)) {
      SubStatus.expiringSoon => 0,
      SubStatus.active => 1,
      SubStatus.expired => 2,
    };

    final list =
        matchingSubscriptions.where((s) => matchesFilter(s, _filter)).toList()
          ..sort((a, b) {
            final statusOrder = priority(a).compareTo(priority(b));
            if (statusOrder != 0) return statusOrder;
            return priority(a) == 2
                ? b.endDate.compareTo(a.endDate)
                : a.endDate.compareTo(b.endDate);
          });
    final hasActiveFilters = query.isNotEmpty || _filter != _SubFilter.all;

    int count(_SubFilter filter) =>
        matchingSubscriptions.where((s) => matchesFilter(s, filter)).length;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Column(
            children: [
              AppSearchField(
                controller: _searchController,
                hint: 'Search customers or plans...',
                onChanged: (v) => setState(() => _q = v),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _chip('All', _SubFilter.all, count(_SubFilter.all)),
                    const SizedBox(width: 8),
                    _chip(
                      'Active',
                      _SubFilter.active,
                      count(_SubFilter.active),
                    ),
                    const SizedBox(width: 8),
                    _chip(
                      'Expiring soon',
                      _SubFilter.soon,
                      count(_SubFilter.soon),
                    ),
                    const SizedBox(width: 8),
                    _chip(
                      'Expired',
                      _SubFilter.expired,
                      count(_SubFilter.expired),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? hasActiveFilters
                    ? EmptyState(
                        icon: Icons.vpn_key_outlined,
                        title: 'No subscriptions match these filters',
                        text: 'Try changing the search or subscription status filter.',
                        actionLabel: 'Clear search and status filter',
                        onAction: () => setState(() {
                          _searchController.clear();
                          _q = '';
                          _filter = _SubFilter.all;
                        }),
                      )
                    : EmptyState(
                        icon: Icons.vpn_key_outlined,
                        title: 'No subscriptions recorded yet.',
                        text: 'Record a sale to automatically create a customer subscription and expiry date.',
                        actionLabel: 'Sell a subscription',
                        onAction: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SellSubscriptionPage(),
                          ),
                        ),
                      )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 9),
                  itemBuilder: (context, i) {
                    final s = list[i];
                    final c = repo.customerById(s.customerId);
                    final status = Ledger.subStatus(s, reminderDays: reminder);
                    final days = Ledger.daysLeft(s);
                    final progress = _progress(s);
                    return CardBox(
                      onTap: c == null
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CustomerDetailPage(customer: c),
                              ),
                            ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c?.name ?? 'No customer'.tr,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      s.planName,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: onSurface.withValues(
                                          alpha: 0.65,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  MoneyText(
                                    s.amount,
                                    currency: s.currency,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  TagChip(
                                    status == SubStatus.expired
                                        ? '${'Expired'.tr} ${Fmt.expiryLabel(days)}'
                                        : Fmt.expiryLabel(days),
                                    color: status.color,
                                    dense: true,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              minHeight: 5,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.1),
                              valueColor: AlwaysStoppedAnimation(status.color),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(
                                Icons.date_range_rounded,
                                size: 14,
                                color: onSurface.withValues(alpha: 0.5),
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  '{from} to {to}'.trArgs({
                                    'from': J.d(s.startDate),
                                    'to': J.d(s.endDate),
                                  }),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                              ),
                              TextButton.icon(
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        SellSubscriptionPage(renewFrom: s),
                                  ),
                                ),
                                icon: const Icon(
                                  Icons.autorenew_rounded,
                                  size: 16,
                                ),
                                label: Text(
                                  'Renew'.tr,
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  double _progress(Subscription s) {
    final total = s.endDate.difference(s.startDate).inDays;
    if (total <= 0) return 1;
    final passed = DateTime.now().difference(s.startDate).inDays;
    return (passed / total).clamp(0.0, 1.0);
  }

  Widget _chip(String label, _SubFilter value, int n) => ChoiceChip(
    selected: _filter == value,
    showCheckmark: false,
    onSelected: (_) => setState(() => _filter = value),
    label: Text('${label.tr} ($n)'),
  );
}
