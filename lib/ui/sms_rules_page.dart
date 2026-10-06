import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/localization.dart';
import '../core/money.dart';
import '../core/sms/bank_rules.dart';
import '../core/sms/sms_models.dart';
import '../core/sms/sms_parser.dart';
import '../data/repository.dart';
import '../data/store.dart';
import 'widgets/widgets.dart';

/// Manage the rules that are allowed to identify bank SMS messages.
/// A matched message is still only a suggestion; approval remains manual.
class SmsRulesPage extends StatelessWidget {
  const SmsRulesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final customRules = [...repo.smsRules]
      ..sort((a, b) => a.bankName.compareTo(b.bankName));
    final rules = [...builtinBankRules, ...customRules];
    final enabledCount = rules
        .where((rule) => repo.isSmsRuleEnabled(rule.id))
        .length;

    return Scaffold(
      appBar: AppBar(title: Text('SMS recognition rules'.tr)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          CardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.fact_check_outlined, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Enabled {enabled} of {total} rules'.trArgs({
                          'enabled': enabledCount,
                          'total': rules.length,
                        }),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Only messages matched by an enabled rule can enter the review queue. No transaction is recorded until you review it and explicitly choose Personal or VPN business.'
                      .tr,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.68),
                  ),
                ),
              ],
            ),
          ),
          SectionTitle(
            'Built-in banks',
            icon: Icons.account_balance_outlined,
          ),
          _ruleCard(
            context,
            repo,
            builtinBankRules,
            allowDelete: false,
          ),
          SectionTitle(
            'Custom rules',
            icon: Icons.rule_rounded,
            action: 'Add',
            onAction: () => _addRule(context),
          ),
          if (customRules.isEmpty)
            CardBox(
              child: Text(
                'No custom rules yet. Add a sender ID or phrase to recognize a bank or payment service not listed above.'
                    .tr,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.68),
                ),
              ),
            )
          else
            _ruleCard(context, repo, customRules, allowDelete: true),
        ],
      ),
    );
  }

  Widget _ruleCard(
    BuildContext context,
    AppRepository repo,
    List<BankRule> rules, {
    required bool allowDelete,
  }) {
    final dividerColor = Theme.of(context).dividerColor;
    return CardBox(
      child: Column(
        children: [
          for (var i = 0; i < rules.length; i++) ...[
            if (i > 0) Divider(color: dividerColor, height: 1),
            _ruleTile(context, repo, rules[i], allowDelete: allowDelete),
          ],
        ],
      ),
    );
  }

  Widget _ruleTile(
    BuildContext context,
    AppRepository repo,
    BankRule rule, {
    required bool allowDelete,
  }) {
    final enabled = repo.isSmsRuleEnabled(rule.id);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        allowDelete ? Icons.rule_rounded : Icons.account_balance_outlined,
        size: 20,
      ),
      title: Text(rule.bankName.tr, style: const TextStyle(fontSize: 13.5)),
      subtitle: Text(
        _ruleDescription(rule),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10.5, height: 1.35),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (allowDelete)
            IconButton(
              tooltip: 'Delete custom rule'.tr,
              onPressed: () => _deleteRule(context, repo, rule),
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          Tooltip(
            message: (enabled ? 'Disable rule' : 'Enable rule').tr,
            child: Switch(
              value: enabled,
              onChanged: (value) async {
                await repo.setSmsRuleEnabled(rule.id, value);
                if (context.mounted) {
                  showSnack(
                    context,
                    value
                        ? 'Recognition rule enabled.'
                        : 'Recognition rule disabled. Messages that no longer match an enabled rule are removed from the review queue.',
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  String _ruleDescription(BankRule rule) {
    final details = <String>[];
    if (rule.senderHints.isNotEmpty) {
      details.add(
        'Sender IDs: {value}'.trArgs({'value': rule.senderHints.join(', ')}),
      );
    }
    if (rule.bodyHints.isNotEmpty) {
      details.add(
        'Message phrases: {value}'.trArgs({'value': rule.bodyHints.join(', ')}),
      );
    }
    return details.join(' · ');
  }

  Future<void> _addRule(BuildContext context) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const SmsRuleEditPage()),
    );
  }

  Future<void> _deleteRule(
    BuildContext context,
    AppRepository repo,
    BankRule rule,
  ) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Delete custom rule?'.tr,
      message:
          'This rule will no longer identify SMS messages. Existing transactions will not be changed.'
              .tr,
      okLabel: 'Delete'.tr,
      danger: true,
    );
    if (!confirmed) return;
    await repo.deleteSmsRule(rule.id);
    if (context.mounted) showSnack(context, 'Custom rule deleted.');
  }
}

/// Form for adding one custom bank or payment-provider sender rule.
class SmsRuleEditPage extends StatefulWidget {
  const SmsRuleEditPage({super.key, this.initialMessage});

  final SmsMessage? initialMessage;

  @override
  State<SmsRuleEditPage> createState() => _SmsRuleEditPageState();
}

class _SmsRuleEditPageState extends State<SmsRuleEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _senderController = TextEditingController();
  final _bodyHintController = TextEditingController();
  final _sampleController = TextEditingController();

  AmountUnit _unit = AmountUnit.rial;
  ParsedSms? _preview;
  bool _saving = false;

  List<String> get _senderHints => _senderController.text
      .split(RegExp(r'[,;\n]+'))
      .map((hint) => hint.trim())
      .where((hint) => hint.isNotEmpty)
      .toList();

  String get _bodyHint => _bodyHintController.text.trim();

  BankRule _buildRule(String id) => BankRule(
    id: id,
    bankName: _nameController.text.trim(),
    senderHints: _senderHints,
    bodyHints: _bodyHint.isEmpty ? const [] : [_bodyHint],
    defaultUnit: _unit,
    custom: true,
  );

  @override
  void initState() {
    super.initState();
    final message = widget.initialMessage;
    if (message != null) {
      _nameController.text = message.address.trim();
      _senderController.text = message.address.trim();
      _sampleController.text = message.body;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _senderController.dispose();
    _bodyHintController.dispose();
    _sampleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Add custom SMS rule'.tr)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            CardBox(
              child: Text(
                (widget.initialMessage == null
                        ? 'Use a sender ID or a phrase that reliably appears in the message. The sample is only for testing; it is not saved.'
                        : 'The sender and SMS sample are prefilled. Confirm the bank or service name and detection hints before saving.')
                    .tr,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.68),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: 'Bank or service name'.tr,
                border: const OutlineInputBorder(),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a bank or service name.'.tr
                  : null,
              onChanged: (_) => _clearPreview(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _senderController,
              decoration: InputDecoration(
                labelText: 'Sender IDs or numbers'.tr,
                hintText: 'Comma-separated; e.g. MYBANK, 30001234'.tr,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _clearPreview(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _bodyHintController,
              decoration: InputDecoration(
                labelText: 'Optional phrase in SMS body'.tr,
                hintText: 'e.g. Your wallet balance'.tr,
                border: const OutlineInputBorder(),
              ),
              validator: (_) => _senderHints.isEmpty && _bodyHint.isEmpty
                  ? 'Add a sender ID or body phrase to identify messages.'.tr
                  : null,
              onChanged: (_) => _clearPreview(),
            ),
            const SizedBox(height: 18),
            Text(
              'Assumed amount unit (if the message omits it)'.tr,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            SegmentedButton<AmountUnit>(
              segments: [
                ButtonSegment(
                  value: AmountUnit.rial,
                  label: Text('Rials'.tr),
                ),
                ButtonSegment(
                  value: AmountUnit.toman,
                  label: Text('Tomans'.tr),
                ),
              ],
              selected: {_unit},
              onSelectionChanged: (selection) {
                setState(() {
                  _unit = selection.first;
                  _preview = null;
                });
              },
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _sampleController,
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: 'Sample SMS text (optional)'.tr,
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => _clearPreview(),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _testSample,
              icon: const Icon(Icons.science_outlined),
              label: Text('Test sample'.tr),
            ),
            if (_preview != null) ...[
              const SizedBox(height: 10),
              _previewCard(context, _preview!),
            ],
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving…'.tr : 'Save rule'.tr),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewCard(BuildContext context, ParsedSms preview) {
    final colorScheme = Theme.of(context).colorScheme;
    final recognized = preview.isTransaction;
    final message = recognized
        ? 'Matched {bank}: {direction} {amount}.'.trArgs({
            'bank': preview.bankName ?? '',
            'direction': preview.direction.label,
            'amount': Money.text(preview.amount, currency: preview.currency),
          })
        : 'No complete transaction was detected. Check the sender, phrase, amount, and direction.'
              .tr;
    return CardBox(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            recognized ? Icons.check_circle_outline : Icons.info_outline,
            color: recognized ? colorScheme.primary : colorScheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: const TextStyle(fontSize: 12, height: 1.5)),
          ),
        ],
      ),
    );
  }

  void _clearPreview() {
    if (_preview != null) setState(() => _preview = null);
  }

  void _testSample() {
    final sample = _sampleController.text.trim();
    if (sample.isEmpty) {
      showSnack(context, 'Enter sample SMS text first.', error: true);
      return;
    }
    final hints = _senderHints;
    final message = SmsMessage(
      id: 'rule-preview',
      address: hints.isEmpty ? '' : hints.first,
      body: sample,
      date: DateTime.now(),
    );
    final parsed = SmsParser.parse(
      message,
      extraRules: [_buildRule('rule-preview')],
    );
    setState(() => _preview = parsed);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repo = context.read<AppRepository>();
    setState(() => _saving = true);
    try {
      await repo.addSmsRule(_buildRule(LocalStore.newId()));
      if (!mounted) return;
      showSnack(context, 'Custom rule added.');
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) showSnack(context, 'Could not save the custom rule.', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
