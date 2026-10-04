import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format_utils.dart';
import '../../core/jalali_utils.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../widgets/widgets.dart';
import 'contact_edit_page.dart';
import 'plan_edit_page.dart';

/// ثبت فروش اشتراک جدید یا تمدید اشتراک
class SellSubscriptionPage extends StatefulWidget {
  const SellSubscriptionPage({super.key, this.contact, this.plan, this.renewFrom});

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
    _title.text = 'اشتراک';
    _plan = widget.plan;

    final old = widget.renewFrom;
    if (old != null) {
      _contact = repo.customerById(old.customerId);
      _plan = repo.planById(old.planId);
      _title.text = old.planName;
      _price.text = groupedNumber(old.amount, decimals: Money.decimals(old.currency));
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
      _received.text = groupedNumber(price, decimals: Money.decimals(_receiveCurrency));
    } else {
      _contact = widget.contact;
      final plan = _plan;
      if (plan != null) {
        _title.text = plan.name;
        _price.text = groupedNumber(plan.price, decimals: Money.decimals(plan.currency));
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
    return DateTime(base.year, base.month, base.day)
        .add(Duration(days: _durationValue - 1));
  }

  void _applyPlan(Plan? plan) {
    setState(() {
      _plan = plan;
      if (plan != null) {
        _title.text = plan.name;
        _price.text = groupedNumber(plan.price, decimals: Money.decimals(plan.currency));
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
      showSnack(context, 'اول مشتری را انتخاب کنید', error: true);
      return;
    }
    if (_formKey.currentState?.validate() != true) return;
    final price = parseAmount(_price.text);
    final received = parseAmount(_received.text);
    await repo.sellSubscription(
      customer: _contact!,
      plan: _plan,
      title: _title.text.trim().isEmpty ? 'اشتراک' : _title.text.trim(),
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
    showSnack(context, isRenew ? 'اشتراک تمدید شد' : 'فروش ثبت شد');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final currencies = repo.settings.currencies;
    final remaining =
        (_currency == _receiveCurrency) ? parseAmount(_price.text) - parseAmount(_received.text) : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isRenew ? 'تمدید اشتراک' : 'فروش اشتراک جدید'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            // ---------- مشتری ----------
            Row(
              children: [
                Expanded(
                  child: SelectField<Customer>(
                    label: 'مشتری',
                    icon: Icons.person_outline_rounded,
                    value: _contact,
                    items: repo.activeCustomers,
                    labelOf: (c) => c.name,
                    subOf: (c) =>
                        (repo.balanceOf(c)).abs() < 1 ? (c.phone.isEmpty ? 'تسویه' : c.phone) : '${c.phone.isEmpty ? '' : '${c.phone} • '}${Money.text(repo.balanceOf(c), signed: true)}',
                    clearable: false,
                    sheetTitle: 'انتخاب مشتری',
                    searchHint: 'نام مشتری…',
                    onChanged: (c) => setState(() => _contact = c),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'مشتری جدید',
                  onPressed: () async {
                    final created = await Navigator.push<Customer>(
                      context,
                      MaterialPageRoute(builder: (_) => const ContactEditPage()),
                    );
                    if (created != null) setState(() => _contact = created);
                  },
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ---------- پلن آماده ----------
            SelectField<Plan>(
              label: 'پلن آماده (اختیاری)',
              icon: Icons.local_offer_outlined,
              value: _plan,
              items: repo.activePlans,
              clearable: true,
              labelOf: (p) => p.name,
              subOf: (p) => '${Money.text(p.price, currency: p.currency)} • ${p.durationLabel}',
              extraActionLabel: 'مدیریت پلن‌ها',
              onExtraAction: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const PlansPage())),
              onChanged: _applyPlan,
            ),
            const SizedBox(height: 14),

            AppTextField(
              controller: _title,
              label: 'عنوان سرویس',
              hint: 'مثلاً: یک‌ماهه نامحدود - دو کاربره',
              icon: Icons.vpn_key_outlined,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'عنوان را وارد کنید' : null,
            ),
            const SizedBox(height: 14),

            // ---------- قیمت ----------
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AmountField(controller: _price, label: 'مبلغ فروش', currency: _currency),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 112,
                  child: SelectField<String>(
                    label: 'ارز',
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

            // ---------- مدت ----------
            CardBox(
              child: Column(
                children: [
                  JalaliDateField(
                    label: 'تاریخ شروع',
                    value: _start,
                    onChanged: (d) => setState(() {
                      _start = d;
                      if (!_manualEnd) _end = _computeEnd();
                    }),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('مدت:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
                        visualDensity: VisualDensity.compact,
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            '${Fmt.toFaDigits('$_durationValue')} ${_unitIsMonth ? 'ماه' : 'روز'}',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      IconButton.outlined(
                        onPressed: () => setState(() {
                          _durationValue++;
                          _manualEnd = false;
                          _end = _computeEnd();
                        }),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('ماه')),
                      ButtonSegment(value: false, label: Text('روز')),
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
                    label: 'تاریخ پایان (قابل تغییر)',
                    value: _end,
                    helper: '${Fmt.toFaDigits('${_end.difference(J.dateOnly(_start)).inDays + 1}')} روز',
                    onChanged: (d) => setState(() {
                      _end = d;
                      _manualEnd = true;
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ---------- دریافت ----------
            SectionTitle('پرداخت', icon: Icons.payments_outlined),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AmountField(
                    controller: _received,
                    label: 'همین حالا دریافت شد',
                    currency: _receiveCurrency,
                    validator: (_) => null,
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 112,
                  child: SelectField<String>(
                    label: 'ارز',
                    value: _receiveCurrency,
                    items: currencies.map((c) => c.code).toList(),
                    labelOf: (code) => Money.symbol(code),
                    onChanged: (code) =>
                        setState(() => _receiveCurrency = code ?? _receiveCurrency),
                  ),
                ),
              ],
            ),
            if (remaining != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(
                      remaining <= 0 ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                      size: 15,
                      color: remaining <= 0
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      remaining <= 0
                          ? 'تسویه شد'
                          : 'باقی‌مانده به‌صورت بدهی مشتری ثبت می‌شود: ${Money.text(remaining, currency: _currency)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: remaining <= 0
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFB45309),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 14),

            SelectField<Category>(
              label: 'دسته‌بندی درآمد',
              icon: Icons.category_outlined,
              value: repo.categoryById(_categoryId),
              items: repo.categoriesOf(TxnKind.income),
              labelOf: (c) => c.name,
              onChanged: (c) => setState(() => _categoryId = c?.id),
            ),
            const SizedBox(height: 14),

            AppTextField(controller: _note, label: 'یادداشت', icon: Icons.notes_rounded, maxLines: 2),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _autoRenew,
              onChanged: (v) => setState(() => _autoRenew = v),
              title: const Text('تمدید خودکار', style: TextStyle(fontSize: 13.5)),
              subtitle: const Text('فقط به‌عنوان یادآوری است', style: TextStyle(fontSize: 11.5)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _save,
              icon: Icon(isRenew ? Icons.autorenew_rounded : Icons.check_rounded),
              label: Text(isRenew ? 'ثبت تمدید' : 'ثبت فروش'),
            ),
          ],
        ),
      ),
    );
  }
}
