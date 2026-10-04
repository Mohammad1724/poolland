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

class SubscriptionsPage extends StatefulWidget {
  const SubscriptionsPage({super.key});

  @override
  State<SubscriptionsPage> createState() => _SubscriptionsPageState();
}

enum _SubFilter { all, active, soon, expired }

class _SubscriptionsPageState extends State<SubscriptionsPage> {
  _SubFilter _filter = _SubFilter.all;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final reminder = repo.settings.reminderDays;

    var list = [...repo.subscriptions];
    if (_q.isNotEmpty) {
      list = list
          .where((s) =>
              repo.customerName(s.customerId).contains(_q) || s.planName.contains(_q))
          .toList();
    }
    list = list.where((s) {
      final st = Ledger.subStatus(s, reminderDays: reminder);
      return switch (_filter) {
        _SubFilter.all => true,
        _SubFilter.active => st == SubStatus.active,
        _SubFilter.soon => st == SubStatus.expiringSoon,
        _SubFilter.expired => st == SubStatus.expired,
      };
    }).toList()
      ..sort((a, b) => a.endDate.compareTo(b.endDate));

    int count(_SubFilter f) {
      if (f == _SubFilter.all) return repo.subscriptions.length;
      return repo.subscriptions
          .where((s) => Ledger.subStatus(s, reminderDays: reminder) ==
              switch (f) {
                _SubFilter.active => SubStatus.active,
                _SubFilter.soon => SubStatus.expiringSoon,
                _SubFilter.expired => SubStatus.expired,
                _ => SubStatus.active,
              })
          .length;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
          child: Column(
            children: [
              TextField(
                decoration: const InputDecoration(
                  hintText: 'جست‌وجوی مشتری یا نام پلن…',
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                ),
                onChanged: (v) => setState(() => _q = v.trim()),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _chip('همه', _SubFilter.all, count(_SubFilter.all)),
                    const SizedBox(width: 8),
                    _chip('فعال', _SubFilter.active, count(_SubFilter.active)),
                    const SizedBox(width: 8),
                    _chip('نزدیک انقضا', _SubFilter.soon, count(_SubFilter.soon)),
                    const SizedBox(width: 8),
                    _chip('منقضی', _SubFilter.expired, count(_SubFilter.expired)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? EmptyState(
                  icon: Icons.vpn_key_outlined,
                  title: 'اشتراکی پیدا نشد',
                  text: 'با ثبت فروش، اشتراک مشتری و تاریخ انقضایش خودکار ثبت می‌شود.',
                  actionLabel: 'فروش اشتراک جدید',
                  onAction: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const SellSubscriptionPage())),
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
                          : () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => CustomerDetailPage(customer: c))),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(c?.name ?? 'بدون مشتری',
                                        style: const TextStyle(
                                            fontSize: 14, fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 3),
                                    Text(s.planName,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: onSurface.withValues(alpha: 0.65))),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  MoneyText(s.amount,
                                      currency: s.currency,
                                      style: const TextStyle(
                                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  TagChip(
                                    status == SubStatus.expired
                                        ? 'منقضی ${Fmt.expiryLabel(days)}'
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
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                              valueColor: AlwaysStoppedAnimation(status.color),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Icon(Icons.date_range_rounded,
                                  size: 14, color: onSurface.withValues(alpha: 0.5)),
                              const SizedBox(width: 5),
                              Text('${J.d(s.startDate)} تا ${J.d(s.endDate)}',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      color: onSurface.withValues(alpha: 0.6))),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            SellSubscriptionPage(renewFrom: s))),
                                icon: const Icon(Icons.autorenew_rounded, size: 16),
                                label: const Text('تمدید', style: TextStyle(fontSize: 12)),
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
        label: Text('$label (${Fmt.toFaDigits('$n')})'),
      );
}
