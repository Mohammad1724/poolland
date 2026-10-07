import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_info.dart';
import '../core/backup.dart';
import '../core/biometrics.dart';
import '../core/format_utils.dart';
import '../core/jalali_utils.dart';
import '../core/money.dart';
import '../core/notifications/notify.dart';
import '../core/notifications/notification_sound_picker.dart';
import '../core/platform_info.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'forms/plan_edit_page.dart';
import 'lock/pin_setup_page.dart';
import 'sms_page.dart';
import 'sms_rules_page.dart';
import 'widgets/widgets.dart';

import '../core/localization.dart';

enum _NotificationSoundAction { systemDefault, phoneSound, audioFile }

Future<void> _selectNotificationSound(
  BuildContext context,
  AppRepository repo,
  AppSettings settings,
  _NotificationSoundAction action,
) async {
  try {
    if (action == _NotificationSoundAction.systemDefault) {
      await repo.updateSettings(
        settings.copyWith(clearNotificationSound: true),
      );
    } else {
      final choice = action == _NotificationSoundAction.phoneSound
          ? await NotificationSoundPicker.pickSystemSound(
              currentUri: settings.notificationSoundUri,
            )
          : await NotificationSoundPicker.pickAudioFile();
      if (choice == null) return;
      if (choice.uri == null || choice.uri!.isEmpty) {
        await repo.updateSettings(
          settings.copyWith(clearNotificationSound: true),
        );
      } else {
        await repo.updateSettings(
          settings.copyWith(
            notificationSoundUri: choice.uri,
            notificationSoundName: choice.name ?? 'Notification sound',
          ),
        );
      }
    }
    if (context.mounted) showSnack(context, 'Notification sound updated.');
  } catch (error) {
    if (!context.mounted) return;
    final message = error is FormatException
        ? error.message.tr
        : 'Could not set notification sound'.tr;
    showSnack(context, message, error: true);
  }
}

Future<void> _testNotificationSound(
  BuildContext context,
  AppSettings settings,
) async {
  try {
    final permitted = await reminder.requestPermission();
    if (!permitted) {
      if (context.mounted) {
        showSnack(
          context,
          'Notification permission denied. Enable it in Android settings.',
          error: true,
        );
      }
      return;
    }
    await reminder.showNow(
      title: 'Poolland reminder test'.tr,
      body: 'If you can see this message, notifications are working ✓',
      soundUri: settings.notificationSoundUri,
      soundName: settings.notificationSoundName,
    );
  } catch (_) {
    if (context.mounted) {
      showSnack(context, 'Could not send notification', error: true);
    }
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final s = repo.settings;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final aboutText = [
      'Version {version} • Open-source software (MIT)'.trArgs({
        'version': appVersionLabel,
      }),
      'A simple offline ledger for VPN sellers.'.tr,
      'All data stays on this device.'.tr,
      'The Personal section is for your own finances and is not included in business profit or loss.'
          .tr,
    ].join('\n');

    return Scaffold(
      appBar: AppBar(title: Text('Settings'.tr)),
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
                  title: Text(
                    'Business name'.tr,
                    style: TextStyle(fontSize: 13.5),
                  ),
                  subtitle: Text(
                    s.businessName,
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () => _editText(
                    context,
                    title: 'Business name'.tr,
                    initial: s.businessName,
                    hint: 'e.g. Alex VPN'.tr,
                    onSave: (v) =>
                        repo.updateSettings(s.copyWith(businessName: v)),
                  ),
                ),
                Divider(color: Theme.of(context).dividerColor),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 20,
                  ),
                  title: Text(
                    'Opening cash balance'.tr,
                    style: TextStyle(fontSize: 13.5),
                  ),
                  subtitle: Text(
                    '{amount} — cash or bank balance you already had'.trArgs({
                      'amount': Money.text(s.openingCash),
                    }),
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  onTap: () => _editAmount(
                    context,
                    title: 'Opening cash balance'.tr,
                    initial: s.openingCash,
                    onSave: (v) =>
                        repo.updateSettings(s.copyWith(openingCash: v)),
                  ),
                ),
              ],
            ),
          ),

          // ---------- Basic data ----------
          const SectionTitle('Basic data', icon: Icons.tune_rounded),
          CardBox(
            child: Column(
              children: [
                _navTile(
                  context,
                  icon: Icons.local_offer_outlined,
                  title: 'Plans'.tr,
                  subtitle: '{count} plans'.trArgs({
                    'count': repo.plans.length,
                  }),
                  page: const PlansPage(),
                ),
                Divider(color: Theme.of(context).dividerColor),
                _navTile(
                  context,
                  icon: Icons.category_outlined,
                  title: 'Income and expense categories'.tr,
                  subtitle: '{count} categories (business and personal)'.trArgs(
                    {'count': repo.categories.length},
                  ),
                  page: const CategoriesPage(),
                ),
                Divider(color: Theme.of(context).dividerColor),
                _navTile(
                  context,
                  icon: Icons.currency_exchange_rounded,
                  title: 'Currencies and exchange rates'.tr,
                  subtitle: s.currencies
                      .map(
                        (c) =>
                            '${c.code} ${Fmt.number(c.rateToBase, persian: false)}',
                      )
                      .join(' • '),
                  page: const RatesPage(),
                ),
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
                  onChanged: (v) =>
                      repo.updateSettings(s.copyWith(persianDigits: v)),
                  title: Text(
                    'Use Persian digits'.tr,
                    style: TextStyle(fontSize: 13.5),
                  ),
                ),
                Divider(color: Theme.of(context).dividerColor),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.notifications_active_outlined,
                    size: 20,
                  ),
                  title: Text(
                    'Expiry reminders'.tr,
                    style: TextStyle(fontSize: 13.5),
                  ),
                  subtitle: Text(
                    '{days} days before expiry'.trArgs({
                      'days': s.reminderDays,
                    }),
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  onTap: () => _editInt(
                    context,
                    title:
                        'How many days before expiry should we remind you?'.tr,
                    initial: s.reminderDays,
                    onSave: (v) =>
                        repo.updateSettings(s.copyWith(reminderDays: v)),
                  ),
                ),
                Divider(color: Theme.of(context).dividerColor),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Language'.tr,
                        style: const TextStyle(fontSize: 13.5),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment(value: 'fa', label: Text('فارسی')),
                          ButtonSegment(value: 'en', label: Text('English')),
                        ],
                        selected: {s.languageCode},
                        onSelectionChanged: (v) => repo.updateSettings(
                          s.copyWith(languageCode: v.first),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Appearance'.tr,
                        style: const TextStyle(fontSize: 13.5),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: [
                          ButtonSegment(
                            value: 'system',
                            label: Text('System'.tr),
                          ),
                          ButtonSegment(
                            value: 'light',
                            label: Text('Light'.tr),
                          ),
                          ButtonSegment(value: 'dark', label: Text('Dark'.tr)),
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

          // ---------- Security ----------
          const SectionTitle('Security', icon: Icons.lock_outline_rounded),
          CardBox(
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: repo.hasAppLock,
                  onChanged: (wantLock) =>
                      _toggleAppLock(context, wantLock: wantLock),
                  secondary: const Icon(Icons.pin_outlined, size: 20),
                  title: Text(
                    'App lock (PIN)'.tr,
                    style: const TextStyle(fontSize: 13.5),
                  ),
                  subtitle: Text(
                    (repo.hasAppLock
                            ? 'Ask for a PIN when the app opens'
                            : 'Your bank SMS and customer debts are readable by anyone holding the phone')
                        .tr,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
                if (repo.hasAppLock) ...[
                  Divider(color: Theme.of(context).dividerColor),
                  const _BiometricUnlockTile(),
                  _actionTile(
                    context,
                    icon: Icons.password_rounded,
                    title: 'Change PIN'.tr,
                    subtitle: 'Enter the current PIN, then pick a new one',
                    onTap: () => _runPinSetup(
                      context,
                      PinSetupMode.change,
                      'PIN changed',
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ---------- Backups ----------
          const SectionTitle('Backups', icon: Icons.cloud_sync_outlined),
          CardBox(
            child: Column(
              children: [
                _actionTile(
                  context,
                  icon: Icons.share_rounded,
                  title: 'Share backup'.tr,
                  subtitle:
                      'Export JSON to a messaging app or save it on your phone',
                  onTap: () => _backup(context, repo, share: true),
                ),
                Divider(color: Theme.of(context).dividerColor),
                _actionTile(
                  context,
                  icon: Icons.download_rounded,
                  title: 'Save backup to device'.tr,
                  subtitle: 'Choose where to save the JSON file',
                  onTap: () => _backup(context, repo, share: false),
                ),
                Divider(color: Theme.of(context).dividerColor),
                _actionTile(
                  context,
                  icon: Icons.restore_rounded,
                  title: 'Restore from backup'.tr,
                  subtitle: 'All current data will be replaced with the selected file',
                  onTap: () => _restore(context, repo),
                ),
              ],
            ),
          ),

          // ---------- Data ----------
          const SectionTitle('Data', icon: Icons.storage_rounded),
          CardBox(
            child: Column(
              children: [
                _actionTile(
                  context,
                  icon: Icons.auto_awesome_outlined,
                  title: 'Load sample data'.tr,
                  subtitle:
                      'For a quick app demo (current data will be erased)',
                  onTap: () async {
                    final ok = await confirmDialog(
                      context,
                      title: 'Sample data'.tr,
                      message: 'Current data will be erased and replaced with sample data. Continue?'
                          .tr,
                      okLabel: 'Continue'.tr,
                    );
                    if (!ok) return;
                    await repo.loadDemoData();
                    if (context.mounted) {
                      showSnack(context, 'Sample data loaded'.tr);
                    }
                  },
                ),
                Divider(color: Theme.of(context).dividerColor),
                _actionTile(
                  context,
                  icon: Icons.delete_forever_outlined,
                  title: 'Erase all data'.tr,
                  subtitle: 'Reset the app (cannot be undone)',
                  danger: true,
                  onTap: () async {
                    final ok = await confirmDialog(
                      context,
                      title: 'Erase all data'.tr,
                      message: 'All customers, subscriptions, and transactions will be deleted. Back up your data first.'
                          .tr,
                      okLabel: 'Clear',
                      danger: true,
                    );
                    if (!ok) return;
                    await repo.wipeAll();
                    if (context.mounted) showSnack(context, 'All data erased');
                  },
                ),
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
                    title: Text(
                      'Read bank SMS'.tr,
                      style: TextStyle(fontSize: 13.5),
                    ),
                    subtitle: Text(
                      'Deposits and withdrawals are detected automatically and added to the review queue'
                          .tr,
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
                    title: 'Review SMS'.tr,
                    subtitle: repo.smsPendingCount > 0
                        ? '{count} transactions awaiting review'.trArgs({
                            'count': repo.smsPendingCount,
                          })
                        : 'Nothing awaiting review'.tr,
                    page: const SmsPage(),
                  ),
                  Divider(color: Theme.of(context).dividerColor),
                  _navTile(
                    context,
                    icon: Icons.tune_rounded,
                    title: 'Recognition rules'.tr,
                    subtitle:
                        'Choose which built-in banks and custom senders can match SMS.'
                            .tr,
                    page: const SmsRulesPage(),
                  ),
                  Divider(color: Theme.of(context).dividerColor),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.date_range_outlined, size: 20),
                    title: Text(
                      'SMS lookback period'.tr,
                      style: TextStyle(fontSize: 13.5),
                    ),
                    subtitle: Text(
                      'Past {days} days'.trArgs({'days': s.smsSyncDays}),
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    onTap: () => _editInt(
                      context,
                      title: 'How many past days should be checked?'.tr,
                      initial: s.smsSyncDays,
                      onSave: (v) => repo.updateSettings(
                        s.copyWith(smsSyncDays: v.clamp(1, 365)),
                      ),
                    ),
                  ),
                  Divider(color: Theme.of(context).dividerColor),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.info_outline_rounded, size: 20),
                    title: Text(
                      'Manual SMS review is required'.tr,
                      style: TextStyle(fontSize: 13.5),
                    ),
                    subtitle: Text(
                      'Choose VPN business or personal before recording each SMS transaction.'
                          .tr,
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // ---------- Daily reminder ----------
          if (reminder.supported) ...[
            const SectionTitle(
              'Daily reminder',
              icon: Icons.notifications_active_outlined,
            ),
            CardBox(
              child: Column(
                children: [
                  if (isAndroidPlatform) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.music_note_outlined, size: 20),
                      title: Text(
                        'Notification sound'.tr,
                        style: const TextStyle(fontSize: 13.5),
                      ),
                      subtitle: Text(
                        s.notificationSoundName ?? 'System default'.tr,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Test notification sound'.tr,
                            onPressed: () => _testNotificationSound(context, s),
                            icon: const Icon(Icons.play_arrow_rounded),
                          ),
                          PopupMenuButton<_NotificationSoundAction>(
                            tooltip: 'Choose notification sound'.tr,
                            onSelected: (action) => _selectNotificationSound(
                              context,
                              repo,
                              s,
                              action,
                            ),
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: _NotificationSoundAction.systemDefault,
                                child: Text('System default'.tr),
                              ),
                              PopupMenuItem(
                                value: _NotificationSoundAction.phoneSound,
                                child: Text('Choose a phone sound'.tr),
                              ),
                              PopupMenuItem(
                                value: _NotificationSoundAction.audioFile,
                                child: Text('Choose an audio file'.tr),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Divider(color: Theme.of(context).dividerColor),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: s.dailyReminder,
                    title: Text(
                      'Expense reminder'.tr,
                      style: TextStyle(fontSize: 13.5),
                    ),
                    subtitle: Text(
                      'Reminds you every day at the selected time to record your expenses and income'
                          .tr,
                      style: TextStyle(fontSize: 11.5),
                    ),
                    onChanged: (v) async {
                      if (v) {
                        final ok = await reminder.requestPermission();
                        if (!ok) {
                          if (context.mounted) {
                            showSnack(
                              context,
                              'Notification permission denied. Enable it in Android settings.',
                              error: true,
                            );
                          }
                          return;
                        }
                      }
                      await repo.updateSettings(s.copyWith(dailyReminder: v));
                    },
                  ),
                  if (s.dailyReminder) ...[
                    Divider(color: Theme.of(context).dividerColor),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule_rounded, size: 20),
                      title: Text(
                        'Reminder time'.tr,
                        style: TextStyle(fontSize: 13.5),
                      ),
                      subtitle: Text(
                        '${s.reminderHour.toString().padLeft(2, '0')}:${s.reminderMinute.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onTap: () async {
                        final t = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay(
                            hour: s.reminderHour,
                            minute: s.reminderMinute,
                          ),
                        );
                        if (t == null || !context.mounted) return;
                        await repo.updateSettings(
                          s.copyWith(
                            reminderHour: t.hour,
                            reminderMinute: t.minute,
                          ),
                        );
                      },
                    ),
                    Divider(color: Theme.of(context).dividerColor),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.send_rounded, size: 20),
                      title: Text(
                        'Send test notification'.tr,
                        style: TextStyle(fontSize: 13.5),
                      ),
                      subtitle: Text(
                        'Check that notifications are displayed'.tr,
                        style: TextStyle(fontSize: 11.5),
                      ),
                      onTap: () async {
                        try {
                          await reminder.showNow(
                            title: 'Poolland reminder test'.tr,
                            body: 'If you can see this message, notifications are working ✓',
                            soundUri: s.notificationSoundUri,
                            soundName: s.notificationSoundName,
                          );
                        } catch (_) {
                          if (context.mounted) {
                            showSnack(
                              context,
                              'Could not send notification',
                              error: true,
                            );
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
                Text(
                  'Poolland Ledger'.tr,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  aboutText,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.9,
                    color: onSurface.withValues(alpha: 0.65),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _navTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget page,
  }) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(icon, size: 20),
    title: Text(title.tr, style: const TextStyle(fontSize: 13.5)),
    subtitle: Text(
      subtitle.tr,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 11.5),
    ),
    trailing: const Icon(Icons.chevron_right_rounded, size: 18),
    onTap: () =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
  );

  /// Push the PIN flow and confirm the outcome once it comes back.
  Future<void> _runPinSetup(
    BuildContext context,
    PinSetupMode mode,
    String successMessage,
  ) async {
    final applied = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => PinSetupPage(mode: mode)),
    );
    if (applied != true || !context.mounted) return;
    showSnack(context, successMessage);
  }

  /// Turning the switch on or off both require going through the PIN flow:
  /// on needs a PIN to set, off needs the current PIN to prove it is you.
  Future<void> _toggleAppLock(
    BuildContext context, {
    required bool wantLock,
  }) => _runPinSetup(
    context,
    wantLock ? PinSetupMode.create : PinSetupMode.remove,
    wantLock ? 'App lock is on' : 'App lock turned off',
  );

  Widget _actionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool danger = false,
  }) => ListTile(
    contentPadding: EdgeInsets.zero,
    onTap: onTap,
    leading: Icon(
      icon,
      size: 20,
      color: danger ? const Color(0xFFE11D48) : null,
    ),
    title: Text(
      title.tr,
      style: TextStyle(
        fontSize: 13.5,
        color: danger ? const Color(0xFFE11D48) : null,
      ),
    ),
    subtitle: Text(subtitle.tr, style: const TextStyle(fontSize: 11.5)),
  );

  Future<void> _editText(
    BuildContext context, {
    required String title,
    required String initial,
    required Future<void> Function(String) onSave,
    String? hint,
  }) async {
    final ctrl = TextEditingController(text: initial);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title.tr),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(hintText: hint?.tr),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text('Save'.tr),
          ),
        ],
      ),
    );
    if (res != null && res.isNotEmpty) await onSave(res);
  }

  Future<void> _editAmount(
    BuildContext context, {
    required String title,
    required double initial,
    required Future<void> Function(double) onSave,
  }) async {
    final ctrl = TextEditingController(text: groupedNumber(initial));
    final res = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title.tr),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: 'Toman'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, parseAmount(ctrl.text)),
            child: Text('Save'.tr),
          ),
        ],
      ),
    );
    if (res != null) await onSave(res);
  }

  Future<void> _editInt(
    BuildContext context, {
    required String title,
    required int initial,
    required Future<void> Function(int) onSave,
  }) async {
    final ctrl = TextEditingController(text: '$initial');
    final res = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title.tr),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: 'day'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel'.tr),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, parseAmount(ctrl.text).toInt().clamp(0, 60)),
            child: Text('Save'.tr),
          ),
        ],
      ),
    );
    if (res != null) await onSave(res);
  }

  Future<void> _backup(
    BuildContext context,
    AppRepository repo, {
    required bool share,
  }) async {
    final content = const JsonEncoder.withIndent('  ')
        .convert(repo.exportData());
    final name =
        'poolland-backup-${J.d(DateTime.now(), persian: false).replaceAll('/', '-')}.json';
    final ok = share
        ? await Backup.shareFile(fileName: name, content: content)
        : await Backup.saveToDevice(fileName: name, content: content);
    if (context.mounted) {
      showSnack(
        context,
        ok ? 'Backup file created' : 'Backup save cancelled',
        error: !ok,
      );
    }
  }

  Future<void> _restore(BuildContext context, AppRepository repo) async {
    try {
      final data = await Backup.pickJsonContent();
      if (data == null) return;
      if (!context.mounted) return;
      final ok = await confirmDialog(
        context,
        title: 'Restore backup'.tr,
        message: 'All current data will be replaced with the contents of this file. Continue?'
            .tr,
        okLabel: 'Restore',
      );
      if (!ok) return;
      await repo.importData(data);
      if (context.mounted) showSnack(context, 'Backup restored');
    } catch (e) {
      if (context.mounted) {
        showSnack(
          context,
          'Invalid file: {error}'.trArgs({'error': '$e'}),
          error: true,
        );
      }
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
      appBar: AppBar(title: Text('Currencies and exchange rates'.tr)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addCurrency(context, repo),
        icon: const Icon(Icons.add_rounded),
        label: Text('Add currency'.tr),
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
                    'The base currency is Toman. Enter each currency’s rate in Toman to convert reports automatically.'
                        .tr,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.8,
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.7),
                    ),
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
                      color: Theme.of(context).colorScheme.primary
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      c.symbol,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${c.name.tr} (${c.code})',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          c.code == s.baseCurrency
                              ? 'Base currency'
                              : '1 ${c.name.tr} = ${Money.text(c.rateToBase)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Theme.of(context).colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (c.code != s.baseCurrency)
                    IconButton(
                      tooltip: 'Delete'.tr,
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      onPressed: () async {
                        final ok = await confirmDialog(
                          context,
                          title: 'Remove currency'.tr,
                          message: 'Remove {currency}? Existing transactions will not be deleted.'
                              .trArgs({'currency': c.name.tr}),
                          okLabel: 'Delete'.tr,
                          danger: true,
                        );
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

  Future<void> _editRate(
    BuildContext context,
    AppRepository repo,
    CurrencyDef c,
  ) async {
    final ctrl = TextEditingController(text: groupedNumber(c.rateToBase));
    final res = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          '{currency} exchange rate in Toman'.trArgs({'currency': c.name.tr}),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: 'Toman'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, parseAmount(ctrl.text)),
            child: Text('Save'.tr),
          ),
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
        title: Text('Add currency'.tr),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: code,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'Code (e.g. AED)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: symbol,
                decoration: const InputDecoration(labelText: 'Symbol'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: rate,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Rate in Toman',
                  suffixText: 'Toman',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Add'.tr),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (code.text.trim().isEmpty || name.text.trim().isEmpty) return;
    await repo.upsertCurrency(
      CurrencyDef(
        code: code.text.trim().toUpperCase(),
        name: name.text.trim(),
        symbol: symbol.text.trim().isEmpty
            ? name.text.trim()
            : symbol.text.trim(),
        rateToBase: parseAmount(rate.text),
        decimals: 2,
      ),
    );
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
          title: Text('Categories'.tr),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Income'.tr),
              Tab(text: 'Expense'.tr),
            ],
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
                        : const Color(0xFFE11D48),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      c.name.tr,
                      style: const TextStyle(fontSize: 13.5),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Edit'.tr,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () async {
                      final ctrl = TextEditingController(text: c.name);
                      final res = await showDialog<String>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text('Edit category'.tr),
                          content: TextField(controller: ctrl, autofocus: true),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: Text('Cancel'.tr),
                            ),
                            FilledButton(
                              onPressed: () =>
                                  Navigator.pop(ctx, ctrl.text.trim()),
                              child: Text('Save'.tr),
                            ),
                          ],
                        ),
                      );
                      if (res != null && res.isNotEmpty) {
                        await repo.renameCategory(c, res);
                      }
                    },
                  ),
                  IconButton(
                    tooltip: 'Delete'.tr,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    onPressed: () async {
                      final ok = await confirmDialog(
                        context,
                        title: 'Delete category'.tr,
                        message: 'Delete category “{name}”? Its transactions will become uncategorized.'
                            .trArgs({'name': c.name.tr}),
                        okLabel: 'Delete'.tr,
                        danger: true,
                      );
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
                title: Text(
                  kind == TxnKind.income
                      ? 'New income category'
                      : 'New expense category',
                ),
                content: TextField(
                  controller: ctrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Server purchase',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('Cancel'.tr),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                    child: Text('Add'.tr),
                  ),
                ],
              ),
            );
            if (res != null && res.isNotEmpty) {
              await repo.addCategory(res, kind, scope: _scope);
            }
          },
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text('Add category'.tr),
        ),
      ],
    );
  }
}

/// Fingerprint switch, shown only when the phone can actually do it.
///
/// Stateful so the availability check runs once per visit instead of on every
/// rebuild: a plain FutureBuilder would restart the check each time the repo
/// notifies, and the switch would blink out of existence as it was toggled.
class _BiometricUnlockTile extends StatefulWidget {
  const _BiometricUnlockTile();

  @override
  State<_BiometricUnlockTile> createState() => _BiometricUnlockTileState();
}

class _BiometricUnlockTileState extends State<_BiometricUnlockTile> {
  bool _available = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final available = await Biometrics.isAvailable();
    if (!mounted) return;
    setState(() => _available = available);
  }

  @override
  Widget build(BuildContext context) {
    // A phone with no sensor, or with no fingerprint enrolled in Android
    // itself, gets no switch at all rather than one that cannot work.
    if (!_available) return const SizedBox.shrink();

    final repo = context.watch<AppRepository>();
    return Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: repo.biometricUnlock,
          onChanged: repo.setBiometricUnlock,
          secondary: const Icon(Icons.fingerprint_rounded, size: 20),
          title: Text(
            'Unlock with fingerprint'.tr,
            style: const TextStyle(fontSize: 13.5),
          ),
          subtitle: Text(
            'The PIN still works if the sensor fails'.tr,
            style: const TextStyle(fontSize: 11.5),
          ),
        ),
        Divider(color: Theme.of(context).dividerColor),
      ],
    );
  }
}
