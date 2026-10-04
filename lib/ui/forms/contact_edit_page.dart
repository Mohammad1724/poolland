import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format_utils.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../widgets/widgets.dart';

/// افزودن / ویرایش مشتری یا تأمین‌کننده
class ContactEditPage extends StatefulWidget {
  const ContactEditPage({super.key, this.existing, this.initialName});

  final Customer? existing;
  final String? initialName;

  @override
  State<ContactEditPage> createState() => _ContactEditPageState();
}

class _ContactEditPageState extends State<ContactEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _telegram = TextEditingController();
  final _note = TextEditingController();
  final _opening = TextEditingController();

  bool _openingIsDebt = true;
  bool _archived = false;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    if (c != null) {
      _name.text = c.name;
      _phone.text = c.phone.isEmpty ? '' : Fmt.toFaDigits(c.phone);
      _telegram.text = c.telegram;
      _note.text = c.note;
      _archived = c.archived;
      if (c.openingBalance != 0) {
        _openingIsDebt = c.openingBalance > 0;
        _opening.text = groupedNumber(c.openingBalance.abs(), decimals: 0);
      }
    } else if (widget.initialName != null) {
      _name.text = widget.initialName!;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _telegram.dispose();
    _note.dispose();
    _opening.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    final repo = context.read<AppRepository>();
    final opening = parseAmount(_opening.text) * (_openingIsDebt ? 1 : -1);
    final digits = _phone.text.replaceAll(RegExp(r'[^0-9+]'), '');

    if (isEdit) {
      final c = widget.existing!.copyWith(
        name: _name.text.trim(),
        phone: digits,
        telegram: _telegram.text.trim(),
        note: _note.text.trim(),
        openingBalance: opening,
        archived: _archived,
      );
      await repo.updateCustomer(c);
      if (!mounted) return;
      Navigator.pop(context, c);
    } else {
      final c = await repo.addCustomer(
        name: _name.text.trim(),
        phone: digits,
        telegram: _telegram.text.trim(),
        note: _note.text.trim(),
        openingBalance: opening,
      );
      if (!mounted) return;
      Navigator.pop(context, c);
    }
    if (mounted) showSnack(context, isEdit ? 'تغییرات ذخیره شد' : 'مشتری اضافه شد');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'ویرایش طرف حساب' : 'طرف حساب جدید'),
        actions: [
          if (isEdit)
            IconButton(
              tooltip: 'حذف',
              onPressed: () async {
                final repo = context.read<AppRepository>();
                final count = repo.txnsOfCustomer(widget.existing!.id).length;
                final ok = await confirmDialog(
                  context,
                  title: 'حذف طرف حساب',
                  message: count > 0
                      ? 'این طرف حساب $count تراکنش دارد. با حذف او، همه‌ی آن تراکنش‌ها هم حذف می‌شوند. مطمئن هستید؟'
                      : 'این طرف حساب حذف شود؟',
                  okLabel: 'حذف',
                  danger: true,
                );
                if (!ok) return;
                await repo.deleteCustomer(widget.existing!.id);
                if (!context.mounted) return;
                Navigator.pop(context);
                showSnack(context, 'طرف حساب حذف شد');
              },
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            AppTextField(
              controller: _name,
              label: 'نام',
              icon: Icons.person_outline_rounded,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'نام را وارد کنید' : null,
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _phone,
              label: 'شماره تماس',
              hint: '۰۹۱۲…',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 14),
            AppTextField(
              controller: _telegram,
              label: 'آیدی تلگرام (اختیاری)',
              hint: '@username',
              icon: Icons.send_outlined,
            ),
            const SizedBox(height: 14),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: AmountField(
                    controller: _opening,
                    label: 'بدهی/طلب قبلی',
                    validator: (_) => null,
                  ),
                ),
                const SizedBox(width: 8),
                SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, label: Text('بدهکار')),
                    ButtonSegment(value: false, label: Text('بستانکار')),
                  ],
                  selected: {_openingIsDebt},
                  onSelectionChanged: (s) => setState(() => _openingIsDebt = s.first),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'اگر از قبل حساب باز مانده دارید، اینجا وارد کنید (مثلاً مشتری قدیمی که ۵۰۰ هزار بدهکار است).',
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55)),
              ),
            ),
            const SizedBox(height: 14),
            AppTextField(controller: _note, label: 'یادداشت', maxLines: 3, icon: Icons.notes_rounded),
            if (isEdit)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _archived,
                onChanged: (v) => setState(() => _archived = v),
                title: const Text('بایگانی شده', style: TextStyle(fontSize: 13.5)),
                subtitle: const Text('در لیست اصلی نمایش داده نمی‌شود',
                    style: TextStyle(fontSize: 11.5)),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(isEdit ? 'ذخیره تغییرات' : 'افزودن'),
            ),
          ],
        ),
      ),
    );
  }
}
