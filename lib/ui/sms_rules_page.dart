import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/localization.dart';
import '../core/money.dart';
import '../core/sms/bank_rules.dart';
import '../core/sms/sms_access.dart';
import '../core/sms/sms_models.dart';
import '../core/sms/sms_parser.dart';
import '../data/repository.dart';
import '../data/store.dart';
import 'theme.dart';
import 'widgets/widgets.dart';

Future<void> _syncArrivalRuleHints(AppRepository repo) {
  final rules = repo.activeSmsRules;
  return smsAccess.syncArrivalRules(
    senderHints: rules.expand((rule) => rule.senderHints).toList(),
    bodyHints: rules.expand((rule) => rule.bodyHints).toList(),
  );
}

/// Manage the rules that are allowed to identify bank SMS messages.
/// Both built-in bank rules and custom user rules can be searched, edited,
/// toggled on/off, or reset to factory defaults.
class SmsRulesPage extends StatefulWidget {
  const SmsRulesPage({super.key});

  @override
  State<SmsRulesPage> createState() => _SmsRulesPageState();
}

class _SmsRulesPageState extends State<SmsRulesPage> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _matchesQuery(BankRule rule) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (rule.bankName.toLowerCase().contains(q)) return true;
    if (rule.bankName.tr.toLowerCase().contains(q)) return true;
    if (rule.senderHints.any((h) => h.toLowerCase().contains(q))) return true;
    if (rule.bodyHints.any((h) => h.toLowerCase().contains(q))) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final builtinRules = repo.effectiveBuiltinRules;
    final customRules = [...repo.customSmsRules]
      ..sort((a, b) => a.bankName.compareTo(b.bankName));
    final allRules = [...builtinRules, ...customRules];
    final enabledCount = allRules
        .where((rule) => repo.isSmsRuleEnabled(rule.id))
        .length;

    final filteredBuiltin = builtinRules.where(_matchesQuery).toList();
    final filteredCustom = customRules.where(_matchesQuery).toList();

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: Text('SMS recognition rules'.tr)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditRule(context),
        icon: const Icon(Icons.add_rounded),
        label: Text('Add custom SMS rule'.tr),
      ),
      body: RepaintBoundary(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
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
                            'total': allRules.length,
                          }),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Inbox messages enter the review queue only when matched by an enabled rule. Pasted messages can be added manually. No transaction is recorded until you review it and explicitly choose Personal or VPN business.'
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
            const SizedBox(height: 10),
            TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      ),
                hintText: 'Search bank name or sender number…'.tr,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            SectionTitle(
              'Custom rules',
              icon: Icons.rule_rounded,
              action: 'Add'.tr,
              onAction: () => _openEditRule(context),
            ),
            if (filteredCustom.isEmpty)
              CardBox(
                child: Text(
                  _query.trim().isNotEmpty
                      ? 'No items found'.tr
                      : 'No custom rules yet. Add a sender ID or phrase to recognize a bank or payment service not listed above.'
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
              _ruleCard(context, repo, filteredCustom, allowDelete: true),
            SectionTitle(
              'Built-in banks',
              icon: Icons.account_balance_outlined,
            ),
            if (filteredBuiltin.isEmpty)
              CardBox(
                child: Text(
                  'No items found'.tr,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.68),
                  ),
                ),
              )
            else
              _ruleCard(
                context,
                repo,
                filteredBuiltin,
                allowDelete: false,
              ),
          ],
        ),
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
    final modified = !allowDelete && repo.isBuiltinSmsRuleModified(rule.id);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => _openEditRule(context, existingRule: rule),
      leading: Icon(
        allowDelete ? Icons.rule_rounded : Icons.account_balance_outlined,
        size: 20,
        color: enabled ? AppTheme.primary : null,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              rule.bankName.tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (modified) ...[
            const SizedBox(width: 6),
            const TagChip(
              'Customized',
              color: AppTheme.info,
              dense: true,
            ),
          ],
        ],
      ),
      subtitle: Text(
        _ruleDescription(rule),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 10.5, height: 1.35),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Edit'.tr,
            visualDensity: VisualDensity.compact,
            onPressed: () => _openEditRule(context, existingRule: rule),
            icon: const Icon(Icons.edit_outlined, size: 19),
          ),
          if (modified)
            IconButton(
              tooltip: 'Reset to default'.tr,
              visualDensity: VisualDensity.compact,
              onPressed: () => _resetBuiltinRule(context, repo, rule),
              icon: const Icon(Icons.restart_alt_rounded, size: 19),
            ),
          if (allowDelete)
            IconButton(
              tooltip: 'Delete custom rule'.tr,
              visualDensity: VisualDensity.compact,
              onPressed: () => _deleteRule(context, repo, rule),
              icon: const Icon(Icons.delete_outline_rounded, size: 19),
            ),
          Tooltip(
            message: (enabled ? 'Disable rule' : 'Enable rule').tr,
            child: Switch(
              value: enabled,
              onChanged: (value) async {
                await repo.setSmsRuleEnabled(rule.id, value);
                await _syncArrivalRuleHints(repo);
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
      final cleanPhrases = rule.bodyHints
          .map((h) => h.replaceAll('\n', ' ').trim())
          .where((h) => h.isNotEmpty)
          .toList();
      if (cleanPhrases.isNotEmpty) {
        details.add(
          'Message phrases: {value}'.trArgs({'value': cleanPhrases.join(', ')}),
        );
      }
    }
    details.add(
      rule.defaultUnit == AmountUnit.rial ? 'Rials'.tr : 'Tomans'.tr,
    );
    return details.join(' · ');
  }

  Future<void> _openEditRule(
    BuildContext context, {
    BankRule? existingRule,
  }) async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => SmsRuleEditPage(existingRule: existingRule),
      ),
    );
  }

  Future<void> _resetBuiltinRule(
    BuildContext context,
    AppRepository repo,
    BankRule rule,
  ) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Reset to default'.tr,
      message:
          'Reset "{bank}" recognition settings back to factory defaults?'
              .trArgs({'bank': rule.bankName.tr}),
      okLabel: 'Reset'.tr,
    );
    if (!confirmed) return;
    await repo.resetBuiltinSmsRule(rule.id);
    await _syncArrivalRuleHints(repo);
    if (context.mounted) showSnack(context, 'Rule reset to default.');
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
    await _syncArrivalRuleHints(repo);
    if (context.mounted) showSnack(context, 'Custom rule deleted.');
  }
}

/// Form for adding or editing a bank or payment-provider recognition rule
/// (supports both built-in banks and custom rules).
class SmsRuleEditPage extends StatefulWidget {
  const SmsRuleEditPage({
    super.key,
    this.initialMessage,
    this.existingRule,
  });

  final SmsMessage? initialMessage;
  final BankRule? existingRule;

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

  bool get _isEdit => widget.existingRule != null;

  BankRule? get _builtinDefault {
    final existing = widget.existingRule;
    if (existing == null) return null;
    for (final b in builtinBankRules) {
      if (b.id == existing.id) return b;
    }
    return null;
  }

  List<String> get _senderHints => _senderController.text
      .split(RegExp(r'[,،;\n]+'))
      .map((hint) => hint.trim())
      .where((hint) => hint.isNotEmpty)
      .toList();

  List<String> get _bodyHints => _bodyHintController.text
      .split(RegExp(r'[,،;\n]+'))
      .map((hint) => hint.trim())
      .where((hint) => hint.isNotEmpty)
      .toList();

  String _resolvedBankName() {
    final entered = _nameController.text.trim();
    final builtin = _builtinDefault;
    if (builtin != null &&
        (entered == builtin.bankName.tr || entered == builtin.bankName)) {
      return builtin.bankName;
    }
    return entered;
  }

  BankRule _buildRule(String id) => BankRule(
    id: id,
    bankName: _resolvedBankName(),
    senderHints: _senderHints,
    bodyHints: _bodyHints,
    defaultUnit: _unit,
    custom: _builtinDefault == null,
  );

  @override
  void initState() {
    super.initState();
    final existing = widget.existingRule;
    final message = widget.initialMessage;
    if (existing != null) {
      _nameController.text = existing.bankName.tr;
      _senderController.text = existing.senderHints.join(', ');
      _bodyHintController.text = existing.bodyHints
          .map((h) => h.replaceAll('\n', ' ').trim())
          .where((h) => h.isNotEmpty)
          .join(', ');
      _unit = existing.defaultUnit;
    } else if (message != null) {
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
    final repo = context.watch<AppRepository>();
    final builtin = _builtinDefault;
    final canReset =
        builtin != null && repo.isBuiltinSmsRuleModified(builtin.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          (_isEdit ? 'Edit SMS recognition rule' : 'Add custom SMS rule').tr,
        ),
        actions: [
          if (canReset)
            IconButton(
              tooltip: 'Reset to default'.tr,
              icon: const Icon(Icons.restart_alt_rounded),
              onPressed: () async {
                final ok = await confirmDialog(
                  context,
                  title: 'Reset to default'.tr,
                  message:
                      'Reset "{bank}" recognition settings back to factory defaults?'
                          .trArgs({'bank': builtin.bankName.tr}),
                  okLabel: 'Reset'.tr,
                );
                if (!ok) return;
                await repo.resetBuiltinSmsRule(builtin.id);
                await _syncArrivalRuleHints(repo);
                if (!context.mounted) return;
                showSnack(context, 'Rule reset to default.');
                Navigator.of(context).pop(true);
              },
            ),
        ],
      ),
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
              validator: (_) => _senderHints.isEmpty && _bodyHints.isEmpty
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
            'bank': (preview.bankName ?? '').tr,
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
            child: Text(
              message,
              style: const TextStyle(fontSize: 12, height: 1.5),
            ),
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
    final previewId = widget.existingRule?.id ?? 'rule-preview';
    final message = SmsMessage(
      id: 'rule-preview',
      address: hints.isEmpty ? '' : hints.first,
      body: sample,
      date: DateTime.now(),
    );
    final parsed = SmsParser.parse(
      message,
      extraRules: [_buildRule(previewId)],
    );
    setState(() => _preview = parsed);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repo = context.read<AppRepository>();
    setState(() => _saving = true);
    try {
      final id = widget.existingRule?.id ?? LocalStore.newId();
      await repo.addSmsRule(_buildRule(id));
      await _syncArrivalRuleHints(repo);
      if (!mounted) return;
      showSnack(
        context,
        _isEdit ? 'Recognition rule updated.' : 'Custom rule added.',
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        showSnack(context, 'Could not save the custom rule.', error: true);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
