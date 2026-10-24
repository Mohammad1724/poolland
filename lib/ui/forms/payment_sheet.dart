import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format_utils.dart';
import '../../core/haptics.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../theme.dart';
import '../widgets/widgets.dart';
import '../motion_kit.dart';
import 'sms_review_sheet.dart';

import '../../core/localization.dart';

/// Quick sheet for recording a receipt from or payment to a customer
Future<bool> showPaymentSheet(
  BuildContext context, {
  required Customer customer,
  bool isReceive = true,
}) async {
  final res = await showLedgerSheet<bool>(
    context,
    builder: (_) => _PaymentSheet(customer: customer, isReceive: isReceive),
  );
  return res ?? false;
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.customer, required this.isReceive});

  final Customer customer;
  final bool isReceive;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late String _currency;
  bool _receive = true;
  bool _busy = false;
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    final repo = context.read<AppRepository>();
    _receive = widget.isReceive;
    _currency = repo.settings.baseCurrency;
    _categoryId = repo.defaultCategoryId(
      _receive ? TxnKind.income : TxnKind.expense,
      scope: TxnScope.business,
    );
    final balance = repo.balanceOf(widget.customer);
    if (balance > 0 && _receive) {
      _amount.text = groupedNumber(balance);
    } else if (balance < 0 && !_receive) {
      _amount.text = groupedNumber(balance.abs());
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return; // Double-tap guard.
    if (_formKey.currentState?.validate() != true) return;
    Haptics.confirm();
    // The repository, navigator, and messenger are resolved before the await
    // so the rest of this method never reads the BuildContext again.
    final repo = context.read<AppRepository>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final amount = parseAmount(_amount.text);
      await repo.addPayment(
        customer: widget.customer,
        amount: amount,
        currencyCode: _currency,
        date: DateTime.now(),
        isReceive: _receive,
        note: _note.text.trim(),
        categoryId: _categoryId,
      );
      if (!mounted) return;
      // The signature "money recorded" moment: coin, impact ring, stamp.
      MoneyCelebration.recorded(context);
      showMessengerSnack(
        messenger,
        _receive ? 'Payment received' : 'Payment made',
      );
      navigator.pop(true);
    } catch (_) {
      showMessengerSnack(
        messenger,
        'Saving failed. Please try again.',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final balance = repo.balanceOf(widget.customer);
    final absBalance = balance.abs();
    final catKind = _receive ? TxnKind.income : TxnKind.expense;
    final accent = _receive ? AppTheme.revenue : AppTheme.expense;
    final actionLabel = _busy
        ? 'Saving…'
        : (_receive ? 'Record receipt' : 'Record payment');

    // The sheet route keeps the sheet clear of the soft keyboard and measures
    // its maximum height against what is actually visible, so no `viewInsets`
    // padding is needed here. What is needed is a scrollable body: on a short
    // screen the keyboard alone can leave less room than this form takes, and
    // a fixed column would overflow with the confirm button out of reach.
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The shared handle: one widget, one size, one colour, in every
              // sheet of the app.
              const SheetHandle(),
              const SizedBox(height: 14),
              Text(
                '{who} {customer}'.trArgs({
                  'who': _receive ? 'Receive from'.tr : 'Pay to'.tr,
                  'customer': widget.customer.name,
                }),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              // The balance always carries its sign so a creditor balance
              // is visually distinct from a debtor one — the old version
              // showed a bare positive number with only "(creditor)" in
              // parentheses, which was easy to skim past.
              Text(
                balance >= 0
                    ? 'Balance: {amount} (debtor)'.trArgs({
                        'amount': Money.text(balance, signed: true),
                      })
                    : 'Balance: {amount} (creditor)'.trArgs({
                        'amount': Money.text(balance, signed: true),
                      }),
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: true,
                    label: Text('Receive from customer'.tr),
                  ),
                  ButtonSegment(value: false, label: Text('Pay customer'.tr)),
                ],
                selected: {_receive},
                onSelectionChanged: (s) => setState(() {
                  _receive = s.first;
                  _categoryId = repo.defaultCategoryId(
                    _receive ? TxnKind.income : TxnKind.expense,
                    scope: TxnScope.business,
                  );
                }),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AmountField(
                      controller: _amount,
                      label: 'Amount'.tr,
                      currency: _currency,
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 112,
                    child: SelectField<String>(
                      label: 'Currency'.tr,
                      value: _currency,
                      items: repo.settings.currencies
                          .map((c) => c.code)
                          .toList(),
                      labelOf: (c) => Money.symbol(c),
                      onChanged: (c) =>
                          setState(() => _currency = c ?? _currency),
                    ),
                  ),
                ],
              ),
              if (absBalance > 0.5) ...[
                const SizedBox(height: 8),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _amount,
                  builder: (context, _, _) {
                    final typed = parseAmount(_amount.text);
                    final halfBal = (absBalance / 2).roundToDouble();
                    final isFull = (typed - absBalance).abs() < 1;
                    final isHalf =
                        halfBal > 0 && (typed - halfBal).abs() < 1;
                    return Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        InkWell(
                          key: const ValueKey('payment_full_balance_chip'),
                          borderRadius: BorderRadius.circular(9),
                          onTap: () {
                            Haptics.selection();
                            _amount.text = groupedNumber(
                              absBalance,
                              decimals: Money.decimals(_currency),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: isFull
                                  ? accent.withValues(alpha: 0.14)
                                  : scheme.onSurface.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: isFull
                                    ? accent.withValues(alpha: 0.55)
                                    : scheme.onSurface.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Text(
                              '${'Full balance'.tr} (${Money.text(absBalance, compact: true)})',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: isFull
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: isFull
                                    ? accent
                                    : scheme.onSurface.withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                        ),
                        InkWell(
                          key: const ValueKey('payment_half_balance_chip'),
                          borderRadius: BorderRadius.circular(9),
                          onTap: () {
                            Haptics.selection();
                            _amount.text = groupedNumber(
                              halfBal,
                              decimals: Money.decimals(_currency),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: isHalf
                                  ? accent.withValues(alpha: 0.14)
                                  : scheme.onSurface.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: isHalf
                                    ? accent.withValues(alpha: 0.55)
                                    : scheme.onSurface.withValues(alpha: 0.12),
                              ),
                            ),
                            child: Text(
                              '50% of balance'.tr,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: isHalf
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: isHalf
                                    ? accent
                                    : scheme.onSurface.withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
              const SizedBox(height: 12),
              AccountSelectorSection(
                repo: repo,
                categoryKind: catKind,
                scope: TxnScope.business,
                selectedCategoryId:
                    _categoryId ??
                    repo.defaultCategoryId(catKind, scope: TxnScope.business),
                shortcuts: repo.shortcutCategories(
                  catKind,
                  scope: TxnScope.business,
                ),
                onSelectCategory: (cat) =>
                    setState(() => _categoryId = cat.id),
              ),
              const SizedBox(height: 12),
              AppTextField(
                controller: _note,
                label: 'Description (optional)'.tr,
                icon: Icons.notes_rounded,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _receive
                            ? Icons.call_received_rounded
                            : Icons.call_made_rounded,
                      ),
                label: Text(actionLabel.tr),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
