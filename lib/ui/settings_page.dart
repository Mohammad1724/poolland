import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/backup.dart';
import '../core/format_utils.dart';
import '../core/jalali_utils.dart';
import '../core/money.dart';
import '../core/notifications/notify.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'forms/plan_edit_page.dart';
import 'sms_page.dart';
import 'widgets/widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final s = repo.settings;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          // ---------- Business ----------
          const SectionTitle('Business', icon: Icons.storefront_outlined),
          CardBox(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.badge_outlined, size: 20),
                  title: const Text('Business name', style: TextStyle(fontSize: 13.5)),
                  subtitle: Text(s.businessName, style: const TextStyle(fontSize: 12)),
                  onTap: () => _editText(
                    context,
                    title: 'Business name',
                    initial: s.businessName,
                    hint: 'e.g. Alex VPN',
                    onSave: (v) => repo.updateSettings(s.copyWith(businessName: v)),
                  ),
                ),
                Divider(color: Theme.of(context).dividerColor),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_balance_wallet_outlined, size: 20),
                  title: const Text('Opening cash balance', style: TextStyle(fontSize: 13.5)),
                  subtitle: Text(
                    '${Money.text(s.openingCash)} — cash or bank balance you already had',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  onTap: () => _editAmount(context,
                      title: 'Opening cash balance',
                      initial: s.openingCash,
                      onSave: (v) => repo.updateSettings(s.copyWith(openingCash: v))),
                ),
              ],
            ),
          ),

          // ---------- Basic data ----------
          const SectionTitle('Basic data', icon: Icons.tune_rounded),
          CardBox(
            child: Column(
              children: [
                _navTile(context,
                    icon: Icons.local_offer_outlined,
                    title: 'Plans',
                    subtitle: '${repo.plans.length} plans',
                    page: const PlansPage()),
                Divider(color: Theme.of(context).dividerColor),
                _navTile(context,
                    icon: Icons.category_outlined,
                    title: 'Income and expense categories',
                    subtitle: '${repo.categories.length} categories '
                        '(business and personal)',
                    page: const CategoriesPage()),
                Divider(color: Theme.of(context).dividerColor),
                _navTile(context,
                    icon: Icons.currency_exchange_rounded,
                    title: 'Currencies and exchange rates',
                    subtitle: s.currencies
                        .map((c) => '${c.code} ${Fmt.number(c.rateToBase, persian: false)}')
                        .join(' • '),
                    page: const RatesPage()),
              ],
            ),
          ),

          // ---------- Display ----------
          const SectionTitle('Display', icon: Icons.palette_outlined),
          CardBox(
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: s.persianDigits,
                  onChanged: (v) => repo.updateSettings(s.copyWith(persianDigits: v)),
                  title: const Text('Use Persian digits', style: TextStyle(fontSize: 13.5)),
                ),
                Divider(color: Theme.of(context).dividerColor),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.notifications_active_outlined, size: 20),
                  title: const Text('Expiry reminders', style: TextStyle(fontSize: 13.5)),
                  subtitle: Text('${s.reminderDays} days before expiry',
                      style: const TextStyle(fontSize: 11.5)),
                  onTap: () => _editInt(
                    context,
                    title: 'How many days before expiry should we remind you?',
                    initial: s.reminderDays,
                    onSave: (v) => repo.updateSettings(s.copyWith(reminderDays: v)),
                  ),
                ),
                Divider(color: Theme.of(context).dividerColor),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Appearance', style: TextStyle(fontSize: 13.5)),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'system', label: Text('System')),
                          ButtonSegment(value: 'light', label: Text('Light')),
                          ButtonSegment(value: 'dark', label: Text('Dark')),
                        ],
                        selected: {s.themeMode},
                        onSelectionChanged: (v) =>
                            repo.updateSettings(s.copyWith(themeMode: v.first)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ---------- Backups ----------
          const SectionTitle('Backups', icon: Icons.cloud_sync_outlined),
          CardBox(
            child: Column(
              children: [
                _actionTile(context,
                    icon: Icons.share_rounded,
                    title: 'Share backup',
                    subtitle: 'Export JSON to a messaging app or save it on your phone',
                    onTap: () => _backup(context, repo, share: true)),
                Divider(color: Theme.of(context).dividerColor),
                _actionTile(context,
                    icon: Icons.download_rounded,
                    title: 'Save backup to device',
                    subtitle: 'Choose where to save the JSON file',
                    onTap: () => _backup(context, repo, share: false)),
                Divider(color: Theme.of(context).dividerColor),
                _actionTile(context,
                    icon: Icons.restore_rounded,
                    title: 'Restore from backup',
                    subtitle: 'All current data will be replaced with the selected file',
                    onTap: () => _restore(context, repo)),
              ],
            ),
          ),

          // ---------- Data ----------
          const SectionTitle('Data', icon: Icons.storage_rounded),
          CardBox(
            child: Column(
              children: [
                _actionTile(context,
                    icon: Icons.auto_awesome_outlined,
                    title: 'Load sample data',
                    subtitle: 'For a quick app demo (current data will be erased)',
                    onTap: () async {
                      final ok = await confirmDialog(context,
                          title: 'Sample data',
                          message:
                              'Current data will be erased and replaced with sample data. Continue?',
                          okLabel: 'Continue');
                      if (!ok) return;
                      await repo.loadDemoData();
                      if (context.mounted) showSnack(context, 'Sample data loaded');
                    }),
                Divider(color: Theme.of(context).dividerColor),
                _actionTile(context,
                    icon: Icons.delete_forever_outlined,
                    title: 'Erase all data',
                    subtitle: 'Reset the app (cannot be undone)',
                    danger: true,
                    onTap: () async {
                      final ok = await confirmDialog(context,
                          title: 'Erase all data',
                          message:
                              'All customers, subscriptions, and transactions will be deleted. Back up your data first.',
                          okLabel: 'Clear',
                          danger: true);
                      if (!ok) return;
                      await repo.wipeAll();
                      if (context.mounted) showSnack(context, 'All data erased');
                    }),
              ],
            ),
          ),

          // ---------- Bank SMS ----------
          if (repo.smsSupported) ...[
            const SectionTitle('Bank SMS', icon: Icons.sms_rounded),
            CardBox(
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: s.smsEnabled,
                    title: const Text('Read bank SMS',
                        style: TextStyle(fontSize: 13.5)),
                    subtitle: const Text(
                      'Deposits and withdrawals are detected automatically '
                      'and added to the review queue',
                      style: TextStyle(fontSize: 11.5),
                    ),
                    onChanged: (v) async {
                      if (v && !repo.smsPermissionGranted) {
                        final ok = await repo.requestSmsPermission();
                        if (!ok) return;
                      }
                      await repo.updateSettings(s.copyWith(smsEnabled: v));
                    },
                  ),
                  Divider(color: Theme.of(context).dividerColor),
                  _navTile(
                    context,
                    icon: Icons.fact_check_outlined,
                    title: 'Review SMS',
                    subtitle: repo.smsPendingCount > 0
                        ? '${repo.smsPendingCount} '
                            'transactions awaiting review'
                        : 'Nothing awaiting review',
                    page: const SmsPage(),
                  ),
                  Divider(color: Theme.of(context).dividerColor),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.date_range_outlined, size: 20),
                    title: const Text('SMS lookback period',
                        style: TextStyle(fontSize: 13.5)),
                    subtitle: Text(
                      'Past ${s.smsSyncDays} days',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    onTap: () => _editInt(
                      context,
                      title: 'How many past days should be checked?',
                      initial: s.smsSyncDays,
                      onSave: (v) => repo
                          .updateSettings(s.copyWith(smsSyncDays: v.clamp(1, 365))),
                    ),
                  ),
                  Divider(color: Theme.of(context).dividerColor),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: s.smsAutoApprove,
                    title: const Text('Automatically approve high-confidence matches',
                        style: TextStyle(fontSize: 13.5)),
                    subtitle: const Text(
                      'Transactions will be recorded without your approval (off by default)',
                      style: TextStyle(fontSize: 11.5),
                    ),
                    onChanged: (v) =>
                        repo.updateSettings(s.copyWith(smsAutoApprove: v)),
                  ),
                ],
              ),
            ),
          ],

          // ---------- Daily reminder ----------
          if (reminder.supported) ...[
            const SectionTitle('Daily reminder',
                icon: Icons.notifications_active_outlined),
            CardBox(
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: s.dailyReminder,
                    title: const Text('Expense reminder',
                        style: TextStyle(fontSize: 13.5)),
                    subtitle: const Text(
                      'Reminds you every day at the selected time '
                      'to record your expenses and income',
                      style: TextStyle(fontSize: 11.5),
                    ),
                    onChanged: (v) async {
                      if (v) {
                        final ok = await reminder.requestPermission();
                        if (!ok) {
                          if (context.mounted) {
                            showSnack(context,
                                'Notification permission denied. Enable it in Android settings.',
                                error: true);
                          }
                          return;
                        }
                      }
                      await repo
                          .updateSettings(s.copyWith(dailyReminder: v));
                    },
                  ),
                  if (s.dailyReminder) ...[
                    Divider(color: Theme.of(context).dividerColor),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule_rounded, size: 20),
                      title: const Text('Reminder time',
                          style: TextStyle(fontSize: 13.5)),
                      subtitle: Text(
                        '${s.reminderHour.toString().padLeft(2, '0')}:${s.reminderMinute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onTap: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(
                              hour: s.reminderHour, minute: s.reminderMinute),
                        );
                        if (t == null || !context.mounted) return;
                        await repo.updateSettings(s.copyWith(
                            reminderHour: t.hour, reminderMinute: t.minute));
                      },
                    ),
                    Divider(color: Theme.of(context).dividerColor),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.send_rounded, size: 20),
                      title: const Text('Send test notification',
                          style: TextStyle(fontSize: 13.5)),
                      subtitle: const Text('Check that notifications are displayed',
                          style: TextStyle(fontSize: 11.5)),
                      onTap: () async {
                        try {
                          await reminder.showNow(
                              title: 'Poolland reminder test',
                              body: 'If you can see this message, notifications are working ✓');
                        } catch (_) {
                          if (context.mounted) {
                            showSnack(context, 'Could not send notification',
                                error: true);
                          }
                        }
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],

          // ---------- About ----------
          const SectionTitle('About', icon: Icons.info_outline_rounded),
          CardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Poolland Ledger',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  'Version 1.2.0 • Open-source software (MIT)\nA simple offline ledger for VPN sellers.\nAll data stays on this device.\n'
                      'The Personal section is for your own finances and is not included in business profit '
                      'or loss.',
                  style: TextStyle(
                      fontSize: 11.5, height: 1.9, color: onSurface.withValues(alpha: 0.65)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _navTile(BuildContext context,
          {required IconData icon,
          required String title,
          required String subtitle,
          required Widget page}) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, size: 20),
        title: Text(title, style: const TextStyle(fontSize: 13.5)),
        subtitle: Text(subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11.5)),
        trailing: const Icon(Icons.chevron_right_rounded, size: 18),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
      );

  Widget _actionTile(BuildContext context,
          {required IconData icon,
          required String title,
          required String subtitle,
          required VoidCallback onTap,
          bool danger = false}) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        onTap: onTap,
        leading: Icon(icon, size: 20, color: danger ? const Color(0xFFE11D48) : null),
        title: Text(title,
            style: TextStyle(
                fontSize: 13.5, color: danger ? const Color(0xFFE11D48) : null)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11.5)),
      );

  Future<void> _editText(BuildContext context,
      {required String title,
      required String initial,
      required Future<void> Function(String) onSave,
      String? hint}) async {
    final ctrl = TextEditingController(text: initial);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (res != null && res.isNotEmpty) await onSave(res);
  }

  Future<void> _editAmount(BuildContext context,
      {required String title,
      required double initial,
      required Future<void> Function(double) onSave}) async {
    final ctrl = TextEditingController(text: groupedNumber(initial));
    final res = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: 'Toman'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, parseAmount(ctrl.text)),
              child: const Text('Save')),
        ],
      ),
    );
    if (res != null) await onSave(res);
  }

  Future<void> _editInt(BuildContext context,
      {required String title,
      required int initial,
      required Future<void> Function(int) onSave}) async {
    final ctrl = TextEditingController(text: '$initial');
    final res = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: 'day'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, parseAmount(ctrl.text).toInt().clamp(0, 60)),
              child: const Text('Save')),
        ],
      ),
    );
    if (res != null) await onSave(res);
  }

  Future<void> _backup(BuildContext context, AppRepository repo,
      {required bool share}) async {
    final content = const JsonEncoder.withIndent('  ').convert(repo.exportData());
    final name = 'poolland-backup-${J.d(DateTime.now(), persian: false).replaceAll('/', '-')}.json';
    final ok = share
        ? await Backup.shareFile(fileName: name, content: content)
        : await Backup.saveToDevice(fileName: name, content: content);
    if (context.mounted) {
      showSnack(context,
          ok ? 'Backup file created' : 'Backup save cancelled',
          error: !ok);
    }
  }

  Future<void> _restore(BuildContext context, AppRepository repo) async {
    try {
      final data = await Backup.pickJsonContent();
      if (data == null) return;
      if (!context.mounted) return;
      final ok = await confirmDialog(context,
          title: 'Restore backup',
          message:
              'All current data will be replaced with the contents of this file. Continue?',
          okLabel: 'Restore');
      if (!ok) return;
      await repo.importData(data);
      if (context.mounted) showSnack(context, 'Backup restored');
    } catch (e) {
      if (context.mounted) showSnack(context, 'Invalid file: $e', error: true);
    }
  }
}

/// ---------- Currencies and exchange rates page ----------
class RatesPage extends StatelessWidget {
  const RatesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final s = repo.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Currencies and exchange rates')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addCurrency(context, repo),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add currency'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
        children: [
          CardBox(
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'The base currency is Toman. Enter each currency’s rate in Toman to convert reports automatically.',
                    style: TextStyle(
                        fontSize: 11.5,
                        height: 1.8,
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.7)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          for (final c in s.currencies) ...[
            CardBox(
              onTap: c.code == s.baseCurrency
                  ? null
                  : () => _editRate(context, repo, c),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(c.symbol,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${c.name} (${c.code})',
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 3),
                        Text(
                          c.code == s.baseCurrency
                              ? 'Base currency'
                              : '1 ${c.name} = ${Money.text(c.rateToBase)}',
                          style: TextStyle(
                              fontSize: 11.5,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                  ),
                  if (c.code != s.baseCurrency)
                    IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      onPressed: () async {
                        final ok = await confirmDialog(context,
                            title: 'Remove currency',
                            message: 'Remove ${c.name}? Existing transactions will not be deleted.',
                            okLabel: 'Delete',
                            danger: true);
                        if (ok) await repo.removeCurrency(c.code);
                      },
                    )
                  else
                    const Icon(Icons.lock_outline_rounded, size: 18),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Future<void> _editRate(BuildContext context, AppRepository repo, CurrencyDef c) async {
    final ctrl = TextEditingController(text: groupedNumber(c.rateToBase));
    final res = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${c.name} exchange rate in Toman'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: 'Toman'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, parseAmount(ctrl.text)),
              child: const Text('Save')),
        ],
      ),
    );
    if (res != null && res > 0) {
      await repo.upsertCurrency(c.copyWith(rateToBase: res));
    }
  }

  Future<void> _addCurrency(BuildContext context, AppRepository repo) async {
    final code = TextEditingController();
    final name = TextEditingController();
    final symbol = TextEditingController();
    final rate = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add currency'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: code,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'Code (e.g. AED)')),
              const SizedBox(height: 10),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Name')),
              const SizedBox(height: 10),
              TextField(
                  controller: symbol, decoration: const InputDecoration(labelText: 'Symbol')),
              const SizedBox(height: 10),
              TextField(
                  controller: rate,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Rate in Toman', suffixText: 'Toman')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Add')),
        ],
      ),
    );
    if (ok != true) return;
    if (code.text.trim().isEmpty || name.text.trim().isEmpty) return;
    await repo.upsertCurrency(CurrencyDef(
      code: code.text.trim().toUpperCase(),
      name: name.text.trim(),
      symbol: symbol.text.trim().isEmpty ? name.text.trim() : symbol.text.trim(),
      rateToBase: parseAmount(rate.text),
      decimals: 2,
    ));
  }
}

/// ---------- Categories page ----------
class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  TxnScope _scope = TxnScope.business;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Categories'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Income'), Tab(text: 'Expense')],
          ),
        ),
        body: Column(
          children: [
            const SizedBox(height: 10),
            SegmentedButton<TxnScope>(
              segments: [
                for (final sc in TxnScope.values)
                  ButtonSegment(value: sc, label: Text(sc.label)),
              ],
              selected: {_scope},
              onSelectionChanged: (s) => setState(() => _scope = s.first),
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _list(context, TxnKind.income),
                  _list(context, TxnKind.expense),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context, TxnKind kind) {
    final repo = context.watch<AppRepository>();
    final list = repo.categoriesOf(kind, scope: _scope);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      children: [
        for (final c in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CardBox(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Row(
                children: [
                  Icon(
                      kind == TxnKind.income
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                      size: 18,
                      color: kind == TxnKind.income
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFE11D48)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(c.name, style: const TextStyle(fontSize: 13.5))),
                  IconButton(
                    tooltip: 'Edit',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () async {
                      final ctrl = TextEditingController(text: c.name);
                      final res = await showDialog<String>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Edit category'),
                          content: TextField(controller: ctrl, autofocus: true),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('Cancel')),
                            FilledButton(
                                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                                child: const Text('Save')),
                          ],
                        ),
                      );
                      if (res != null && res.isNotEmpty) {
                        await repo.renameCategory(c, res);
                      }
                    },
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    onPressed: () async {
                      final ok = await confirmDialog(context,
                          title: 'Delete category',
                          message:
                              'Delete category “${c.name}”? Its transactions will become uncategorized.',
                          okLabel: 'Delete',
                          danger: true);
                      if (ok) await repo.deleteCategory(c.id);
                    },
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: () async {
            final ctrl = TextEditingController();
            final res = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(kind == TxnKind.income ? 'New income category' : 'New expense category'),
                content: TextField(
                    controller: ctrl,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'e.g. Server purchase')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                      child: const Text('Add')),
                ],
              ),
            );
            if (res != null && res.isNotEmpty) {
              await repo.addCategory(res, kind, scope: _scope);
            }
          },
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Add category'),
        ),
      ],
    );
  }
}
