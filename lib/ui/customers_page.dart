import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format_utils.dart';
import '../core/jalali_utils.dart';
import '../core/localization.dart';
import '../core/money.dart';
import '../data/ledger.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'customer_detail_page.dart';
import 'forms/contact_edit_page.dart';
import 'widgets/widgets.dart';

class CustomersPage extends StatefulWidget {
  const CustomersPage({super.key});

  @override
  State<CustomersPage> createState() => _CustomersPageState();
}

enum _Filter { all, debtors, creditors }

class _CustomersPageState extends State<CustomersPage> {
  final _searchController = TextEditingController();
  String _q = '';
  _Filter _filter = _Filter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final balances = repo.balancesMap();

    final query = Fmt.normalizeSearchText(_q);
    final queryDigits = query.replaceAll(RegExp(r'[^0-9]'), '');
    final matchingCustomers = repo.activeCustomers.where((c) {
      if (query.isEmpty) return true;
      final matchesName = Fmt.normalizeSearchText(c.name).contains(query);
      final phoneKey = Fmt.normalizeSearchText(c.phone);
      final normalizedPhone = phoneKey.replaceAll(RegExp(r'[^0-9]'), '');
      final matchesPhone =
          phoneKey.contains(query) ||
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
    final hasActiveFilters = query.isNotEmpty || _filter != _Filter.all;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            children: [
              AppSearchField(
                controller: _searchController,
                hint: 'Search name or phone...',
                onChanged: (v) => setState(() => _q = v),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _chip('All', _Filter.all, matchingCustomers.length),
                    const SizedBox(width: 8),
                    _chip('Debtors', _Filter.debtors, null),
                    const SizedBox(width: 8),
                    _chip('Creditors', _Filter.creditors, null),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? EmptyState(
                  icon: Icons.people_outline_rounded,
                  title: hasActiveFilters
                      ? 'No customers match these filters'
                      : 'No customers yet',
                  text: hasActiveFilters
                      ? 'Try changing or clearing the search or balance filter.'
                      : 'Add each customer once to keep their sales, balances, and renewals together.',
                  actionLabel: hasActiveFilters
                      ? 'Clear search and balance filter'
                      : 'Add customer',
                  onAction: hasActiveFilters
                      ? () => setState(() {
                          _q = '';
                          _searchController.clear();
                          _filter = _Filter.all;
                        })
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ContactEditPage(),
                          ),
                        ),
                )
              : ListView.separated(
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
                    return CardBox(
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
                                      const SizedBox(width: 6),
                                      TagChip(
                                        'Active',
                                        color: const Color(0xFF16A34A),
                                        dense: true,
                                      ),
                                    ] else if (latest != null) ...[
                                      const SizedBox(width: 6),
                                      TagChip(
                                        'Expired',
                                        color: const Color(0xFFE11D48),
                                        dense: true,
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
