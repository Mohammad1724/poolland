import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format_utils.dart';
import '../core/jalali_utils.dart';
import '../data/ledger.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'customer_detail_page.dart';
import 'forms/sell_subscription_page.dart';
import 'sms_page.dart';
import 'widgets/common_charts.dart';
import 'widgets/widgets.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key, required this.onNavigate});

  final void Function(int index) onNavigate;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final monthStart = J.startOfMonth(DateTime.now());
    final monthEnd = J.endOfMonth(DateTime.now());
    final monthSummary = repo.summary(from: monthStart, to: monthEnd);
    final totals = repo.totals;
    final alerts = repo.alerts;
    final series = repo.series(months: 6);
    final recent = repo.transactions.take(5).toList();
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
      children: [
        // پیام خوش‌آمد
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('سلام 👋',
                      style: TextStyle(fontSize: 13, color: onSurface.withValues(alpha: 0.6))),
                  const SizedBox(height: 2),
                  Text(J.mLabel(DateTime.now()),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            TagChip('${repo.activeSubsCount} اشتراک فعال',
                color: const Color(0xFF16A34A), icon: Icons.check_circle_rounded),
          ],
        ),
        const SizedBox(height: 14),

        // خلاصه‌ی ماه
        CardBox(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('خلاصه‌ی این ماه',
                  style: TextStyle(fontSize: 12.5, color: onSurface.withValues(alpha: 0.65))),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _miniStat(context, 'درآمد', monthSummary.income,
                        const Color(0xFF16A34A), Icons.trending_up_rounded),
                  ),
                  Container(width: 1, height: 42, color: Theme.of(context).dividerColor),
                  Expanded(
                    child: _miniStat(context, 'هزینه', monthSummary.expense,
                        const Color(0xFFE11D48), Icons.trending_down_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Divider(color: Theme.of(context).dividerColor),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.savings_rounded,
                      size: 18,
                      color: monthSummary.profit >= 0
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFE11D48)),
                  const SizedBox(width: 8),
                  Text('سود این ماه',
                      style: TextStyle(fontSize: 12.5, color: onSurface.withValues(alpha: 0.7))),
                  const Spacer(),
                  MoneyText(monthSummary.profit,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: monthSummary.profit >= 0
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFE11D48))),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // طلب و بدهی
        Row(
          children: [
            Expanded(
              child: CardBox(
                onTap: () => onNavigate(1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('طلب شما از مشتری‌ها',
                        style: TextStyle(fontSize: 11.5, color: onSurface.withValues(alpha: 0.65))),
                    const SizedBox(height: 6),
                    MoneyText(totals.receivable,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0F766E))),
                    const SizedBox(height: 3),
                    Text('${Fmt.toFaDigits('${totals.debtorsCount}')} مشتری بدهکار',
                        style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: 0.55))),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: CardBox(
                onTap: () => onNavigate(1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('بدهی شما',
                        style: TextStyle(fontSize: 11.5, color: onSurface.withValues(alpha: 0.65))),
                    const SizedBox(height: 6),
                    MoneyText(totals.payable,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2563EB))),
                    const SizedBox(height: 3),
                    Text('${Fmt.toFaDigits('${totals.creditorsCount}')} طرف حساب',
                        style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: 0.55))),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: CardBox(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('موجودی صندوق',
                        style: TextStyle(fontSize: 11.5, color: onSurface.withValues(alpha: 0.65))),
                    const SizedBox(height: 6),
                    MoneyText(repo.cashBalance,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF7C3AED))),
                    const SizedBox(height: 3),
                    Text('نقد + بانک',
                        style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: 0.55))),
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
                    Text('دریافتی این ماه',
                        style: TextStyle(fontSize: 11.5, color: onSurface.withValues(alpha: 0.65))),
                    const SizedBox(height: 6),
                    MoneyText(monthSummary.cashIn,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text('نقد + وصولی',
                        style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: 0.55))),
                  ],
                ),
              ),
            ),
          ],
        ),

        // پیامک‌های بانکی (فقط اندروید)
        if (repo.smsSupported) ...[
          CardBox(
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SmsPage())),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: (repo.smsPendingCount > 0
                            ? const Color(0xFF16A34A)
                            : const Color(0xFF7C3AED))
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(Icons.sms_rounded,
                      size: 19,
                      color: repo.smsPendingCount > 0
                          ? const Color(0xFF16A34A)
                          : const Color(0xFF7C3AED)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('پیامک‌های بانکی',
                          style: TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(
                        !repo.smsPermissionGranted
                            ? 'برای شناسایی خودکار واریزها دسترسی بدهید'
                            : repo.smsPendingCount > 0
                                ? '${Fmt.toFaDigits('${repo.smsPendingCount}')} '
                                    'تراکنش در انتظار تأیید'
                                : 'مورد جدیدی پیدا نشد',
                        style: TextStyle(
                            fontSize: 11.5,
                            color: onSurface.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
                if (repo.smsPendingCount > 0)
                  TagChip(
                      Fmt.toFaDigits('${repo.smsPendingCount}'),
                      color: const Color(0xFF16A34A),
                      dense: true)
                else
                  const Icon(Icons.chevron_left_rounded, size: 18),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],

        // هشدار انقضا
        if (alerts.isNotEmpty) ...[
          SectionTitle('سرویس‌های نزدیک انقضا و منقضی‌شده',
              icon: Icons.notification_important_outlined, action: 'همه', onAction: () => onNavigate(2)),
          ...alerts.take(4).map((s) {
            final customer = repo.customerById(s.customerId);
            final status = Ledger.subStatus(s, reminderDays: repo.settings.reminderDays);
            final days = Ledger.daysLeft(s);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CardBox(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                onTap: customer == null
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => CustomerDetailPage(customer: customer))),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(customer?.name ?? 'بدون مشتری',
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 3),
                          Text('${s.planName} • ${J.d(s.endDate)}',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: onSurface.withValues(alpha: 0.6))),
                        ],
                      ),
                    ),
                    TagChip(Fmt.expiryLabel(days), color: status.color, dense: true),
                    const SizedBox(width: 6),
                    IconButton(
                      tooltip: 'تمدید',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => SellSubscriptionPage(renewFrom: s))),
                      icon: const Icon(Icons.autorenew_rounded, size: 19),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],

        // نمودار
        const SectionTitle('روند ۶ ماه گذشته', icon: Icons.bar_chart_rounded),
        CardBox(
          padding: const EdgeInsets.fromLTRB(10, 16, 10, 8),
          child: SizedBox(
            height: 190,
            child: MonthlyBarChart(points: series),
          ),
        ),

        // آخرین تراکنش‌ها
        SectionTitle('آخرین تراکنش‌ها',
            icon: Icons.receipt_long_outlined, action: 'همه', onAction: () => onNavigate(3)),
        if (recent.isEmpty)
          const EmptyState(
            icon: Icons.receipt_long_outlined,
            title: 'هنوز تراکنشی ثبت نشده',
            text: 'با دکمه‌ی + اولین فروش یا هزینه را ثبت کنید.',
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

  Widget _miniStat(BuildContext context, String label, double value, Color color, IconData icon) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 11.5, color: onSurface.withValues(alpha: 0.65))),
          ],
        ),
        const SizedBox(height: 6),
        MoneyText(value,
            compact: false,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }
}
