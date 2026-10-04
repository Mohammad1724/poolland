import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/backup.dart';
import '../core/format_utils.dart';
import '../core/jalali_utils.dart';
import '../core/money.dart';
import '../data/ledger.dart';
import '../data/models.dart';
import '../data/pdf_service.dart';
import '../data/repository.dart';
import 'forms/contact_edit_page.dart';
import 'forms/payment_sheet.dart';
import 'forms/sell_subscription_page.dart';
import 'forms/transaction_edit_page.dart';
import 'widgets/widgets.dart';

class CustomerDetailPage extends StatelessWidget {
  const CustomerDetailPage({super.key, required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final c = repo.customerById(customer.id) ?? customer;
    final balance = repo.balanceOf(c);
    final subs = repo.subsOfCustomer(c.id);
    final txns = repo.txnsOfCustomer(c.id);
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final monthStart = J.startOfMonth(J.addMonths(DateTime.now(), -11));
    final customerSummary = Ledger.summarize(repo.transactions,
        from: monthStart, customerId: c.id);
    final currencyTotals = Ledger.customerCurrencyTotals(c, repo.transactions);

    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
        actions: [
          IconButton(
            tooltip: 'ویرایش',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => ContactEditPage(existing: c))),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'statement':
                  final bytes = await PdfService.buildCustomerStatement(
                    repo: repo,
                    customer: c,
                    from: J.addMonths(DateTime.now(), -12),
                    to: DateTime.now(),
                  );
                  final ok = await Backup.shareBytes(
                    fileName: 'soorat-hesab-${c.name}.pdf',
                    bytes: bytes,
                    mimeType: 'application/pdf',
                  );
                  if (ok && context.mounted) showSnack(context, 'صورت‌حساب ساخته شد');
                  break;
                case 'delete':
                  final ok = await confirmDialog(context,
                      title: 'حذف مشتری',
                      message:
                          'مشتری «${c.name}» با ${txns.length} تراکنش و ${subs.length} اشتراک حذف شود؟ این کار قابل بازگشت نیست.',
                      okLabel: 'حذف',
                      danger: true);
                  if (!ok) return;
                  await repo.deleteCustomer(c.id);
                  if (context.mounted) Navigator.pop(context);
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'statement', child: Text('صورت‌حساب PDF')),
              PopupMenuItem(value: 'delete', child: Text('حذف مشتری')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          // ---------- مانده حساب ----------
          CardBox(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            balance.abs() < 1
                                ? 'تسویه شده'
                                : balance > 0
                                    ? 'به شما بدهکار است'
                                    : 'شما به او بدهکارید',
                            style: TextStyle(
                                fontSize: 12, color: onSurface.withValues(alpha: 0.65)),
                          ),
                          const SizedBox(height: 6),
                          MoneyText(balance.abs(),
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: balance.abs() < 1
                                      ? onSurface.withValues(alpha: 0.5)
                                      : balance > 0
                                          ? const Color(0xFF0F766E)
                                          : const Color(0xFF2563EB))),
                        ],
                      ),
                    ),
                    if (c.phone.isNotEmpty)
                      IconButton.filledTonal(
                        tooltip: 'تماس',
                        onPressed: () => launchUrl(Uri.parse('tel:${c.phone}')),
                        icon: const Icon(Icons.call_rounded, size: 20),
                      ),
                    const SizedBox(width: 6),
                    if (c.telegram.isNotEmpty || c.phone.isNotEmpty)
                      IconButton.filledTonal(
                        tooltip: 'پیام در تلگرام',
                        onPressed: () async {
                          final uname = c.telegram.replaceAll('@', '');
                          final uri = uname.isNotEmpty
                              ? Uri.parse('https://t.me/$uname')
                              : Uri.parse('https://wa.me/${c.phone}');
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                        },
                        icon: const Icon(Icons.send_rounded, size: 19),
                      ),
                  ],
                ),
                if (currencyTotals.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Divider(color: Theme.of(context).dividerColor),
                  const SizedBox(height: 8),
                  Text('به تفکیک ارز',
                      style: TextStyle(
                          fontSize: 11.5, color: onSurface.withValues(alpha: 0.6))),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: currencyTotals.entries
                        .map((e) => TagChip(
                              '${Money.text(e.value, currency: e.key)} ${e.value >= 0 ? 'بدهکار' : 'بستانکار'}',
                              color: e.value >= 0
                                  ? const Color(0xFF0F766E)
                                  : const Color(0xFF2563EB),
                              dense: true,
                            ))
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ---------- دکمه‌های عملیات ----------
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => showPaymentSheet(context, customer: c),
                  icon: const Icon(Icons.call_received_rounded, size: 18),
                  label: const Text('دریافت'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => SellSubscriptionPage(contact: c))),
                  icon: const Icon(Icons.vpn_key_rounded, size: 18),
                  label: const Text('فروش'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => TransactionEditPage(
                              initialKind: TxnKind.receive, customer: c))),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('تراکنش دستی'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(
                        text:
                            '${c.name}\nمانده: ${Money.text(balance.abs())} ${balance.abs() < 1 ? '' : balance > 0 ? '(بدهکار)' : '(بستانکار)'}\nسرویس‌ها: ${subs.length}'));
                    showSnack(context, 'اطلاعات کپی شد');
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('کپی خلاصه'),
                ),
              ),
            ],
          ),
          if (c.note.isNotEmpty) ...[
            const SizedBox(height: 12),
            CardBox(
              child: Row(
                children: [
                  Icon(Icons.notes_rounded,
                      size: 17, color: onSurface.withValues(alpha: 0.5)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(c.note, style: const TextStyle(fontSize: 12.5))),
                ],
              ),
            ),
          ],

          // ---------- خلاصه ۱۲ ماه ----------
          const SectionTitle('خلاصه ۱۲ ماه اخیر', icon: Icons.insights_rounded),
          CardBox(
            child: Column(
              children: [
                InfoRow('جمع خرید', MoneyText(customerSummary.income, withSymbol: true)),
                InfoRow('جمع دریافتی', MoneyText(customerSummary.received)),
                InfoRow('تعداد تراکنش', Text(Fmt.toFaDigits('${customerSummary.txnCount}'))),
              ],
            ),
          ),

          // ---------- اشتراک‌ها ----------
          SectionTitle('سرویس‌ها (${Fmt.toFaDigits('${subs.length}')})',
              icon: Icons.vpn_key_outlined),
          if (subs.isEmpty)
            const CardBox(
              child: Text('هنوز سرویسی ثبت نشده است.',
                  style: TextStyle(fontSize: 12.5)),
            )
          else
            ...subs.map((s) {
              final status =
                  Ledger.subStatus(s, reminderDays: repo.settings.reminderDays);
              final days = Ledger.daysLeft(s);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: CardBox(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(s.planName,
                                style: const TextStyle(
                                    fontSize: 13.5, fontWeight: FontWeight.w700)),
                          ),
                          TagChip(
                            status == SubStatus.expired
                                ? 'منقضی'
                                : Fmt.expiryLabel(days),
                            color: status.color,
                            dense: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.date_range_rounded,
                              size: 14, color: onSurface.withValues(alpha: 0.5)),
                          const SizedBox(width: 6),
                          Text('${J.d(s.startDate)} تا ${J.d(s.endDate)}',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: onSurface.withValues(alpha: 0.65))),
                          const Spacer(),
                          MoneyText(s.amount,
                              currency: s.currency,
                              style: const TextStyle(
                                  fontSize: 12.5, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          SellSubscriptionPage(renewFrom: s))),
                              icon: const Icon(Icons.autorenew_rounded, size: 16),
                              label: const Text('تمدید'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.outlined(
                            tooltip: 'حذف',
                            onPressed: () async {
                              final ok = await confirmDialog(context,
                                  title: 'حذف اشتراک',
                                  message:
                                      'این اشتراک حذف شود؟ (تراکنش‌های مالی باقی می‌مانند)',
                                  okLabel: 'حذف',
                                  danger: true);
                              if (!ok) return;
                              await repo.deleteSubscription(s.id);
                            },
                            icon: const Icon(Icons.delete_outline_rounded, size: 18),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),

          // ---------- تراکنش‌ها ----------
          SectionTitle('تراکنش‌ها (${Fmt.toFaDigits('${txns.length}')})',
              icon: Icons.receipt_long_outlined),
          if (txns.isEmpty)
            const CardBox(child: Text('تراکنشی ثبت نشده است.', style: TextStyle(fontSize: 12.5)))
          else
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < txns.length; i++) ...[
                    TxnTile(
                      txn: txns[i],
                      categoryName: repo.categoryName(txns[i].categoryId),
                      showCustomer: false,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => TransactionEditPage(existing: txns[i]))),
                    ),
                    if (i != txns.length - 1)
                      Divider(height: 1, color: Theme.of(context).dividerColor),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
