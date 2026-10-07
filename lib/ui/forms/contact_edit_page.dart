import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format_utils.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../widgets/widgets.dart';

import '../../core/localization.dart';

/// Add or edit a customer or supplier
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
  final _identifiers = TextEditingController();

  bool _openingIsDebt = true;
  bool _archived = false;

  bool get isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    if (c != null) {
      _name.text = c.name;
      _phone.text = c.phone.isEmpty ? '' : c.phone;
      _telegram.text = c.telegram;
      _note.text = c.note;
      _archived = c.archived;
      _identifiers.text = c.bankIdentifiers.join(' , ');
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
    _identifiers.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;
    final repo = context.read<AppRepository>();
    final opening = parseAmount(_opening.text) * (_openingIsDebt ? 1 : -1);
    final digits = _phone.text.replaceAll(RegExp(r'[^0-9+]'), '');
    final identifiers = _identifiers.text
        .split(RegExp(r'[,\u060C\s]+'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (isEdit) {
      final c = widget.existing!.copyWith(
        name: _name.text.trim(),
        phone: digits,
        telegram: _telegram.text.trim(),
        note: _note.text.trim(),
        openingBalance: opening,
        archived: _archived,
        bankIdentifiers: identifiers,
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
        bankIdentifiers: identifiers,
      );
      if (!mounted) return;
      Navigator.pop(context, c);
    }
    if (mounted) {
      showSnack(context, isEdit ? 'Changes saved'.tr : 'Customer added'.tr);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text((isEdit ? 'Edit contact' : 'New contact').tr),
        actions: [
          if (isEdit)
            IconButton(
              tooltip: 'Delete'.tr,
              onPressed: () async {
                final repo = context.read<AppRepository>();
                final count = repo.txnsOfCustomer(widget.existing!.id).length;
                final ok = await confirmDialog(
                  context,
                  title: 'Delete contact'.tr,
                  message: count > 0
                      ? 'This contact has $count transactions. Deleting them will also delete all of those transactions. Continue?'
                      : 'Delete this contact?',
                  okLabel: 'Delete'.tr,
                  danger: true,
                );
                if (!ok) return;
                await repo.deleteCustomer(widget.existing!.id);
                if (!context.mounted) return;
                Navigator.pop(context);
                showSnack(context, 'Contact deleted');
              },
              icon: const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      bottomNavigationBar: FormActionBar(
        label: isEdit ? 'Save changes' : 'Add',
        onPressed: _save,
      ),
      body: Form(
        key: _formKey,
        child: FormPageContent(
          maxWidth: 760,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            children: [
              AppTextField(
                controller: _name,
                label: 'Name'.tr,
                icon: Icons.person_outline_rounded,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: _phone,
                label: 'Phone number'.tr,
                hint: '0912...'.tr,
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: _telegram,
                label: 'Telegram username (optional)'.tr,
                hint: '@username'.tr,
                icon: Icons.send_outlined,
              ),
              const SizedBox(height: 14),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AmountField(
                      controller: _opening,
                      label: 'Opening balance'.tr,
                      textInputAction: TextInputAction.next,
                      validator: (_) => null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment(value: true, label: Text('Debtor'.tr)),
                      ButtonSegment(value: false, label: Text('Creditor'.tr)),
                    ],
                    selected: {_openingIsDebt},
                    onSelectionChanged: (s) =>
                        setState(() => _openingIsDebt = s.first),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Enter any existing balance here (for example, an old customer who owes 500,000).'
                      .tr,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.55),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: _note,
                label: 'Note'.tr,
                maxLines: 3,
                icon: Icons.notes_rounded,
              ),
              const SizedBox(height: 14),
              AppTextField(
                controller: _identifiers,
                label: 'Bank identifiers (for automatic SMS matching)'.tr,
                hint: 'e.g. 1234, 6104********5678'.tr,
                icon: Icons.credit_card_rounded,
                maxLines: 2,
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Enter this customer’s last four card digits or full card number here, and incoming payments in bank SMS messages can be matched automatically.'
                      .tr,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.55),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (isEdit)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _archived,
                  onChanged: (v) => setState(() => _archived = v),
                  title: Text('Archived'.tr, style: TextStyle(fontSize: 13.5)),
                  subtitle: Text(
                    'Hidden from the main list'.tr,
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
