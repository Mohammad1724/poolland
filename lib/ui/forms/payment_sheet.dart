import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format_utils.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../widgets/widgets.dart';

/// Quick sheet for recording a receipt from or payment to a customer
Future<bool> showPaymentSheet(
  BuildContext context, {
  required Customer customer,
  bool isReceive = true,
}) async {
  final res = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
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

  @override
  void initState() {
    super.initState();
    _receive = widget.isReceive;
    _currency = context.read<AppRepository>().settings.baseCurrency;
    final balance = context.read<AppRepository>().balanceOf(widget.customer);
    if (balance > 0 && _receive) {
      _amount.text = groupedNumber(balance);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final theme = Theme.of(context);
    final balance = repo.balanceOf(widget.customer);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                        color: theme.dividerColor, borderRadius: BorderRadius.circular(2))),
              ),
              const SizedBox(height: 14),
              Text('${_receive ? 'Receive from' : 'Pay to'} ${widget.customer.name}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                balance >= 0
                    ? 'Balance: ${Money.text(balance, signed: true)} (debtor)'
                    : 'Balance: ${Money.text(balance.abs())} (creditor)',
                style: TextStyle(
                    fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('Receive from customer')),
                  ButtonSegment(value: false, label: Text('Pay customer')),
                ],
                selected: {_receive},
                onSelectionChanged: (s) => setState(() => _receive = s.first),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AmountField(controller: _amount, label: 'Amount', currency: _currency),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 112,
                    child: SelectField<String>(
                      label: 'Currency',
                      value: _currency,
                      items: repo.settings.currencies.map((c) => c.code).toList(),
                      labelOf: (c) => Money.symbol(c),
                      onChanged: (c) => setState(() => _currency = c ?? _currency),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              AppTextField(controller: _note, label: 'Description (optional)', icon: Icons.notes_rounded),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  if (_formKey.currentState?.validate() != true) return;
                  final amount = parseAmount(_amount.text);
                  await repo.addPayment(
                    customer: widget.customer,
                    amount: amount,
                    currencyCode: _currency,
                    date: DateTime.now(),
                    isReceive: _receive,
                    note: _note.text.trim(),
                  );
                  if (!context.mounted) return;
                  Navigator.pop(context, true);
                  showSnack(context, _receive ? 'Payment received' : 'Payment made');
                },
                icon: Icon(_receive ? Icons.call_received_rounded : Icons.call_made_rounded),
                label: Text(_receive ? 'Record receipt' : 'Record payment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
