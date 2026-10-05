import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format_utils.dart';
import '../core/jalali_utils.dart';
import '../core/money.dart';
import '../core/sms/sms_models.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'widgets/widgets.dart';

import '../core/localization.dart';

/// ============================================================
///  Bank SMS — review and approval queue
///
///  Messages are read and parsed, but until the user approves them,
///  no transaction is recorded in the ledger.
/// ============================================================
class SmsPage extends StatefulWidget {
  const SmsPage({super.key});

  @override
  State<SmsPage> createState() => _SmsPageState();
}

enum _SmsFilter { all, deposit, withdraw }

class _SmsPageState extends State<SmsPage> {
  _SmsFilter _filter = _SmsFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final repo = context.read<AppRepository>();
      repo.initSms();
      await repo.refreshSmsPermission();
      if (repo.smsPermissionGranted && repo.smsSuggestions.isEmpty) {
        await repo.syncSms();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final onSurface = Theme.of(context).colorScheme.onSurface;

    if (!repo.smsSupported) {
      return Scaffold(
        appBar: AppBar(title: Text('Bank SMS'.tr)),
        body: const EmptyState(
          icon: Icons.sms_outlined,
          title: 'Android only',
          text: 'SMS access is not available on web or desktop. Try this feature on an Android phone.',
        ),
      );
    }

    final all = repo.smsSuggestions;
    final list = switch (_filter) {
      _SmsFilter.all => all,
      _SmsFilter.deposit =>
        all.where((s) => s.direction == SmsDirection.deposit).toList(),
      _SmsFilter.withdraw =>
        all.where((s) => s.direction == SmsDirection.withdraw).toList(),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text('Bank SMS'.tr),
        actions: [
          IconButton(
            tooltip: 'Sync'.tr,
            icon: repo.smsBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
            onPressed: repo.smsBusy ? null : () => repo.syncSms(force: true),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              switch (v) {
                case 'reject_all':
                  final ok = await confirmDialog(
                    context,
                    title: 'Reject all'.tr,
                    message: 'Reject all suggestions? (They will no longer appear, but no transactions will be deleted.)'
                        .tr,
                    okLabel: 'Reject'.tr,
                    danger: true,
                  );
                  if (ok) await repo.rejectAllSms();
                  break;
                case 'reset':
                  final ok = await confirmDialog(
                    context,
                    title: 'Review again'.tr,
                    message:
                        'Clear the review history and scan SMS messages '
                        'again?',
                    okLabel: 'Clear',
                  );
                  if (ok) {
                    await repo.resetSmsState();
                    await repo.syncSms(force: true);
                  }
                  break;
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'reject_all', child: Text('Reject all'.tr)),
              PopupMenuItem(value: 'reset', child: Text('Rescan SMS'.tr)),
            ],
          ),
        ],
      ),
      body: !repo.smsPermissionGranted
          ? _permissionView(context, repo)
          : RefreshIndicator(
              onRefresh: () => repo.syncSms(force: true),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                children: [
                  _summaryCard(context, repo, all.length),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _chip('All', _SmsFilter.all, all.length),
                      const SizedBox(width: 8),
                      _chip(
                        'Deposit',
                        _SmsFilter.deposit,
                        all
                            .where((s) => s.direction == SmsDirection.deposit)
                            .length,
                      ),
                      const SizedBox(width: 8),
                      _chip(
                        'Withdrawal',
                        _SmsFilter.withdraw,
                        all
                            .where((s) => s.direction == SmsDirection.withdraw)
                            .length,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (list.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: EmptyState(
                        icon: Icons.sms_outlined,
                        title: repo.smsBusy
                            ? 'Checking SMS...'
                            : 'No items found',
                        text: repo.smsBusy
                            ? 'Please wait'
                            : 'No new transaction messages found. Tap '
                                  'Sync to check recent messages.',
                      ),
                    )
                  else
                    for (final sms in list)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _SmsCard(sms: sms, onSurface: onSurface),
                      ),
                ],
              ),
            ),
    );
  }

  Widget _chip(String label, _SmsFilter f, int count) => ChoiceChip(
    label: Text(count > 0 ? '${label.tr} ($count)' : label.tr),
    showCheckmark: false,
    selected: _filter == f,
    onSelected: (_) => setState(() => _filter = f),
  );

  Widget _summaryCard(BuildContext context, AppRepository repo, int count) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final days = repo.settings.smsSyncDays;
    final last = repo.settings.smsLastSyncAt;
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sms_rounded, size: 18),
              const SizedBox(width: 8),
              Text(
                count > 0
                    ? '{count} transactions awaiting review'.trArgs({
                        'count': count,
                      })
                    : 'Nothing awaiting review'.tr,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Checking the past {days} days'.trArgs({'days': days}) +
                (last > 0
                    ? ' · {label}'.trArgs({
                        'label': 'Last checked: {date}'.trArgs({
                          'date': J.d(
                            DateTime.fromMillisecondsSinceEpoch(last),
                          ),
                        }),
                      })
                    : ''),
            style: TextStyle(
              fontSize: 11.5,
              color: onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _permissionView(BuildContext context, AppRepository repo) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
      children: [
        CardBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.privacy_tip_outlined, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'SMS reading permission'.tr,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'To let Poolland read bank SMS and automatically identify deposits and withdrawals, grant SMS permission.\n\n'
                        '• SMS messages are read on this device only\n'
                        '• No data is sent anywhere\n'
                        '• No transaction is recorded until you approve it'
                    .tr,
                style: const TextStyle(fontSize: 12.5, height: 1.8),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => repo.requestSmsPermission(),
                  icon: const Icon(Icons.sms_rounded, size: 18),
                  label: Text('Grant SMS access'.tr),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// ---------------- SMS card ----------------
class _SmsCard extends StatelessWidget {
  const _SmsCard({required this.sms, required this.onSurface});

  final ParsedSms sms;
  final Color onSurface;

  Color get _color => switch (sms.direction) {
    SmsDirection.deposit => const Color(0xFF16A34A),
    SmsDirection.withdraw => const Color(0xFFE11D48),
    SmsDirection.unknown => const Color(0xFFF59E0B),
  };

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final matched = repo.matchCustomerForSms(sms);

    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  sms.direction == SmsDirection.deposit
                      ? Icons.call_received_rounded
                      : Icons.call_made_rounded,
                  size: 18,
                  color: _color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sms.bankName ?? 'Unknown bank'.tr,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${J.d(sms.message.date)} · ${Fmt.clock(sms.message.date)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${sms.direction == SmsDirection.deposit ? '+' : '−'}'
                    '${Money.text(sms.amount, currency: sms.currency)}',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: _color,
                    ),
                  ),
                  const SizedBox(height: 3),
                  TagChip(sms.direction.label, color: _color, dense: true),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (sms.cardMask != null)
                TagChip(
                  'Card {card}'.trArgs({'card': sms.cardMask}),
                  color: const Color(0xFF7C3AED),
                  dense: true,
                ),
              if (sms.reference != null)
                TagChip(
                  'Reference {reference}'.trArgs({'reference': sms.reference}),
                  color: const Color(0xFF0F766E),
                  dense: true,
                ),
              if (sms.balance != null)
                TagChip(
                  'Balance {balance}'.trArgs({
                    'balance': Money.text(sms.balance!, compact: true),
                  }),
                  color: const Color(0xFF2563EB),
                  dense: true,
                ),
            ],
          ),
          if (matched != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.person_outline_rounded, size: 15),
                const SizedBox(width: 5),
                Text(
                  matched.name,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '(Auto-matched)'.tr,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            sms.message.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.6,
              color: onSurface.withValues(alpha: 0.6),
            ),
          ),
          if (sms.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              sms.note,
              style: const TextStyle(fontSize: 10.5, color: Color(0xFFB45309)),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => repo.rejectSms(sms),
                  icon: const Icon(Icons.close_rounded, size: 17),
                  label: Text('Reject'.tr),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () => _openReview(context, sms, matched),
                  icon: const Icon(Icons.check_rounded, size: 17),
                  label: Text(
                    matched == null ? 'Review and record' : 'Confirm',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openReview(
    BuildContext context,
    ParsedSms sms,
    Customer? matched,
  ) async {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SmsReviewSheet(sms: sms, initialCustomer: matched),
    );
    if (ok == true && context.mounted) {
      showSnack(context, 'Transaction recorded from SMS');
    }
  }
}

/// ---------------- Review or edit before recording ----------------
class SmsReviewSheet extends StatefulWidget {
  const SmsReviewSheet({super.key, required this.sms, this.initialCustomer});

  final ParsedSms sms;
  final Customer? initialCustomer;

  @override
  State<SmsReviewSheet> createState() => _SmsReviewSheetState();
}

class _SmsReviewSheetState extends State<SmsReviewSheet> {
  late TextEditingController _amount;
  Customer? _customer;
  TxnKind _kind = TxnKind.receive;
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    final repo = context.read<AppRepository>();
    _customer = widget.initialCustomer;
    _kind = widget.sms.direction == SmsDirection.deposit
        ? (_customer != null ? TxnKind.receive : TxnKind.income)
        : TxnKind.expense;
    _amount = TextEditingController(
      text: groupedNumber(
        widget.sms.amount,
        decimals: Money.decimals(widget.sms.currency),
      ),
    );
    _categoryId = _kind == TxnKind.expense
        ? repo.defaultExpenseCategoryId
        : repo.defaultIncomeCategoryId;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final sms = widget.sms;
    final isProfit = _kind == TxnKind.income || _kind == TxnKind.expense;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        14,
        16,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Record this SMS transaction'.tr,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              sms.bankName ?? sms.message.address,
              style: TextStyle(
                fontSize: 11.5,
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),

            // Transaction type
            Wrap(
              spacing: 8,
              children: [
                for (final k in [
                  TxnKind.receive,
                  TxnKind.income,
                  TxnKind.expense,
                  TxnKind.refund,
                  TxnKind.payablePayment,
                ])
                  ChoiceChip(
                    selected: _kind == k,
                    avatar: Icon(k.icon, size: 16),
                    label: Text(k.shortLabel),
                    onSelected: (_) => setState(() {
                      _kind = k;
                      _categoryId = k == TxnKind.expense
                          ? repo.defaultExpenseCategoryId
                          : repo.defaultIncomeCategoryId;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 14),

            AmountField(
              controller: _amount,
              label: 'Amount'.tr,
              currency: sms.currency,
            ),
            const SizedBox(height: 14),

            SelectField<Customer>(
              label: 'Contact (optional)'.tr,
              icon: Icons.person_outline_rounded,
              value: _customer,
              items: repo.activeCustomers,
              clearable: true,
              labelOf: (c) => c.name,
              subOf: (c) => c.phone,
              searchHint: 'Customer name...'.tr,
              sheetTitle: 'Select contact'.tr,
              onChanged: (c) => setState(() => _customer = c),
            ),

            if (isProfit) ...[
              const SizedBox(height: 14),
              SelectField<Category>(
                label: 'Category'.tr,
                icon: Icons.category_outlined,
                value: repo.categoryById(_categoryId),
                items: repo.categoriesOf(_kind),
                labelOf: (c) => c.name,
                onChanged: (c) => setState(() => _categoryId = c?.id),
              ),
            ],

            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel'.tr),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final value = parseAmount(_amount.text);
                      if (value <= 0) {
                        showSnack(context, 'Enter an amount', error: true);
                        return;
                      }
                      await repo.approveSms(
                        sms,
                        customer: _customer,
                        kind: _kind,
                        categoryId: _categoryId,
                        amount: value,
                      );
                      if (context.mounted) Navigator.pop(context, true);
                    },
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text('Record transaction'.tr),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
