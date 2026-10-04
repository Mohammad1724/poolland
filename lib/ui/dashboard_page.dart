import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format_utils.dart';
import '../core/jalali_utils.dart';
import '../data/ledger.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'customer_detail_page.dart';
import 'forms/sell_subscription_page.dart';
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
    final recent = repo.visibleTxns.take(5).toList();
    final onSurface = Theme.of(context).colorScheme.onSurface;

    // مشتری، اشتراک و انقضا فقط مربوط به دفتر کسب‌وکار است
    final showBusiness = !repo.isBookFiltered || repo.bookFilter == BookIds.business;
    final activeBook = repo.isBookFiltered ? repo.bookById(repo.bookFilter) : null;

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
            if (showBusiness)
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
              Row(
                children: [
                  Expanded(
                    child: Text('خلاصه‌ی این ماه',
                        style: TextStyle(
                            fontSize: 12.5, color: onSurface.withValues(alpha: 0.65))),
                  ),
                  if (activeBook != null)
                    TagChip(activeBook.name,
                        color: Color(activeBook.color), icon: Icons.menu_book_rounded, dense: true),
                ],
              ),
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

        // مقایسه‌ی دفترها — فقط وقتی روی «همه» هستیم
        if (!repo.isBookFiltered && repo.settings.books.length > 1) ...[
          _BooksComparison(repo: repo, from: monthStart, to: monthEnd),
          const SizedBox(height: 12),
        ],

        // طلب و بدهی (فقط دفتر کسب‌وکار)
        if (showBusiness) ...[
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
        ],

        // هشدار انقضا
        if (showBusiness && alerts.isNotEmpty) ...[
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
        SectionTitle('روند ۶ ماه گذشته${activeBook == null ? '' : ' — ${activeBook.name}'}',
            icon: Icons.bar_chart_rounded),
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
          EmptyState(
            icon: Icons.receipt_long_outlined,
            title: repo.isBookFiltered
                ? 'در دفتر «${repo.bookName(repo.bookFilter)}» تراکنشی نیست'
                : 'هنوز تراکنشی ثبت نشده',
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
                    showBook: !repo.isBookFiltered,
                    bookName: repo.bookName(recent[i].bookId),
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

/// مقایسه‌ی درآمد/هزینه/سود هر دفتر در یک بازه — پاسخ به «واقعاً چقدر درآمد داشتم؟»
class _BooksComparison extends StatelessWidget {
  const _BooksComparison({required this.repo, required this.from, required this.to});

  final AppRepository repo;
  final DateTime from;
  final DateTime to;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final rows = repo.summaryByBook(from: from, to: to);
    final grand = rows.fold<double>(0, (a, e) => a + e.value.profit);

    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.compare_arrows_rounded, size: 16, color: onSurface.withValues(alpha: 0.6)),
              const SizedBox(width: 6),
              Text('مقایسه‌ی دفترها — این ماه',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: onSurface.withValues(alpha: 0.85))),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Divider(height: 1, color: Theme.of(context).dividerColor),
            ),
            _BookRow(entry: rows[i], total: grand, onTap: () => repo.setBookFilter(rows[i].key.id)),
          ],
          const SizedBox(height: 10),
          Divider(color: Theme.of(context).dividerColor),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('سود کل (${Fmt.toFaDigits('${rows.length}')} دفتر)',
                  style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.7))),
              const Spacer(),
              MoneyText(grand,
                  compact: true,
                  style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: grand >= 0 ? const Color(0xFF16A34A) : const Color(0xFFE11D48))),
            ],
          ),
        ],
      ),
    );
  }
}

class _BookRow extends StatelessWidget {
  const _BookRow({required this.entry, required this.total, required this.onTap});

  final MapEntry<Book, Summary> entry;
  final double total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final color = Color(entry.key.color);
    final s = entry.value;
    final share = total.abs() < 1 ? 0.0 : (s.profit / total);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 34,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.key.name,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    'درآمد ${Money.text(s.income, compact: true)} • هزینه ${Money.text(s.expense, compact: true)}',
                    style: TextStyle(fontSize: 10.5, color: onSurface.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                MoneyText(s.profit,
                    compact: true,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: s.profit >= 0 ? const Color(0xFF16A34A) : const Color(0xFFE11D48))),
                const SizedBox(height: 2),
                Text(Fmt.percent(share),
                    style: TextStyle(fontSize: 10.5, color: onSurface.withValues(alpha: 0.55))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
