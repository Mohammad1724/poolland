import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/debounce.dart';
import '../core/format_utils.dart';
import '../core/haptics.dart';
import '../core/jalali_utils.dart';
import '../core/localization.dart';
import '../core/money.dart';
import '../data/ledger.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'customer_detail_page.dart';
import 'design.dart';
import 'forms/payment_sheet.dart';
import 'forms/sell_subscription_page.dart';
import 'motion_kit.dart';
import 'widgets/widgets.dart';

class SubscriptionsPage extends StatefulWidget {
  const SubscriptionsPage({super.key, this.controller});
  /// Owned by the shell, so tapping the already-open tab can scroll this page
  /// back to the top. Tests and other callers can leave it null.
  final ScrollController? controller;

  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

enum _SubFilter { all, active, soon, expired }

enum _SubSort { nearestExpiry, newestSale, highestAmount }

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  final _searchDebouncer = Debouncer();
  final _searchController = TextEditingController();
  _SubFilter _filter = _SubFilter.all;
  _SubSort _sort = _SubSort.nearestExpiry;
  bool _showHistory = false;
  String _q = '';
  bool _filtersOpen = false;

  @override
  void dispose() {
    _searchDebouncer.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    final query = value.trim();
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
    setState(() {
      _q = '';
      _filter = _SubFilter.all;
      _sort = _SubSort.nearestExpiry;
      _showHistory = false;
    });
  }

  String get _filterLabel => switch (_filter) {
    _SubFilter.all => 'All',
    _SubFilter.active => 'Active',
    _SubFilter.soon => 'Expiring soon',
    _SubFilter.expired => 'Expired',
  };

  void _copyReminder(
    BuildContext context,
    Subscription s,
    Customer? c,
    double balance,
    int reminderDays,
  ) {
    final days = Ledger.daysLeft(s);
    final status = Ledger.subStatus(s, reminderDays: reminderDays);
    final statusText = status == SubStatus.expired
        ? '${'Expired'.tr} ${Fmt.expiryLabel(days)}'
        : Fmt.expiryLabel(days);
    final lines = <String>[
      'Hello {name} 👋\nSubscription: {plan}\nExpiry date: {date} ({status})\nRenewal amount: {amount}'
          .trArgs({
            'name': c?.name ?? 'Customer'.tr,
            'plan': s.planName.tr,
            'date': J.d(s.endDate),
            'status': statusText,
            'amount': Money.text(s.amount, currency: s.currency),
          }),
      if (balance > 0.5)
        'Previous balance due: {debt}'.trArgs({
          'debt': Money.text(balance),
        }),
    ];
    Clipboard.setData(ClipboardData(text: lines.join('\n')));
    showSnack(context, 'Reminder message copied');
  }

  Future<void> _subscriptionActions(
    BuildContext context,
    Subscription s,
    Customer? c,
    double balance,
    int reminderDays,
  ) async {
    Haptics.tap();
    final repo = context.read<AppRepository>();
    final choice = await showLedgerSheet<String>(
      context,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SheetHandle(),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(
                  Icons.copy_rounded,
                  color: Color(0xFF0F766E),
                ),
                title: Text('Copy renewal reminder'.tr),
                onTap: () => Navigator.pop(ctx, 'copy'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.autorenew_rounded,
                  color: Color(0xFF2563EB),
                ),
                title: Text('Renew'.tr),
                onTap: () => Navigator.pop(ctx, 'renew'),
              ),
              if (c != null)
                ListTile(
                  leading: const Icon(
                    Icons.call_received_rounded,
                    color: Color(0xFF16A34A),
                  ),
                  title: Text('Receive from customer'.tr),
                  onTap: () => Navigator.pop(ctx, 'receive'),
                ),
              ListTile(
                leading: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFE11D48),
                ),
                title: Text(
                  'Delete subscription'.tr,
                  style: const TextStyle(color: Color(0xFFE11D48)),
                ),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'copy') {
      _copyReminder(context, s, c, balance, reminderDays);
    } else if (choice == 'renew') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => SellSubscriptionPage(renewFrom: s)),
      );
    } else if (choice == 'receive' && c != null) {
      await showPaymentSheet(context, customer: c, isReceive: true);
    } else if (choice == 'delete') {
      final ok = await confirmDialog(
        context,
        title: 'Delete subscription'.tr,
        message:
            'Delete this subscription? Recorded transactions will stay in the ledger.'
                .tr,
        okLabel: 'Delete'.tr,
        danger: true,
      );
      if (ok && context.mounted) {
        await repo.deleteSubscription(s.id);
        if (context.mounted) showSnack(context, 'Subscription deleted');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final reminder = repo.settings.reminderDays;
    final compact = MediaQuery.sizeOf(context).width < 360;
    final balances = repo.balancesMap();

    final allSubs = repo.subscriptions;
    final hasSuperseded = allSubs.any((s) => Ledger.isSuperseded(s, allSubs));
    final visiblePool = _showHistory
        ? [...allSubs]
        : allSubs.where((s) => !Ledger.isSuperseded(s, allSubs)).toList();

    final query = _q.trim().toLowerCase();
    final matchingSubs = query.isEmpty
        ? visiblePool
        : visiblePool
              .where(
                (s) =>
                    repo
                        .customerName(s.customerId)
                        .toLowerCase()
                        .contains(query) ||
                    s.planName.toLowerCase().contains(query) ||
                    s.planName.tr.toLowerCase().contains(query),
              )
              .toList();

    final statusById = <String, SubStatus>{
      for (final s in matchingSubs)
        s.id: Ledger.subStatus(s, reminderDays: reminder),
    };

    var activeCount = 0;
    var soonCount = 0;
    var expiredCount = 0;
    for (final s in matchingSubs) {
      switch (statusById[s.id]!) {
        case SubStatus.active:
          activeCount++;
        case SubStatus.expiringSoon:
          soonCount++;
        case SubStatus.expired:
          expiredCount++;
      }
    }

    int count(_SubFilter f) => switch (f) {
      _SubFilter.all => matchingSubs.length,
      _SubFilter.active => activeCount,
      _SubFilter.soon => soonCount,
      _SubFilter.expired => expiredCount,
    };

    double baseAmount(Subscription s) =>
        s.amount * repo.settings.currency(s.currency).rateToBase;

    final list = matchingSubs.where((s) {
      final st = statusById[s.id]!;
      return switch (_filter) {
        _SubFilter.all => true,
        _SubFilter.active => st == SubStatus.active,
        _SubFilter.soon => st == SubStatus.expiringSoon,
        _SubFilter.expired => st == SubStatus.expired,
      };
    }).toList();

    switch (_sort) {
      case _SubSort.nearestExpiry:
        list.sort((a, b) => a.endDate.compareTo(b.endDate));
      case _SubSort.newestSale:
        list.sort((a, b) => b.startDate.compareTo(a.startDate));
      case _SubSort.highestAmount:
        list.sort((a, b) => baseAmount(b).compareTo(baseAmount(a)));
    }

    final isFirstRun =
        _q.isEmpty && _filter == _SubFilter.all && allSubs.isEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: SearchField(
                      controller: _searchController,
                      hint: 'Search customers or plans...',
                      onChanged: _onSearchChanged,
                    ),
                  ),
                  const SizedBox(width: Insets.sm),
                  FilterToggleButton(
                    activeCount:
                        (_filter == _SubFilter.all ? 0 : 1) +
                        (_sort == _SubSort.nearestExpiry ? 0 : 1) +
                        (_showHistory ? 1 : 0),
                    expanded: _filtersOpen,
                    onPressed: () =>
                        setState(() => _filtersOpen = !_filtersOpen),
                  ),
                ],
              ),
              if (allSubs.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _SubSummaryPill(
                        label: 'Active'.tr,
                        count: activeCount,
                        color: const Color(0xFF16A34A),
                        selected: _filter == _SubFilter.active,
                        onTap: () => setState(() {
                          _filter = _filter == _SubFilter.active
                              ? _SubFilter.all
                              : _SubFilter.active;
                        }),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _SubSummaryPill(
                        label: 'Expiring soon'.tr,
                        count: soonCount,
                        color: const Color(0xFFF59E0B),
                        selected: _filter == _SubFilter.soon,
                        onTap: () => setState(() {
                          _filter = _filter == _SubFilter.soon
                              ? _SubFilter.all
                              : _SubFilter.soon;
                        }),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _SubSummaryPill(
                        label: 'Expired'.tr,
                        count: expiredCount,
                        color: const Color(0xFFE11D48),
                        selected: _filter == _SubFilter.expired,
                        onTap: () => setState(() {
                          _filter = _filter == _SubFilter.expired
                              ? _SubFilter.all
                              : _SubFilter.expired;
                        }),
                      ),
                    ),
                  ],
                ),
              ],
              if (_filter != _SubFilter.all) ...[
                const SizedBox(height: Insets.sm),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilterPill(
                    label: _filterLabel.tr,
                    icon: Icons.filter_alt_outlined,
                    onClear: () => setState(() => _filter = _SubFilter.all),
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
                            Wrap(
                              spacing: Insets.sm,
                              runSpacing: Insets.sm,
                              children: [
                                _chip(
                                  'All',
                                  _SubFilter.all,
                                  count(_SubFilter.all),
                                ),
                                _chip(
                                  'Active',
                                  _SubFilter.active,
                                  count(_SubFilter.active),
                                ),
                                _chip(
                                  'Expiring soon',
                                  _SubFilter.soon,
                                  count(_SubFilter.soon),
                                ),
                                _chip(
                                  'Expired',
                                  _SubFilter.expired,
                                  count(_SubFilter.expired),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  '${'Sort by'.tr}:',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: onSurface.withValues(alpha: 0.6),
                                  ),
                                ),
                                _sortPill(
                                  'Nearest expiry',
                                  _SubSort.nearestExpiry,
                                ),
                                _sortPill('Newest sale', _SubSort.newestSale),
                                _sortPill(
                                  'Highest amount',
                                  _SubSort.highestAmount,
                                ),
                                if (hasSuperseded)
                                  _historyPill('Show renewed history'),
                              ],
                            ),
                          ],
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? EmptyState(
                  icon: Icons.vpn_key_outlined,
                  title: isFirstRun
                      ? 'No subscriptions found'
                      : 'No items found',
                  text: isFirstRun
                      ? 'Record a sale to automatically create a customer subscription and expiry date.'
                      : 'Try a different search or filter.',
                  actionLabel: isFirstRun
                      ? 'Sell a subscription'
                      : 'Clear search and filters',
                  onAction: isFirstRun
                      ? () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const SellSubscriptionPage(),
                          ),
                        )
                      : _clearSearchAndFilters,
                )
              : RepaintBoundary(
                  child: RefreshIndicator(
                    onRefresh: () => repo.refreshAll(),
                    color: Theme.of(context).colorScheme.primary,
                    child: ListView.separated(
                      controller: widget.controller,
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 9),
                      itemBuilder: (context, i) {
                        final s = list[i];
                        final c = repo.customerById(s.customerId);
                        final balance = c == null
                            ? 0.0
                            : (balances[c.id] ?? 0.0);
                        final status =
                            statusById[s.id] ??
                            Ledger.subStatus(s, reminderDays: reminder);
                        final days = Ledger.daysLeft(s);
                        final progress = _progress(s);
                        return RepaintBoundary(
                          child: CardBox(
                            onTap: c == null
                                ? null
                                : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          CustomerDetailPage(customer: c),
                                    ),
                                  ),
                            onLongPress: () => _subscriptionActions(
                              context,
                              s,
                              c,
                              balance,
                              reminder,
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  c?.name ?? 'No customer'.tr,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              if (balance > 0.5) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                      0xFFE11D48,
                                                    ).withValues(alpha: 0.12),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          999,
                                                        ),
                                                  ),
                                                  child: Text(
                                                    'Debtor'.tr,
                                                    style: const TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: Color(0xFFE11D48),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            s.planName.tr,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
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
                                    ConstrainedBox(
                                      constraints: compact
                                          ? const BoxConstraints(maxWidth: 132)
                                          : const BoxConstraints(),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          CopyMoney(
                                            value: s.amount,
                                            child: MoneyText(
                                              s.amount,
                                              currency: s.currency,
                                              compact: compact,
                                              maxLines: 1,
                                              softWrap: false,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          TagChip(
                                            status == SubStatus.expired
                                                ? '${'Expired'.tr} ${Fmt.expiryLabel(days)}'
                                                : Fmt.expiryLabel(days),
                                            color: status.color,
                                            dense: true,
                                            maxWidth: compact ? 132 : null,
                                          ),
                                        ],
                                      ),
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
                                    valueColor: AlwaysStoppedAnimation(
                                      status.color,
                                    ),
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
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: onSurface.withValues(
                                            alpha: 0.6,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    TextButton.icon(
                                      onPressed: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => SellSubscriptionPage(
                                            renewFrom: s,
                                          ),
                                        ),
                                      ),
                                      icon: const Icon(
                                        Icons.autorenew_rounded,
                                        size: 16,
                                      ),
                                      label: Text(
                                        'Renew'.tr,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 28,
                                        minHeight: 28,
                                      ),
                                      icon: Icon(
                                        Icons.more_vert_rounded,
                                        size: 18,
                                        color: onSurface.withValues(
                                          alpha: 0.55,
                                        ),
                                      ),
                                      onPressed: () => _subscriptionActions(
                                        context,
                                        s,
                                        c,
                                        balance,
                                        reminder,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  double _progress(Subscription s) {
    final start = J.startOfDay(s.startDate);
    final end = J.startOfDay(s.endDate);
    final total = J.daysBetween(start, end);
    if (total <= 0) {
      return Ledger.daysLeft(s) < 0 ? 1.0 : 0.5;
    }
    final passed = J.daysBetween(start, J.today);
    return (passed / total).clamp(0.0, 1.0);
  }

  Widget _chip(String label, _SubFilter value, int n) => ChoiceChip(
    selected: _filter == value,
    showCheckmark: false,
    onSelected: (_) => setState(() => _filter = value),
    label: Text('${label.tr} ($n)'),
  );

  Widget _sortPill(String label, _SubSort value) {
    final selected = _sort == value;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => setState(() => _sort = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.14)
              : scheme.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: 0.35)
                : scheme.onSurface.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label.tr,
          style: TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? scheme.primary
                : scheme.onSurface.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }

  Widget _historyPill(String label) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => setState(() => _showHistory = !_showHistory),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _showHistory
              ? scheme.primary.withValues(alpha: 0.14)
              : scheme.onSurface.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: _showHistory
                ? scheme.primary.withValues(alpha: 0.35)
                : scheme.onSurface.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label.tr,
          style: TextStyle(
            fontSize: 11,
            fontWeight: _showHistory ? FontWeight.w700 : FontWeight.w500,
            color: _showHistory
                ? scheme.primary
                : scheme.onSurface.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }
}

class _SubSummaryPill extends StatelessWidget {
  const _SubSummaryPill({
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.14)
              : color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.45)
                : color.withValues(alpha: 0.18),
            width: selected ? 1.2 : 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: onSurface.withValues(alpha: 0.78),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$count',
              maxLines: 1,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
