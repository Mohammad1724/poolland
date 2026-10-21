import 'package:flutter/material.dart';
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
import 'motion_kit.dart';
import 'forms/contact_edit_page.dart';
import 'forms/payment_sheet.dart';
import 'widgets/widgets.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key, this.controller});

  /// Owned by the shell, so tapping the already-open tab can scroll this page
  /// back to the top. Tests and other callers can leave it null.
  final ScrollController? controller;

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

enum _Filter { all, debtors, creditors }

enum _CustomerSort { name, highestDebt, nearestExpiry }

class _CustomersPageState extends State<CustomersPage> {
  static final RegExp _nonDigitRe = RegExp(r'[^0-9]');
  static final RegExp _phoneQueryRe = RegExp(r'^[0-9\s()+./-]+$');

  final _searchDebouncer = Debouncer();
  final _searchController = TextEditingController();
  String _q = '';
  _Filter _filter = _Filter.all;
  _CustomerSort _sort = _CustomerSort.name;
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

  /// Long-press shortcut sheet for a customer row.
  Future<void> _customerActions(BuildContext context, Customer c) async {
    Haptics.tap();
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
              SheetHandle(),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(
                  Icons.call_received_rounded,
                  color: Color(0xFF0F766E),
                ),
                title: Text('Receive from customer'.tr),
                onTap: () => Navigator.pop(ctx, 'r'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.call_made_rounded,
                  color: Color(0xFFE11D48),
                ),
                title: Text('Pay customer'.tr),
                onTap: () => Navigator.pop(ctx, 'p'),
              ),
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: Text('Edit'.tr),
                onTap: () => Navigator.pop(ctx, 'e'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'r') {
      await showPaymentSheet(context, customer: c, isReceive: true);
    } else if (choice == 'p') {
      await showPaymentSheet(context, customer: c);
    } else if (choice == 'e' && context.mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ContactEditPage(existing: c)),
      );
    }
  }

  void _clearSearchAndFilters() {
    _searchDebouncer.cancel();
    _searchController.clear();
    setState(() {
      _q = '';
      _filter = _Filter.all;
      _sort = _CustomerSort.name;
    });
  }

  String get _filterLabel => switch (_filter) {
    _Filter.all => 'All',
    _Filter.debtors => 'Debtors',
    _Filter.creditors => 'Creditors',
  };

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final balances = repo.balancesMap();

    final query = Fmt.normalizeDigits(_q.trim().toLowerCase());
    final queryDigits = query.replaceAll(_nonDigitRe, '');
    final isPhoneQuery = _phoneQueryRe.hasMatch(query);
    final matchingCustomers = query.isEmpty
        ? repo.activeCustomers
        : repo.activeCustomers.where((c) {
            final matchesName = c.name.toLowerCase().contains(query);
            if (matchesName) return true;
            final normalizedPhone = Fmt.normalizeDigits(
              c.phone,
            ).replaceAll(_nonDigitRe, '');
            return Fmt.normalizeDigits(c.phone.toLowerCase()).contains(query) ||
                (isPhoneQuery &&
                    queryDigits.isNotEmpty &&
                    normalizedPhone.contains(queryDigits));
          }).toList();

    final debtorCustomers = matchingCustomers
        .where((c) => (balances[c.id] ?? 0) > 0.5)
        .toList();
    final creditorCustomers = matchingCustomers
        .where((c) => (balances[c.id] ?? 0) < -0.5)
        .toList();
    final totalDebt = debtorCustomers.fold<double>(
      0,
      (sum, c) => sum + (balances[c.id] ?? 0),
    );
    final totalCredit = creditorCustomers.fold<double>(
      0,
      (sum, c) => sum + (balances[c.id] ?? 0).abs(),
    );

    var list = List<Customer>.from(matchingCustomers);
    if (_filter == _Filter.debtors) {
      list = List<Customer>.from(debtorCustomers)
        ..sort((a, b) => (balances[b.id] ?? 0).compareTo(balances[a.id] ?? 0));
    } else if (_filter == _Filter.creditors) {
      list = List<Customer>.from(creditorCustomers)
        ..sort((a, b) => (balances[a.id] ?? 0).compareTo(balances[b.id] ?? 0));
    } else if (_sort == _CustomerSort.highestDebt) {
      list.sort((a, b) => (balances[b.id] ?? 0).compareTo(balances[a.id] ?? 0));
    } else if (_sort == _CustomerSort.nearestExpiry) {
      list.sort((a, b) {
        final subsA = repo.subsOfCustomer(a.id);
        final subsB = repo.subsOfCustomer(b.id);
        if (subsA.isEmpty && subsB.isEmpty) return a.name.compareTo(b.name);
        if (subsA.isEmpty) return 1;
        if (subsB.isEmpty) return -1;
        return subsA.first.endDate.compareTo(subsB.first.endDate);
      });
    }
    final isInitialEmpty = _q.isEmpty && _filter == _Filter.all;
    final noSavedCustomers = repo.customers.isEmpty;
    final emptyTitle = isInitialEmpty
        ? (noSavedCustomers ? 'No customers yet' : 'No active customers')
        : 'No items found';
    final emptyText = isInitialEmpty
        ? (noSavedCustomers
              ? 'Add each customer once to keep their sales, balances, and renewals together.'
              : 'All saved customers are archived.')
        : 'Try a different search or filter.';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: SearchField(
                      controller: _searchController,
                      hint: 'Search name or phone...',
                      onChanged: _onSearchChanged,
                    ),
                  ),
                  const SizedBox(width: Insets.sm),
                  FilterToggleButton(
                    activeCount:
                        (_filter == _Filter.all ? 0 : 1) +
                        (_sort == _CustomerSort.name ? 0 : 1),
                    expanded: _filtersOpen,
                    onPressed: () =>
                        setState(() => _filtersOpen = !_filtersOpen),
                  ),
                ],
              ),
              if (repo.activeCustomers.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _SummaryBalancePill(
                        label: 'Debtors'.tr,
                        count: debtorCustomers.length,
                        amount: totalDebt,
                        color: const Color(0xFFE11D48),
                        selected: _filter == _Filter.debtors,
                        onTap: () => setState(() {
                          _filter = _filter == _Filter.debtors
                              ? _Filter.all
                              : _Filter.debtors;
                        }),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SummaryBalancePill(
                        label: 'Creditors'.tr,
                        count: creditorCustomers.length,
                        amount: totalCredit,
                        color: const Color(0xFF2563EB),
                        selected: _filter == _Filter.creditors,
                        onTap: () => setState(() {
                          _filter = _filter == _Filter.creditors
                              ? _Filter.all
                              : _Filter.creditors;
                        }),
                      ),
                    ),
                  ],
                ),
              ],
              if (_filter != _Filter.all) ...[
                const SizedBox(height: Insets.sm),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: FilterPill(
                    label: _filterLabel.tr,
                    icon: Icons.filter_alt_outlined,
                    onClear: () => setState(() => _filter = _Filter.all),
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
                                  _Filter.all,
                                  matchingCustomers.length,
                                ),
                                _chip(
                                  'Debtors',
                                  _Filter.debtors,
                                  debtorCustomers.length,
                                ),
                                _chip(
                                  'Creditors',
                                  _Filter.creditors,
                                  creditorCustomers.length,
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
                                _sortPill('By name', _CustomerSort.name),
                                _sortPill(
                                  'Highest debt',
                                  _CustomerSort.highestDebt,
                                ),
                                _sortPill(
                                  'Nearest expiry',
                                  _CustomerSort.nearestExpiry,
                                ),
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
                  icon: Icons.people_outline_rounded,
                  title: emptyTitle,
                  text: emptyText,
                  actionLabel: isInitialEmpty
                      ? 'Add customer'
                      : 'Clear search and filters',
                  onAction: isInitialEmpty
                      ? () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ContactEditPage(),
                          ),
                        )
                      : _clearSearchAndFilters,
                )
              : RefreshIndicator(
                  onRefresh: () => repo.refreshAll(),
                  color: Theme.of(context).colorScheme.primary,
                  child: ListView.separated(
                  controller: widget.controller,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                  // ignore: deprecated_member_use
                  cacheExtent: 600,
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final c = list[i];
                    final balance = balances[c.id] ?? 0;
                    final subs = repo.subsOfCustomer(c.id);
                    final active = subs.where(
                      (s) =>
                          Ledger.subStatus(
                            s,
                            reminderDays: repo.settings.reminderDays,
                          ) !=
                          SubStatus.expired,
                    );
                    final latest = subs.isEmpty ? null : subs.first;
                    // Swiping a row is a shortcut, never a delete: the row
                    // snaps back and the payment sheet opens instead.
                    return RepaintBoundary(
                      child: Dismissible(
                        key: ValueKey('customer-swipe-${c.id}'),
                        direction: DismissDirection.horizontal,
                        // A shortcut, not a full dismiss: a short swipe is
                        // enough, because the row is not going anywhere.
                        dismissThresholds: const {
                          // The keys are the resolved directions, not
                          // [DismissDirection.horizontal].
                          DismissDirection.startToEnd: 0.25,
                          DismissDirection.endToStart: 0.25,
                        },
                        background: SwipeHint(
                          icon: Icons.south_west_rounded,
                          label: 'Receive',
                          color: const Color(0xFF16A34A),
                          alignment: AlignmentDirectional.centerStart,
                          borderRadius: BorderRadius.circular(Radii.card),
                        ),
                        secondaryBackground: SwipeHint(
                          icon: Icons.north_east_rounded,
                          label: 'Payment',
                          color: const Color(0xFFE11D48),
                          alignment: AlignmentDirectional.centerEnd,
                          borderRadius: BorderRadius.circular(Radii.card),
                        ),
                        confirmDismiss: (direction) {
                          Haptics.tap();
                          final isReceive =
                              direction == DismissDirection.startToEnd;
                          // Snap the row home first: awaiting the sheet here
                          // would leave the row slid off-screen behind the
                          // sheet's translucent barrier the whole time it is
                          // open.
                          afterSwipeSnapBack(
                            context,
                            () => showPaymentSheet(
                              context,
                              customer: c,
                              isReceive: isReceive,
                            ),
                          );
                          return Future.value(false);
                        },
                        child: CardBox(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CustomerDetailPage(customer: c),
                            ),
                          ),
                          // Long-press: the money shortcuts without opening the
                          // detail page first.
                          onLongPress: () => _customerActions(context, c),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: Theme.of(context)
                                    .colorScheme
                                    .primary
                                    .withValues(alpha: 0.13),
                                child: Text(
                                  c.initial,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            c.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: onSurface,
                                            ),
                                          ),
                                        ),
                                      if (active.isNotEmpty) ...[
                                        const SizedBox(width: Insets.sm),
                                        // A dot says the same thing as the old
                                        // chip without shouting. The label stays
                                        // for screen readers and long-press.
                                        const StatusDot(
                                          color: Color(0xFF16A34A),
                                          label: 'Active',
                                        ),
                                      ] else if (latest != null) ...[
                                        const SizedBox(width: Insets.sm),
                                        const StatusDot(
                                          color: Color(0xFFE11D48),
                                          label: 'Expired',
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    latest == null
                                        ? (c.phone.isEmpty
                                              ? 'No subscription'.tr
                                              : formatPhone(c.phone))
                                        : '{plan} • until {date}'.trArgs({
                                            'plan': latest.planName.tr,
                                            'date': J.d(latest.endDate),
                                          }),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: onSurface.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                balance.abs() < 1
                                    ? Text(
                                        'Settled'.tr,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w700,
                                          color: onSurface.withValues(
                                            alpha: 0.45,
                                          ),
                                        ),
                                      )
                                    : CopyMoney(
                                        value: balance,
                                        child: Text(
                                          Money.text(
                                            balance.abs(),
                                            withSymbol: false,
                                          ),
                                          style: TextStyle(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w700,
                                            color: balance > 0
                                                ? const Color(0xFFE11D48)
                                                : const Color(0xFF2563EB),
                                          ),
                                        ),
                                      ),
                                if (balance.abs() >= 1)
                                  Text(
                                    balance > 0 ? 'Debtor'.tr : 'Creditor'.tr,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: balance > 0
                                          ? const Color(0xFFE11D48)
                                          : const Color(0xFF2563EB),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
            );
                  },
                ),
                ),
        ),
      ],
    );
  }

  Widget _chip(String label, _Filter value, int? count) {
    final selected = _filter == value;
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      label: Text(count == null ? label.tr : '${label.tr} ($count)'),
      showCheckmark: false,
    );
  }

  Widget _sortPill(String label, _CustomerSort value) {
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
}

class _SummaryBalancePill extends StatelessWidget {
  const _SummaryBalancePill({
    required this.label,
    required this.count,
    required this.amount,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final double amount;
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.13)
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
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '$label ($count)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: onSurface.withValues(alpha: 0.78),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                Money.text(amount, withSymbol: false),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
