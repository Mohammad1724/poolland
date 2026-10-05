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

import '../core/localization.dart';

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
    final customerSummary = Ledger.summarize(
      repo.transactions,
      from: monthStart,
      customerId: c.id,
    );
    final currencyTotals = Ledger.customerCurrencyTotals(
      c,
      repo.businessTxns,
      baseCurrency: repo.settings.baseCurrency,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
        actions: [
          IconButton(
            tooltip: 'Edit'.tr,
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ContactEditPage(existing: c)),
            ),
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
                    fileName: 'statement-${c.name}.pdf',
                    bytes: bytes,
                    mimeType: 'application/pdf',
                  );
                  if (ok && context.mounted) {
                    showSnack(context, 'Statement created');
                  }
                  break;
                case 'delete':
                  final ok = await confirmDialog(
                    context,
                    title: 'Delete customer'.tr,
                    message: 'Delete customer "{name}" with {transactions} transactions and {subscriptions} subscriptions? This cannot be undone.'
                        .trArgs({
                          'name': c.name,
                          'transactions': txns.length,
                          'subscriptions': subs.length,
                        }),
                    okLabel: 'Delete'.tr,
                    danger: true,
                  );
                  if (!ok) return;
                  await repo.deleteCustomer(c.id);
                  if (context.mounted) Navigator.pop(context);
                  break;
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'statement',
                child: Text('PDF statement'.tr),
              ),
              PopupMenuItem(value: 'delete', child: Text('Delete customer'.tr)),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          // ---------- Account balance ----------
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
                                ? 'Settled'
                                : balance > 0
                                ? 'Owes you'
                                : 'You owe them',
                            style: TextStyle(
                              fontSize: 12,
                              color: onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                          const SizedBox(height: 6),
                          MoneyText(
                            balance.abs(),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: balance.abs() < 1
                                  ? onSurface.withValues(alpha: 0.5)
                                  : balance > 0
                                  ? const Color(0xFF0F766E)
                                  : const Color(0xFF2563EB),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (c.phone.isNotEmpty)
                      IconButton.filledTonal(
                        tooltip: 'Call'.tr,
                        onPressed: () => launchUrl(Uri.parse('tel:${c.phone}')),
                        icon: const Icon(Icons.call_rounded, size: 20),
                      ),
                    const SizedBox(width: 6),
                    if (c.telegram.isNotEmpty || c.phone.isNotEmpty)
                      IconButton.filledTonal(
                        tooltip: 'Message on Telegram'.tr,
                        onPressed: () async {
                          final uname = c.telegram.replaceAll('@', '');
                          final uri = uname.isNotEmpty
                              ? Uri.parse('https://t.me/$uname')
                              : Uri.parse('https://wa.me/${c.phone}');
                          await launchUrl(
                            uri,
                            mode: LaunchMode.externalApplication,
                          );
                        },
                        icon: const Icon(Icons.send_rounded, size: 19),
                      ),
                  ],
                ),
                if (currencyTotals.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Divider(color: Theme.of(context).dividerColor),
                  const SizedBox(height: 8),
                  Text(
                    'By currency'.tr,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: currencyTotals.entries
                        .map(
                          (e) => TagChip(
                            '{amount} {status}'.trArgs({
                              'amount': Money.text(e.value, currency: e.key),
                              'status': e.value >= 0
                                  ? 'Debtor'.tr
                                  : 'Creditor'.tr,
                            }),
                            color: e.value >= 0
                                ? const Color(0xFF0F766E)
                                : const Color(0xFF2563EB),
                            dense: true,
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ---------- Actions ----------
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => showPaymentSheet(context, customer: c),
                  icon: const Icon(Icons.call_received_rounded, size: 18),
                  label: Text('Receive'.tr),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SellSubscriptionPage(contact: c),
                    ),
                  ),
                  icon: const Icon(Icons.vpn_key_rounded, size: 18),
                  label: Text('Sale'.tr),
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
                        initialKind: TxnKind.receive,
                        customer: c,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text('Manual transaction'.tr),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(
                        text: '{name}\nBalance: {amount} {status}\nSubscriptions: {count}'
                            .trArgs({
                              'name': c.name,
                              'amount': Money.text(balance.abs()),
                              'status': balance.abs() < 1
                                  ? 'Settled'.tr
                                  : balance > 0
                                  ? 'Debtor'.tr
                                  : 'Creditor'.tr,
                              'count': subs.length,
                            }),
                      ),
                    );
                    showSnack(context, 'Details copied');
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: Text('Copy summary'.tr),
                ),
              ),
            ],
          ),
          if (c.note.isNotEmpty) ...[
            const SizedBox(height: 12),
            CardBox(
              child: Row(
                children: [
                  Icon(
                    Icons.notes_rounded,
                    size: 17,
                    color: onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(c.note, style: const TextStyle(fontSize: 12.5)),
                  ),
                ],
              ),
            ),
          ],

          // ---------- 12-month summary ----------
          const SectionTitle('12-month summary', icon: Icons.insights_rounded),
          CardBox(
            child: Column(
              children: [
                InfoRow(
                  'Total purchases',
                  MoneyText(customerSummary.sales, withSymbol: true),
                ),
                InfoRow('Total received', MoneyText(customerSummary.received)),
                InfoRow('Transactions', Text('${customerSummary.txnCount}')),
              ],
            ),
          ),

          // ---------- Subscriptions ----------
          SectionTitle(
            'Subscriptions ({count})'.trArgs({'count': subs.length}),
            icon: Icons.vpn_key_outlined,
          ),
          if (subs.isEmpty)
            CardBox(
              child: Text(
                'No subscriptions recorded yet.'.tr,
                style: TextStyle(fontSize: 12.5),
              ),
            )
          else
            ...subs.map((s) {
              final status = Ledger.subStatus(
                s,
                reminderDays: repo.settings.reminderDays,
              );
              final days = Ledger.daysLeft(s);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: CardBox(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.planName,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          TagChip(
                            status == SubStatus.expired
                                ? 'Expired'
                                : Fmt.expiryLabel(days),
                            color: status.color,
                            dense: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.date_range_rounded,
                            size: 14,
                            color: onSurface.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '{from} to {to}'.trArgs({
                              'from': J.d(s.startDate),
                              'to': J.d(s.endDate),
                            }),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                          const Spacer(),
                          MoneyText(
                            s.amount,
                            currency: s.currency,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
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
                                  builder: (_) =>
                                      SellSubscriptionPage(renewFrom: s),
                                ),
                              ),
                              icon: const Icon(
                                Icons.autorenew_rounded,
                                size: 16,
                              ),
                              label: Text('Renew'.tr),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.outlined(
                            tooltip: 'Delete'.tr,
                            onPressed: () async {
                              final ok = await confirmDialog(
                                context,
                                title: 'Delete subscription'.tr,
                                message: 'Delete this subscription? (Financial transactions will remain.)'
                                    .tr,
                                okLabel: 'Delete'.tr,
                                danger: true,
                              );
                              if (!ok) return;
                              await repo.deleteSubscription(s.id);
                            },
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),

          // ---------- Transactions ----------
          SectionTitle(
            'Transactions ({count})'.trArgs({'count': txns.length}),
            icon: Icons.receipt_long_outlined,
          ),
          if (txns.isEmpty)
            CardBox(
              child: Text(
                'No transactions recorded.'.tr,
                style: TextStyle(fontSize: 12.5),
              ),
            )
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
                          builder: (_) =>
                              TransactionEditPage(existing: txns[i]),
                        ),
                      ),
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
