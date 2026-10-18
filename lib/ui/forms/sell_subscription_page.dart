import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format_utils.dart';
import '../../core/jalali_utils.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../design.dart';
import '../widgets/widgets.dart';
import '../motion_kit.dart';
import 'contact_edit_page.dart';
import 'plan_edit_page.dart';

import '../../core/localization.dart';

/// Record a new subscription sale or renewal
class SellSubscriptionPage extends StatefulWidget {
  const SellSubscriptionPage({
    super.key,
    this.contact,
    this.plan,
    this.renewFrom,
  });

  final Customer? contact;
  final Plan? plan;
  final Subscription? renewFrom;

  @override
  State<SellSubscriptionPage> createState() => _SellSubscriptionPageState();
}

class _SellSubscriptionPageState extends State<SellSubscriptionPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _price = TextEditingController();
  final _received = TextEditingController();
  final _note = TextEditingController();

  Customer? _contact;
  Plan? _plan;
  String _currency = 'IRT';
  String _receiveCurrency = 'IRT';
  DateTime _start = DateTime.now();
  DateTime _end = DateTime.now();
  int _durationValue = 1;
  bool _unitIsMonth = true;
  bool _manualEnd = false;
  bool _autoRenew = false;
  String? _categoryId;

  bool get isRenew => widget.renewFrom != null;

  @override
  void initState() {
    super.initState();
    final repo = context.read<AppRepository>();
    _currency = repo.settings.baseCurrency;
    _receiveCurrency = repo.settings.baseCurrency;
    // The default value is English; setting the cursor at the end avoids a
    // visible jump when the user starts typing in an RTL context — the
    // selection would otherwise default to position 0 (the left edge) and
    // the first keystroke would insert before the existing text.
    _title.value = TextEditingValue(
      text: 'Subscription',
      selection: TextSelection.collapsed(offset: 'Subscription'.length),
    );
    _plan = widget.plan;

    final old = widget.renewFrom;
    if (old != null) {
      _contact = repo.customerById(old.customerId);
      _plan = repo.planById(old.planId);
      _title.text = old.planName;
      _price.text = groupedNumber(
        old.amount,
        decimals: Money.decimals(old.currency),
      );
      _currency = old.currency;
      _receiveCurrency = old.currency;
      _start = J.addDays(old.endDate, 1);
      _autoRenew = old.autoRenew;
      _note.text = old.note;
      final plan = _plan;
      if (plan != null) {
        _durationValue = plan.durationValue;
        _unitIsMonth = plan.durationUnit == PlanDurationUnit.month;
      } else {
        final days = old.durationDays;
        _durationValue = days > 25 ? (days / 30).round().clamp(1, 60) : days;
        _unitIsMonth = days > 25;
      }
      final price = old.amount;
      _received.text = groupedNumber(
        price,
        decimals: Money.decimals(_receiveCurrency),
      );
    } else {
      _contact = widget.contact;
      final plan = _plan;
      if (plan != null) {
        _title.text = plan.name;
        _price.text = groupedNumber(
          plan.price,
          decimals: Money.decimals(plan.currency),
        );
        _currency = plan.currency;
        _receiveCurrency = plan.currency;
        _durationValue = plan.durationValue;
        _unitIsMonth = plan.durationUnit == PlanDurationUnit.month;
      }
    }
    _end = _computeEnd();
  }

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    _received.dispose();
    _note.dispose();
    super.dispose();
  }

  DateTime _computeEnd() {
    final base = J.dateOnly(_start);
    if (_unitIsMonth) {
      return J.addDays(J.addMonths(base, _durationValue), -1);
    }
    return DateTime(
      base.year,
      base.month,
      base.day,
    ).add(Duration(days: _durationValue - 1));
  }

  void _applyPlan(Plan? plan) {
    setState(() {
      _plan = plan;
      if (plan != null) {
        _title.text = plan.name;
        _price.text = groupedNumber(
          plan.price,
          decimals: Money.decimals(plan.currency),
        );
        _currency = plan.currency;
        _receiveCurrency = plan.currency;
        _durationValue = plan.durationValue;
        _unitIsMonth = plan.durationUnit == PlanDurationUnit.month;
        _manualEnd = false;
        _end = _computeEnd();
      }
    });
  }

  Future<void> _save() async {
    final repo = context.read<AppRepository>();
    if (_contact == null) {
      showSnack(context, 'Select a customer first.', error: true);
      return;
    }
    if (_formKey.currentState?.validate() != true) return;
    // Resolved before the write: the page pops itself right after it, and
    // the confirmation has to outlive the page.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final price = parseAmount(_price.text);
    final received = parseAmount(_received.text);
    await repo.sellSubscription(
      customer: _contact!,
      plan: _plan,
      title: _title.text.trim().isEmpty
          ? 'Subscription'.tr
          : _title.text.trim(),
      price: price,
      currencyCode: _currency,
      start: _start,
      end: _end,
      received: received,
      receiveCurrency: _receiveCurrency,
      autoRenew: _autoRenew,
      note: _note.text.trim(),
      categoryId: _categoryId,
    );
    if (!mounted) return;
    MoneyCelebration.recorded(context);
    showMessengerSnack(
      messenger,
      isRenew ? 'Subscription renewed' : 'Sale recorded',
    );
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final currencies = repo.settings.currencies;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          (isRenew ? 'Renew subscription' : 'Sell a subscription').tr,
        ),
      ),
      bottomNavigationBar: FormActionBar(
        label: isRenew ? 'Record renewal' : 'Record sale',
        icon: isRenew ? Icons.autorenew_rounded : Icons.check_rounded,
        // A sale without a customer has nowhere to go: the account cannot be
        // updated and the subscription has no owner. Say so before the tap
        // instead of only after it.
        hint: _contact == null ? 'Select a customer first.'.tr : null,
        onPressed: _save,
      ),
      body: Form(
        key: _formKey,
        child: FormPageContent(
          maxWidth: 760,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              // ---------- Customer ----------
              Row(
                children: [
                  Expanded(
                    child: SelectField<Customer>(
                      label: 'Customer'.tr,
                      icon: Icons.person_outline_rounded,
                      value: _contact,
                      items: repo.activeCustomers,
                      labelOf: (c) => c.name,
                      subOf: (c) => (repo.balanceOf(c)).abs() < 1
                          ? (c.phone.isEmpty ? 'Settled' : c.phone)
                          : '${c.phone.isEmpty ? '' : '${c.phone} • '}${Money.text(repo.balanceOf(c), signed: true)}',
                      clearable: false,
                      sheetTitle: 'Select customer'.tr,
                      searchHint: 'Customer name...'.tr,
                      onChanged: (c) => setState(() => _contact = c),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    tooltip: 'New customer'.tr,
                    onPressed: () async {
                      final created = await Navigator.push<Customer>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ContactEditPage(),
                        ),
                      );
                      if (created != null) setState(() => _contact = created);
                    },
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ---------- Saved plan ----------
              SelectField<Plan>(
                label: 'Saved plan (optional)'.tr,
                icon: Icons.local_offer_outlined,
                value: _plan,
                items: repo.activePlans,
                clearable: true,
                labelOf: (p) => p.name,
                subOf: (p) =>
                    '${Money.text(p.price, currency: p.currency)} • ${p.durationLabel}',
                extraActionLabel: 'Manage plans',
                onExtraAction: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PlansPage()),
                ),
                onChanged: _applyPlan,
              ),
              const SizedBox(height: 14),

              AppTextField(
                controller: _title,
                label: 'Service name'.tr,
                hint: 'e.g. 1-month unlimited - 2 devices'.tr,
                icon: Icons.vpn_key_outlined,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Enter a service name'
                    : null,
              ),
              const SizedBox(height: 14),

              // ---------- Price ----------
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AmountField(
                      controller: _price,
                      label: 'Sale amount'.tr,
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
                      items: currencies.map((c) => c.code).toList(),
                      labelOf: (code) => Money.symbol(code),
                      onChanged: (code) => setState(() {
                        _currency = code ?? _currency;
                        _receiveCurrency = _currency;
                      }),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ---------- Duration ----------
              CardBox(
                child: Column(
                  children: [
                    JalaliDateField(
                      label: 'Start date'.tr,
                      value: _start,
                      onChanged: (d) => setState(() {
                        _start = d;
                        if (!_manualEnd) _end = _computeEnd();
                      }),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          'Duration:'.tr,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.outlined(
                          onPressed: _durationValue > 1
                              ? () => setState(() {
                                  _durationValue--;
                                  _manualEnd = false;
                                  _end = _computeEnd();
                                })
                              : null,
                          icon: const Icon(Icons.remove_rounded, size: 18),
                          style: IconButton.styleFrom(
                            minimumSize: const Size(Taps.icon, Taps.icon),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              '$_durationValue ${(_unitIsMonth ? 'month' : 'day').tr}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        // A subscription longer than five years (60 months or
                        // ~1825 days) is almost certainly a mistake — a slip
                        // of the finger on the plus button. Capping it avoids
                        // absurd dates while still allowing every realistic
                        // plan length.
                        IconButton.outlined(
                          onPressed: (_unitIsMonth
                                      ? _durationValue >= 60
                                      : _durationValue >= 1825)
                              ? null
                              : () => setState(() {
                                  _durationValue++;
                                  _manualEnd = false;
                                  _end = _computeEnd();
                                }),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          style: IconButton.styleFrom(
                            minimumSize: const Size(Taps.icon, Taps.icon),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(value: true, label: Text('month'.tr)),
                        ButtonSegment(value: false, label: Text('day'.tr)),
                      ],
                      selected: {_unitIsMonth},
                      onSelectionChanged: (s) => setState(() {
                        _unitIsMonth = s.first;
                        _manualEnd = false;
                        _end = _computeEnd();
                      }),
                    ),
                    const SizedBox(height: 12),
                    JalaliDateField(
                      label: 'End date (editable)'.tr,
                      value: _end,
                      helper: '{days} days'.trArgs({
                        'days': _end.difference(J.dateOnly(_start)).inDays + 1,
                      }),
                      onChanged: (d) => setState(() {
                        _end = d;
                        _manualEnd = true;
                      }),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ---------- Payment received ----------
              SectionTitle('Payment', icon: Icons.payments_outlined),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AmountField(
                      controller: _received,
                      label: 'Received now'.tr,
                      currency: _receiveCurrency,
                      textInputAction: TextInputAction.next,
                      validator: (_) => null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 112,
                    child: SelectField<String>(
                      label: 'Currency'.tr,
                      value: _receiveCurrency,
                      items: currencies.map((c) => c.code).toList(),
                      labelOf: (code) => Money.symbol(code),
                      onChanged: (code) => setState(
                        () => _receiveCurrency = code ?? _receiveCurrency,
                      ),
                    ),
                  ),
                ],
              ),
              // The consequence line depends on both amounts, and neither
              // field rebuilds this page — so it listens to the controllers
              // itself. Read straight from `_price.text` in `build` it stayed
              // frozen at whatever the two fields held when the page was last
              // rebuilt for another reason: a renewal (both fields pre-filled,
              // so the line said "paid in full") would keep saying that after
              // the received amount was cleared. Same fix, same reason as the
              // cash/credit hint in the transaction form.
              ListenableBuilder(
                listenable: Listenable.merge([_price, _received]),
                builder: (context, _) {
                  final price = parseAmount(_price.text);
                  // Only meaningful once there is a price, and only when both
                  // sides are the same currency: subtracting 3 USDT from
                  // 500,000 Toman says nothing. With an untouched form the old
                  // version computed 0 - 0 and announced "Paid in full" for a
                  // sale that did not exist yet.
                  final remaining = (_currency == _receiveCurrency && price > 0)
                      ? price - parseAmount(_received.text)
                      : null;
                  if (remaining == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      children: [
                        Icon(
                          remaining <= 0
                              ? Icons.check_circle_rounded
                              : Icons.info_outline_rounded,
                          size: 15,
                          color: remaining <= 0
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFF59E0B),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            remaining <= 0
                                ? 'Paid in full'.tr
                                : 'The remaining balance will be recorded as customer debt: {amount}'
                                      .trArgs({
                                        'amount': Money.text(
                                          remaining,
                                          currency: _currency,
                                        ),
                                      }),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: remaining <= 0
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFFB45309),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),

              SelectField<Category>(
                label: 'Income category'.tr,
                icon: Icons.category_outlined,
                value: repo.categoryById(_categoryId),
                items: repo.pickOrderCategories(TxnKind.income),
                labelOf: (c) => c.name,
                isChild: (c) => c.parentId != null,
                onChanged: (c) => setState(() => _categoryId = c?.id),
              ),
              const SizedBox(height: 14),

              AppTextField(
                controller: _note,
                label: 'Note'.tr,
                icon: Icons.notes_rounded,
                maxLines: 2,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _autoRenew,
                onChanged: (v) => setState(() => _autoRenew = v),
                title: Text('Auto-renew'.tr, style: TextStyle(fontSize: 13.5)),
                subtitle: Text(
                  'Reminder only'.tr,
                  style: TextStyle(fontSize: 11.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
