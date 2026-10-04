import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format_utils.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../widgets/widgets.dart';

/// مدیریت پلن‌های آماده فروش
class PlansPage extends StatelessWidget {
  const PlansPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('پلن‌های فروش')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const PlanEditPage())),
        icon: const Icon(Icons.add_rounded),
        label: const Text('پلن جدید'),
      ),
      body: repo.plans.isEmpty
          ? const EmptyState(
              icon: Icons.local_offer_outlined,
              title: 'هنوز پلنی نساخته‌اید',
              text: 'پلن‌ها قالب‌های آماده فروش هستند (مثلاً «۱ ماهه ۵۰ گیگ»).\nبا ساخت پلن، ثبت فروش چند ثانیه‌ای می‌شود.',
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
              itemCount: repo.plans.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final p = repo.plans[i];
                return CardBox(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => PlanEditPage(existing: p))),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.local_offer_outlined,
                            size: 18, color: Theme.of(context).colorScheme.primary),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name,
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(
                              '${Money.text(p.price, currency: p.currency)} • ${p.durationLabel}',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.6)),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_left_rounded, size: 20),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

/// افزودن/ویرایش پلن
class PlanEditPage extends StatefulWidget {
  const PlanEditPage({super.key, this.existing});

  final Plan? existing;

  @override
  State<PlanEditPage> createState() => _PlanEditPageState();
}

class _PlanEditPageState extends State<PlanEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _note = TextEditingController();
  late String _currency;
  int _duration = 1;
  PlanDurationUnit _unit = PlanDurationUnit.month;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _currency = context.read<AppRepository>().settings.baseCurrency;
    final p = widget.existing;
    if (p != null) {
      _name.text = p.name;
      _price.text = groupedNumber(p.price, decimals: Money.decimals(p.currency));
      _currency = p.currency;
      _duration = p.durationValue;
      _unit = p.durationUnit;
      _note.text = p.note;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    final repo = context.read<AppRepository>();
    final price = parseAmount(_price.text);
    final base = Plan(
      id: widget.existing?.id ?? '',
      name: _name.text.trim(),
      price: price,
      currency: _currency,
      durationValue: _duration,
      durationUnit: _unit,
      note: _note.text.trim(),
      archived: widget.existing?.archived ?? false,
    );
    if (isEdit) {
      await repo.updatePlan(base);
    } else {
      await repo.addPlan(base);
    }
    if (!mounted) return;
    Navigator.pop(context);
    showSnack(context, isEdit ? 'پلن ویرایش شد' : 'پلن اضافه شد');
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'ویرایش پلن' : 'پلن جدید'),
        actions: [
          if (isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final ok = await confirmDialog(context,
                    title: 'حذف پلن',
                    message: 'این پلن حذف شود؟ (فروش‌های قبلی دست‌نخورده می‌مانند)',
                    danger: true,
                    okLabel: 'حذف');
                if (!ok) return;
                await repo.deletePlan(widget.existing!.id);
                if (!context.mounted) return;
                Navigator.pop(context);
              },
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            AppTextField(
              controller: _name,
              label: 'نام پلن',
              hint: 'مثلاً: ۱ ماهه ۵۰ گیگ',
              icon: Icons.label_outline_rounded,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'نام را وارد کنید' : null,
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AmountField(
                      controller: _price, label: 'قیمت', currency: _currency, validator: (_) => null),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 112,
                  child: SelectField<String>(
                    label: 'ارز',
                    value: _currency,
                    items: repo.settings.currencies.map((c) => c.code).toList(),
                    labelOf: (c) => Money.symbol(c),
                    onChanged: (c) => setState(() => _currency = c ?? _currency),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text('مدت اعتبار', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton.outlined(
                  onPressed: _duration > 1 ? () => setState(() => _duration--) : null,
                  icon: const Icon(Icons.remove_rounded, size: 18),
                ),
                Expanded(
                  child: Center(
                    child: Text(Fmt.toFaDigits('$_duration'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
                IconButton.outlined(
                  onPressed: () => setState(() => _duration++),
                  icon: const Icon(Icons.add_rounded, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SegmentedButton<PlanDurationUnit>(
              segments: const [
                ButtonSegment(value: PlanDurationUnit.month, label: Text('ماه')),
                ButtonSegment(value: PlanDurationUnit.day, label: Text('روز')),
              ],
              selected: {_unit},
              onSelectionChanged: (s) => setState(() => _unit = s.first),
            ),
            const SizedBox(height: 16),
            AppTextField(controller: _note, label: 'توضیح (اختیاری)', maxLines: 2),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(isEdit ? 'ذخیره' : 'افزودن پلن'),
            ),
          ],
        ),
      ),
    );
  }
}
