import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format_utils.dart';
import '../core/jalali_utils.dart';
import '../core/money.dart';
import '../core/sms/sms_models.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'widgets/widgets.dart';

/// ============================================================
///  پیامک‌های بانکی — صف بررسی و تأیید
///
///  پیامک‌ها خوانده و تجزیه می‌شوند، اما تا وقتی کاربر تأیید نکند
///  هیچ تراکنشی در دفتر ثبت نمی‌شود.
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
        appBar: AppBar(title: const Text('پیامک‌های بانکی')),
        body: const EmptyState(
          icon: Icons.sms_outlined,
          title: 'فقط روی اندروید',
          text:
              'خواندن پیامک روی وب و دسکتاپ ممکن نیست. '
              'این قابلیت را روی گوشی اندرویدی خود امتحان کنید.',
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
        title: const Text('پیامک‌های بانکی'),
        actions: [
          IconButton(
            tooltip: 'همگام‌سازی',
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
                    title: 'رد کردن همه',
                    message:
                        'همه‌ی پیشنهادها رد شوند؟ '
                        '(دیگر نمایش داده نمی‌شوند اما تراکنشی حذف نمی‌شود)',
                    okLabel: 'رد کن',
                    danger: true,
                  );
                  if (ok) await repo.rejectAllSms();
                  break;
                case 'reset':
                  final ok = await confirmDialog(
                    context,
                    title: 'بررسی دوباره',
                    message:
                        'تاریخچه‌ی بررسی‌شده‌ها پاک شود و پیامک‌ها '
                        'دوباره بررسی شوند؟',
                    okLabel: 'پاک کن',
                  );
                  if (ok) {
                    await repo.resetSmsState();
                    await repo.syncSms(force: true);
                  }
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'reject_all', child: Text('رد کردن همه')),
              PopupMenuItem(
                value: 'reset',
                child: Text('بررسی دوباره پیامک‌ها'),
              ),
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
                      _chip('همه', _SmsFilter.all, all.length),
                      const SizedBox(width: 8),
                      _chip(
                        'واریز',
                        _SmsFilter.deposit,
                        all
                            .where((s) => s.direction == SmsDirection.deposit)
                            .length,
                      ),
                      const SizedBox(width: 8),
                      _chip(
                        'برداشت',
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
                            ? 'در حال بررسی پیامک‌ها…'
                            : 'موردی پیدا نشد',
                        text: repo.smsBusy
                            ? 'کمی صبر کنید'
                            : 'پیامک تراکنشی جدیدی پیدا نشد. دکمه‌ی '
                                  'همگام‌سازی را بزنید تا پیامک‌های اخیر بررسی شوند.',
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
    label: Text(count > 0 ? '$label ($count)' : label),
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
                    ? '$count تراکنش در انتظار تأیید'
                    : 'چیزی در انتظار نیست',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${Fmt.toFaDigits('$days')} روز گذشته بررسی می‌شود'
            '${last > 0 ? ' · آخرین بررسی: ${J.d(DateTime.fromMillisecondsSinceEpoch(last))}' : ''}',
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
              const Row(
                children: [
                  Icon(Icons.privacy_tip_outlined, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'دسترسی خواندن پیامک',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Text(
                'برای اینکه پول‌لند بتواند پیامک‌های بانکی را بخواند و '
                'واریز و برداشت‌ها را به‌صورت خودکار شناسایی کند، باید اجازه‌ی '
                'خواندن پیامک را بدهید.\n\n'
                '• پیامک‌ها فقط روی خودِ گوشی خوانده می‌شوند\n'
                '• هیچ داده‌ای به جایی ارسال نمی‌شود\n'
                '• تا وقتی خودتان تأیید نکنید، تراکنشی ثبت نمی‌شود',
                style: TextStyle(fontSize: 12.5, height: 1.8),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => repo.requestSmsPermission(),
                  icon: const Icon(Icons.sms_rounded, size: 18),
                  label: const Text('دادن دسترسی پیامک'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// ---------------- کارتِ هر پیامک ----------------
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
                      sms.bankName ?? 'بانک نامشخص',
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
                  'کارت ${sms.cardMask}',
                  color: const Color(0xFF7C3AED),
                  dense: true,
                ),
              if (sms.reference != null)
                TagChip(
                  'پیگیری ${sms.reference}',
                  color: const Color(0xFF0F766E),
                  dense: true,
                ),
              if (sms.balance != null)
                TagChip(
                  'مانده ${Money.text(sms.balance!, compact: true)}',
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
                  '(تطبیق خودکار)',
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
                  label: const Text('رد'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () => _openReview(context, sms, matched),
                  icon: const Icon(Icons.check_rounded, size: 17),
                  label: Text(matched == null ? 'بررسی و ثبت' : 'تأیید'),
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
      showSnack(context, 'تراکنش از پیامک ثبت شد');
    }
  }
}

/// ---------------- برگه‌ی بررسی / ویرایش قبل از ثبت ----------------
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
            const Text(
              'ثبت این پیامک در دفتر',
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

            // نوع تراکنش
            Wrap(
              spacing: 8,
              children: [
                for (final k in [
                  TxnKind.receive,
                  TxnKind.income,
                  TxnKind.expense,
                  TxnKind.refund,
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
              label: 'مبلغ',
              currency: sms.currency,
            ),
            const SizedBox(height: 14),

            SelectField<Customer>(
              label: 'طرف حساب (اختیاری)',
              icon: Icons.person_outline_rounded,
              value: _customer,
              items: repo.activeCustomers,
              clearable: true,
              labelOf: (c) => c.name,
              subOf: (c) => c.phone,
              searchHint: 'نام مشتری…',
              sheetTitle: 'انتخاب طرف حساب',
              onChanged: (c) => setState(() => _customer = c),
            ),

            if (isProfit) ...[
              const SizedBox(height: 14),
              SelectField<Category>(
                label: 'دسته‌بندی',
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
                    child: const Text('انصراف'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final value = parseAmount(_amount.text);
                      if (value <= 0) {
                        showSnack(context, 'مبلغ را وارد کنید', error: true);
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
                    label: const Text('ثبت در دفتر'),
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
