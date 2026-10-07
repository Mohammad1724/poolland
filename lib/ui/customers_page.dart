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

class _CustomersPageState extends State<CustomersPage> {
  final _searchDebouncer = Debouncer();
  String _q = '';
  _Filter _filter = _Filter.all;
  bool _filtersOpen = false;

  @override
  void dispose() {
    _searchDebouncer.dispose();
    super.dispose();
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

    final query = _q.trim().toLowerCase();
    final queryDigits = query.replaceAll(RegExp(r'[^0-9]'), '');
    final matchingCustomers = repo.activeCustomers.where((c) {
      if (query.isEmpty) return true;
      final matchesName = c.name.toLowerCase().contains(query);
      final normalizedPhone = c.phone.replaceAll(RegExp(r'[^0-9]'), '');
      final matchesPhone =
          c.phone.toLowerCase().contains(query) ||
          (queryDigits.isNotEmpty && normalizedPhone.contains(queryDigits));
      return matchesName || matchesPhone;
    }).toList();
    var list = matchingCustomers;
    if (_filter == _Filter.debtors) {
      list = list.where((c) => (balances[c.id] ?? 0) > 0.5).toList()
        ..sort((a, b) => (balances[b.id] ?? 0).compareTo(balances[a.id] ?? 0));
    } else if (_filter == _Filter.creditors) {
      list = list.where((c) => (balances[c.id] ?? 0) < -0.5).toList()
        ..sort((a, b) => (balances[a.id] ?? 0).compareTo(balances[b.id] ?? 0));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search name or phone...',
                        prefixIcon: Icon(Icons.search_rounded, size: 20),
                      ),
                      // Filtering waits for a short pause in typing; the field
                      // itself still echoes every keystroke, so nothing feels
                      // laggy.
                      onChanged: (v) => _searchDebouncer.run(
                        () => setState(() => _q = v.trim()),
                      ),
                    ),
                  ),
                  const SizedBox(width: Insets.sm),
                  FilterToggleButton(
                    activeCount: _filter == _Filter.all ? 0 : 1,
                    expanded: _filtersOpen,
                    onPressed: () =>
                        setState(() => _filtersOpen = !_filtersOpen),
                  ),
                ],
              ),
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
                duration: Motion.expand,
                curve: Curves.easeOut,
                alignment: Alignment.topCenter,
                child: _filtersOpen
                    ? Padding(
                        padding: const EdgeInsets.only(top: Insets.md),
                        child: Wrap(
                          spacing: Insets.sm,
                          runSpacing: Insets.sm,
                          children: [
                            _chip(
                              'All',
                              _Filter.all,
                              matchingCustomers.length,
                            ),
                            _chip('Debtors', _Filter.debtors, null),
                            _chip('Creditors', _Filter.creditors, null),
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
                  title: _q.isEmpty ? 'No customers yet' : 'No items found',
                  text: _q.isEmpty
                      ? 'Add each customer once to keep their sales, balances, and renewals together.'
                      : 'Try a different search.',
                  actionLabel: _q.isEmpty ? 'Add customer' : null,
                  onAction: _q.isEmpty
                      ? () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ContactEditPage(),
                          ),
                        )
                      : null,
                )
              : ListView.separated(
                  controller: widget.controller,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
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
                    return Dismissible(
                      key: ValueKey('customer-swipe-${c.id}'),
                      direction: DismissDirection.horizontal,
                      // A shortcut, not a full dismiss: a short swipe is
                      // enough, because the row is not going anywhere.
                      dismissThresholds: const {
                        DismissDirection.horizontal: 0.25,
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
                      confirmDismiss: (direction) async {
                        Haptics.tap();
                        final isReceive =
                            direction == DismissDirection.startToEnd;
                        await showPaymentSheet(
                          context,
                          customer: c,
                          isReceive: isReceive,
                        );
                        return false;
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
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .primary
                                  .withValues(alpha: 0.13),
                              child: Text(
                                c.name.characters.first,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Theme.of(context).colorScheme.primary,
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
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
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
                                Text(
                                  balance.abs() < 1
                                      ? 'Settled'.tr
                                      : Money.text(
                                          balance.abs(),
                                          withSymbol: false,
                                        ),
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                    color: balance.abs() < 1
                                        ? onSurface.withValues(alpha: 0.45)
                                        : balance > 0
                                        ? const Color(0xFF0F766E)
                                        : const Color(0xFF2563EB),
                                  ),
                                ),
                                if (balance.abs() >= 1)
                                  Text(
                                    balance > 0 ? 'Debtor'.tr : 'Creditor'.tr,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: onSurface.withValues(alpha: 0.55),
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
}
