import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_info.dart';
import '../core/backup.dart';
import '../core/biometrics.dart';
import '../core/format_utils.dart';
import '../core/jalali_utils.dart';
import '../core/localization.dart';
import '../core/money.dart';
import '../core/notifications/notification_sound_picker.dart';
import '../core/notifications/notify.dart';
import '../core/platform_info.dart';
import '../core/sms/sms_access.dart';
import '../data/models.dart';
import '../data/pdf_service.dart';
import '../data/repository.dart';
import 'customer_detail_page.dart';
import 'design.dart';
import 'forms/plan_edit_page.dart';
import 'gesture_tour.dart';
import 'lock/pin_setup_page.dart';
import 'motion_kit.dart';
import 'personal_page.dart';
import 'sms_page.dart';
import 'sms_rules_page.dart';
import 'theme.dart';
import 'widgets/widgets.dart';

enum _NotificationSoundAction { systemDefault, phoneSound, audioFile }

Future<void> _syncSmsArrivalRuleHints(AppRepository repo) {
  final rules = repo.activeSmsRules;
  return smsAccess.syncArrivalRules(
    senderHints: rules.expand((rule) => rule.senderHints).toList(),
    bodyHints: rules.expand((rule) => rule.bodyHints).toList(),
  );
}

/// The "Save" action of a small input dialog, disabled while the field holds
/// nothing usable.
Widget _saveWhen(
  TextEditingController controller,
  bool Function(String) valid,
  VoidCallback onSave,
) {
  return ValueListenableBuilder<TextEditingValue>(
    valueListenable: controller,
    builder: (context, value, _) => FilledButton(
      onPressed: valid(value.text) ? onSave : null,
      child: Text('Save'.tr),
    ),
  );
}

class _SettingIconBadge extends StatelessWidget {
  const _SettingIconBadge({required this.icon, this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 19, color: c),
    );
  }
}

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
    final archivedCustomerCount = repo.customers
        .where((c) => c.archived)
        .length;
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
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: Text('Settings'.tr)),
      body: RepaintBoundary(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: [
            // ---------- Business ----------
            const SectionTitle('Business', icon: Icons.storefront_outlined),
            CardBox(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const _SettingIconBadge(
                      icon: Icons.badge_outlined,
                      color: AppTheme.primary,
                    ),
                    title: Text(
                      'Business name'.tr,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      s.businessName,
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.edit_outlined, size: 18),
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
                    leading: const _SettingIconBadge(
                      icon: Icons.account_balance_wallet_outlined,
                      color: AppTheme.revenue,
                    ),
                    title: Text(
                      'Opening cash balance'.tr,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '{amount} — cash or bank balance you already had'.trArgs({
                        'amount': Money.text(s.openingCash),
                      }),
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    trailing: const Icon(Icons.edit_outlined, size: 18),
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
                    iconColor: AppTheme.primary,
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
                    iconColor: AppTheme.receivable,
                    title: 'Income and expense categories'.tr,
                    subtitle: '{count} categories (business and personal)'
                        .trArgs({'count': repo.categories.length}),
                    page: const CategoriesPage(),
                  ),
                  Divider(color: Theme.of(context).dividerColor),
                  _navTile(
                    context,
                    icon: Icons.currency_exchange_rounded,
                    iconColor: AppTheme.revenue,
                    title: 'Currencies and exchange rates'.tr,
                    subtitle: s.currencies
                        .map((c) => '${c.code} ${Fmt.number(c.rateToBase)}')
                        .join(' • '),
                    page: const RatesPage(),
                  ),
                  Divider(color: Theme.of(context).dividerColor),
                  _navTile(
                    context,
                    icon: Icons.pie_chart_outline_rounded,
                    iconColor: AppTheme.warning,
                    title: 'Monthly budgets'.tr,
                    subtitle: '{count} monthly budgets'.trArgs({
                      'count': repo.budgets.length,
                    }),
                    page: const BudgetsManagePage(),
                  ),
                  Divider(color: Theme.of(context).dividerColor),
                  _navTile(
                    context,
                    icon: Icons.autorenew_rounded,
                    iconColor: AppTheme.info,
                    title: 'Recurring transactions'.tr,
                    subtitle: '{count} recurring rules'.trArgs({
                      'count': repo.recurringRules.length,
                    }),
                    page: const RecurringManagePage(),
                  ),
                  Divider(color: Theme.of(context).dividerColor),
                  _navTile(
                    context,
                    icon: Icons.inventory_2_outlined,
                    iconColor: onSurface.withValues(alpha: 0.7),
                    title: 'Archived customers'.tr,
                    subtitle: '{count} archived customers'.trArgs({
                      'count': archivedCustomerCount,
                    }),
                    page: const ArchivedCustomersPage(),
                  ),
                ],
              ),
            ),

            // ---------- Bank SMS ----------
            if (isAndroidPlatform) ...[
              const SectionTitle('Bank SMS', icon: Icons.sms_rounded),
              CardBox(
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const _SettingIconBadge(
                        icon: Icons.shield_outlined,
                        color: AppTheme.revenue,
                      ),
                      title: Text(
                        'On-device SMS access'.tr,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        'Recent bank messages are read on this device when you sync. New messages are checked only if you enable arrival alerts. Nothing is recorded until you approve it.'
                            .tr,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                    Divider(color: Theme.of(context).dividerColor),
                    _navTile(
                      context,
                      icon: Icons.fact_check_outlined,
                      iconColor: AppTheme.primary,
                      title: 'Review SMS'.tr,
                      subtitle: repo.smsPendingCount > 0
                          ? '{count} transactions awaiting review'.trArgs({
                              'count': repo.smsPendingCount,
                            })
                          : 'Sync bank SMS to review transactions'.tr,
                      page: const SmsPage(),
                    ),
                    Divider(color: Theme.of(context).dividerColor),
                    _navTile(
                      context,
                      icon: Icons.tune_rounded,
                      iconColor: AppTheme.info,
                      title: 'Recognition rules'.tr,
                      subtitle:
                          'Choose which banks and phrases a bank SMS can match.'
                              .tr,
                      page: const SmsRulesPage(),
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
                    if (isAndroidPlatform &&
                        s.dailyReminder &&
                        !repo.notificationPermissionGranted) ...[
                      _actionTile(
                        context,
                        icon: Icons.notification_important_outlined,
                        iconColor: AppTheme.warning,
                        title: 'Notification permission not granted'.tr,
                        subtitle:
                            'Notifications are switched on but Android blocks them. Tap to request again.'
                                .tr,
                        onTap: () async {
                          final ok = await reminder.requestPermission();
                          await repo.refreshNotificationPermission();
                          if (!ok && context.mounted) {
                            showSnack(
                              context,
                              'Notification permission denied. Enable it in Android settings.',
                              error: true,
                            );
                          }
                        },
                      ),
                      Divider(color: Theme.of(context).dividerColor),
                    ],
                    if (isAndroidPlatform) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const _SettingIconBadge(
                          icon: Icons.music_note_outlined,
                          color: AppTheme.primary,
                        ),
                        title: Text(
                          'Notification sound'.tr,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
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
                              onPressed: () =>
                                  _testNotificationSound(context, s),
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
                      secondary: const _SettingIconBadge(
                        icon: Icons.alarm_rounded,
                        color: AppTheme.warning,
                      ),
                      title: Text(
                        'Expense reminder'.tr,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        'Reminds you every day at the selected time to record your expenses and income'
                            .tr,
                        style: const TextStyle(fontSize: 11.5),
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
                        leading: const _SettingIconBadge(
                          icon: Icons.schedule_rounded,
                          color: AppTheme.info,
                        ),
                        title: Text(
                          'Reminder time'.tr,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
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
                        leading: const _SettingIconBadge(
                          icon: Icons.send_rounded,
                          color: AppTheme.revenue,
                        ),
                        title: Text(
                          'Send test notification'.tr,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          'Check that notifications are displayed'.tr,
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        onTap: () async {
                          try {
                            await reminder.showNow(
                              title: 'Poolland reminder test'.tr,
                              body:
                                  'If you can see this message, notifications are working ✓',
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

            // ---------- Display ----------
            const SectionTitle('Display', icon: Icons.palette_outlined),
            CardBox(
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const _SettingIconBadge(
                      icon: Icons.onetwothree_rounded,
                      color: AppTheme.primary,
                    ),
                    value: s.persianDigits,
                    onChanged: (v) =>
                        repo.updateSettings(s.copyWith(persianDigits: v)),
                    title: Text(
                      'Use Persian digits'.tr,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Divider(color: Theme.of(context).dividerColor),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const _SettingIconBadge(
                      icon: Icons.notifications_active_outlined,
                      color: AppTheme.warning,
                    ),
                    title: Text(
                      'Expiry reminders'.tr,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '{days} days before expiry'.trArgs({
                        'days': s.reminderDays,
                      }),
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    trailing: const Icon(Icons.edit_outlined, size: 18),
                    onTap: () => _editInt(
                      context,
                      title:
                          'How many days before expiry should we remind you?'
                              .tr,
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
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'fa', label: Text('فارسی')),
                              ButtonSegment(
                                value: 'en',
                                label: Text('English'),
                              ),
                            ],
                            selected: {s.languageCode},
                            onSelectionChanged: (v) => repo.updateSettings(
                              s.copyWith(languageCode: v.first),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Appearance'.tr,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<String>(
                            segments: [
                              ButtonSegment(
                                value: 'system',
                                label: Text('System'.tr),
                              ),
                              ButtonSegment(
                                value: 'light',
                                label: Text('Light'.tr),
                              ),
                              ButtonSegment(
                                value: 'dark',
                                label: Text('Dark'.tr),
                              ),
                            ],
                            selected: {s.themeMode},
                            onSelectionChanged: (v) => repo.updateSettings(
                              s.copyWith(themeMode: v.first),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // ---------- Gesture guide ----------
            const SizedBox(height: 8),
            CardBox(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const _SettingIconBadge(
                  icon: Icons.touch_app_outlined,
                  color: AppTheme.info,
                ),
                title: Text(
                  'Gesture guide'.tr,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'See every swipe, hold and drag again'.tr,
                  style: const TextStyle(fontSize: 11.5),
                ),
                trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                onTap: () => showGestureTour(context),
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
                    secondary: const _SettingIconBadge(
                      icon: Icons.pin_outlined,
                      color: AppTheme.primary,
                    ),
                    title: Text(
                      'App lock (PIN)'.tr,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
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
                      iconColor: AppTheme.warning,
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
            const SectionTitle(
              'Backup and data',
              icon: Icons.cloud_sync_outlined,
            ),
            CardBox(
              child: Column(
                children: [
                  _DataSummaryRow(repo: repo),
                  const SizedBox(height: 10),
                  Divider(color: Theme.of(context).dividerColor),
                  _actionTile(
                    context,
                    icon: Icons.share_rounded,
                    iconColor: AppTheme.primary,
                    title: 'Share backup'.tr,
                    subtitle:
                        'Export JSON to a messaging app or save it on your phone',
                    onTap: () => _backup(context, repo, share: true),
                  ),
                  Divider(color: Theme.of(context).dividerColor),
                  _actionTile(
                    context,
                    icon: Icons.download_rounded,
                    iconColor: AppTheme.revenue,
                    title: 'Save backup to device'.tr,
                    subtitle: 'Choose where to save the JSON file',
                    onTap: () => _backup(context, repo, share: false),
                  ),
                  Divider(color: Theme.of(context).dividerColor),
                  _actionTile(
                    context,
                    icon: Icons.picture_as_pdf_outlined,
                    iconColor: AppTheme.expense,
                    title: 'Export full PDF report'.tr,
                    subtitle:
                        'Generate and share a complete PDF summary of your ledger',
                    onTap: () => _exportFullPdf(context, repo),
                  ),
                  Divider(color: Theme.of(context).dividerColor),
                  _actionTile(
                    context,
                    icon: Icons.restore_rounded,
                    iconColor: AppTheme.warning,
                    title: 'Restore from backup'.tr,
                    subtitle:
                        'All current data will be replaced with the selected file',
                    onTap: () => _restore(context, repo),
                  ),
                ],
              ),
            ),

            // ---------- Data actions (second card of Backup and data) ----------
            const SizedBox(height: 8),
            CardBox(
              child: Column(
                children: [
                  _actionTile(
                    context,
                    icon: Icons.auto_awesome_outlined,
                    iconColor: AppTheme.info,
                    title: 'Load sample data'.tr,
                    subtitle:
                        'For a quick app demo (current data will be erased)',
                    onTap: () async {
                      final ok = await confirmDialog(
                        context,
                        title: 'Sample data'.tr,
                        message:
                            'Current data will be erased and replaced with sample data. Continue?'
                                .tr,
                        okLabel: 'Continue'.tr,
                      );
                      if (!ok) return;
                      await repo.loadDemoData();
                      await _syncSmsArrivalRuleHints(repo);
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
                        message:
                            'All customers, subscriptions, and transactions will be deleted. Back up your data first.'
                                .tr,
                        okLabel: 'Clear',
                        danger: true,
                      );
                      if (!ok) return;
                      await smsAccess.setArrivalNotificationsEnabled(false);
                      await repo.wipeAll();
                      await _syncSmsArrivalRuleHints(repo);
                      if (context.mounted) {
                        showSnack(context, 'All data erased');
                      }
                    },
                  ),
                ],
              ),
            ),

            // ---------- About ----------
            const SectionTitle('About', icon: Icons.info_outline_rounded),
            CardBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const _SettingIconBadge(
                        icon: Icons.account_balance_rounded,
                        color: AppTheme.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Poolland Ledger'.tr,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
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
      ),
    );
  }

  Widget _navTile(
    BuildContext context, {
    required IconData icon,
    Color? iconColor,
    required String title,
    required String subtitle,
    required Widget page,
  }) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: _SettingIconBadge(icon: icon, color: iconColor),
    title: Text(
      title.tr,
      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
    ),
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
    Color? iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final color = danger ? const Color(0xFFE11D48) : iconColor;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: _SettingIconBadge(icon: icon, color: color),
      title: Text(
        title.tr,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: danger ? const Color(0xFFE11D48) : null,
        ),
      ),
      subtitle: Text(subtitle.tr, style: const TextStyle(fontSize: 11.5)),
    );
  }

  Future<void> _editText(
    BuildContext context, {
    required String title,
    required String initial,
    required Future<void> Function(String) onSave,
    String? hint,
  }) async {
    final res = await showDialog<String>(
      context: context,
      builder: (_) =>
          _TextPromptDialog(title: title, initial: initial, hint: hint),
    );
    if (res != null && res.isNotEmpty) await onSave(res);
  }

  Future<void> _editAmount(
    BuildContext context, {
    required String title,
    required double initial,
    required Future<void> Function(double) onSave,
  }) async {
    final res = await showDialog<double>(
      context: context,
      builder: (_) => _AmountPromptDialog(title: title, initial: initial),
    );
    if (res != null) await onSave(res);
  }

  Future<void> _editInt(
    BuildContext context, {
    required String title,
    required int initial,
    required Future<void> Function(int) onSave,
  }) async {
    final res = await showDialog<int>(
      context: context,
      builder: (_) => _IntPromptDialog(title: title, initial: initial),
    );
    if (res != null) await onSave(res);
  }

  Future<void> _exportFullPdf(BuildContext context, AppRepository repo) async {
    try {
      final now = DateTime.now();
      DateTime from = DateTime(now.year - 1, now.month, now.day);
      if (repo.transactions.isNotEmpty) {
        for (final t in repo.transactions) {
          if (t.date.isBefore(from)) from = t.date;
        }
      }
      final bytes = await PdfService.buildReport(
        repo: repo,
        from: from,
        to: now,
      );
      await Backup.shareBytes(
        fileName: 'poolland-report-${J.d(now, persian: false).replaceAll('/', '-')}.pdf',
        bytes: bytes,
        mimeType: 'application/pdf',
      );
      if (context.mounted) {
        showSnack(context, 'PDF report created');
      }
    } catch (e) {
      if (context.mounted) {
        showSnack(context, '$e', error: true);
      }
    }
  }

  Future<void> _backup(
    BuildContext context,
    AppRepository repo, {
    required bool share,
  }) async {
    final content = const JsonEncoder.withIndent(
      '  ',
    ).convert(repo.exportData());
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
        message:
            'All current data will be replaced with the contents of this file. Continue?'
                .tr,
        okLabel: 'Restore',
      );
      if (!ok) return;
      await repo.importData(data);
      await _syncSmsArrivalRuleHints(repo);
      await repo.refreshNotificationPermission();
      if (repo.settings.dailyReminder && !repo.notificationPermissionGranted) {
        await reminder.requestPermission();
        await repo.refreshNotificationPermission();
      }
      if (context.mounted) showSnack(context, 'Backup restored');
    } catch (e) {
      if (context.mounted) {
        showSnack(
          context,
          'Invalid file: {error}'.trArgs({
            'error': e is FormatException ? e.message.tr : '$e',
          }),
          error: true,
        );
      }
    }
  }
}

class _DataSummaryRow extends StatelessWidget {
  const _DataSummaryRow({required this.repo});

  final AppRepository repo;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    Widget pill(String label, int count, Color color) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              Fmt.number(count),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label.tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: onSurface.withValues(alpha: 0.65),
              ),
            ),
          ],
        ),
      ),
    );

    return Row(
      children: [
        pill('Customers', repo.customers.length, AppTheme.primary),
        const SizedBox(width: 6),
        pill('Subscriptions', repo.subscriptions.length, AppTheme.revenue),
        const SizedBox(width: 6),
        pill('Transactions', repo.transactions.length, AppTheme.info),
        const SizedBox(width: 6),
        pill('Categories', repo.categories.length, AppTheme.receivable),
      ],
    );
  }
}

/// ---------- Prompt dialogs with proper controller disposal ----------
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.initial,
    this.hint,
  });

  final String title;
  final String initial;
  final String? hint;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title.tr),
      content: TextField(
        controller: _ctrl,
        decoration: InputDecoration(hintText: widget.hint?.tr),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'.tr),
        ),
        _saveWhen(
          _ctrl,
          (v) => v.trim().isNotEmpty,
          () => Navigator.pop(context, _ctrl.text.trim()),
        ),
      ],
    );
  }
}

class _AmountPromptDialog extends StatefulWidget {
  const _AmountPromptDialog({required this.title, required this.initial});

  final String title;
  final double initial;

  @override
  State<_AmountPromptDialog> createState() => _AmountPromptDialogState();
}

class _AmountPromptDialogState extends State<_AmountPromptDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: groupedNumber(widget.initial));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title.tr),
      content: TextField(
        controller: _ctrl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(suffixText: 'Toman'.tr),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'.tr),
        ),
        _saveWhen(
          _ctrl,
          (v) => v.trim().isNotEmpty,
          () => Navigator.pop(context, parseAmount(_ctrl.text)),
        ),
      ],
    );
  }
}

class _IntPromptDialog extends StatefulWidget {
  const _IntPromptDialog({required this.title, required this.initial});

  final String title;
  final int initial;

  @override
  State<_IntPromptDialog> createState() => _IntPromptDialogState();
}

class _IntPromptDialogState extends State<_IntPromptDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: '${widget.initial}');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title.tr),
      content: TextField(
        controller: _ctrl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(suffixText: 'day'.tr),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'.tr),
        ),
        _saveWhen(
          _ctrl,
          (v) => v.trim().isNotEmpty,
          () => Navigator.pop(
            context,
            parseAmount(_ctrl.text).toInt().clamp(0, 60),
          ),
        ),
      ],
    );
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
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: Text('Currencies and exchange rates'.tr)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addCurrency(context, repo),
        icon: const Icon(Icons.add_rounded),
        label: Text('Add currency'.tr),
      ),
      body: RepaintBoundary(
        child: ListView(
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
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.7),
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
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.12),
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
                                ? 'Base currency'.tr
                                : '1 ${c.name.tr} = ${Money.text(c.rateToBase)}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (c.code != s.baseCurrency)
                      IconButton(
                        tooltip: 'Delete'.tr,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                        ),
                        onPressed: () async {
                          final ok = await confirmDialog(
                            context,
                            title: 'Remove currency'.tr,
                            message:
                                'Remove {currency}? Existing transactions will not be deleted.'
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
      ),
    );
  }

  Future<void> _editRate(
    BuildContext context,
    AppRepository repo,
    CurrencyDef c,
  ) async {
    final res = await showDialog<double>(
      context: context,
      builder: (_) => _RatePromptDialog(currency: c),
    );
    if (res != null && res > 0) {
      await repo.upsertCurrency(c.copyWith(rateToBase: res));
    }
  }

  Future<void> _addCurrency(BuildContext context, AppRepository repo) async {
    final draft = await showDialog<CurrencyDef>(
      context: context,
      builder: (_) => const _AddCurrencyDialog(),
    );
    if (draft == null) return;
    await repo.upsertCurrency(draft);
  }
}

class _RatePromptDialog extends StatefulWidget {
  const _RatePromptDialog({required this.currency});

  final CurrencyDef currency;

  @override
  State<_RatePromptDialog> createState() => _RatePromptDialogState();
}

class _RatePromptDialogState extends State<_RatePromptDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: groupedNumber(widget.currency.rateToBase),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        '{currency} exchange rate in Toman'.trArgs({
          'currency': widget.currency.name.tr,
        }),
      ),
      content: TextField(
        controller: _ctrl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(suffixText: 'Toman'.tr),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'.tr),
        ),
        _saveWhen(
          _ctrl,
          (v) => parseAmount(v) > 0,
          () => Navigator.pop(context, parseAmount(_ctrl.text)),
        ),
      ],
    );
  }
}

class _AddCurrencyDialog extends StatefulWidget {
  const _AddCurrencyDialog();

  @override
  State<_AddCurrencyDialog> createState() => _AddCurrencyDialogState();
}

class _AddCurrencyDialogState extends State<_AddCurrencyDialog> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _symbol = TextEditingController();
  final _rate = TextEditingController();
  int _decimals = 2;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _symbol.dispose();
    _rate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add currency'.tr),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _code,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: 'Code (e.g. AED)'.tr),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: 'Name'.tr),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _symbol,
              decoration: InputDecoration(labelText: 'Symbol'.tr),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _rate,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Rate in Toman'.tr,
                suffixText: 'Toman'.tr,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Decimals'.tr,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<int>(
                segments: [
                  ButtonSegment(value: 0, label: Text('No decimals (0)'.tr)),
                  ButtonSegment(
                    value: 2,
                    label: Text('Two decimals (0.00)'.tr),
                  ),
                ],
                selected: {_decimals},
                onSelectionChanged: (s) => setState(() => _decimals = s.first),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'.tr),
        ),
        AnimatedBuilder(
          animation: Listenable.merge([_code, _name, _rate]),
          builder: (context, child) {
            final valid =
                _code.text.trim().isNotEmpty &&
                _name.text.trim().isNotEmpty &&
                parseAmount(_rate.text) > 0;
            return FilledButton(
              onPressed: valid
                  ? () => Navigator.pop(
                      context,
                      CurrencyDef(
                        code: _code.text.trim().toUpperCase(),
                        name: _name.text.trim(),
                        symbol: _symbol.text.trim().isEmpty
                            ? _name.text.trim()
                            : _symbol.text.trim(),
                        rateToBase: parseAmount(_rate.text),
                        decimals: _decimals,
                      ),
                    )
                  : null,
              child: Text('Add'.tr),
            );
          },
        ),
      ],
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
        resizeToAvoidBottomInset: false,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Scope'.tr,
                    style: TextStyle(
                      fontSize: FontSizes.small,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: Insets.sm,
                    runSpacing: Insets.sm,
                    children: [
                      for (final sc in TxnScope.values)
                        ChoiceChip(
                          label: Text(sc.label),
                          showCheckmark: false,
                          selected: _scope == sc,
                          onSelected: (_) => setState(() => _scope = sc),
                        ),
                    ],
                  ),
                ],
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

  /// The category list: a parent and, right under it, its subcategories
  /// (indented). Orphans — whose parent was deleted — sit at the top.
  Widget _list(BuildContext context, TxnKind kind) {
    final repo = context.watch<AppRepository>();
    final all = repo.categoriesOf(kind, scope: _scope)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final byId = {for (final c in all) c.id: c};
    final childrenOf = <String, List<Category>>{};
    final tops = <Category>[];
    for (final c in all) {
      final parent = c.parentId == null ? null : byId[c.parentId];
      if (parent == null) {
        tops.add(c);
      } else {
        (childrenOf[parent.id] ??= <Category>[]).add(c);
      }
    }
    for (final ks in childrenOf.values) {
      ks.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    final rows = <_CatRow>[];
    for (final t in tops) {
      rows.add(_CatRow(t, child: false));
      rows.addAll(
        (childrenOf[t.id] ?? const <Category>[]).map(
          (k) => _CatRow(k, child: true),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
      children: [
        for (final row in rows)
          Padding(
            padding: EdgeInsetsDirectional.only(
              bottom: 8,
              start: row.child ? 24 : 0,
            ),
            child: _categoryCard(context, kind, row.category, row.child),
          ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: () => _categoryDialog(context, kind),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text('Add category'.tr),
        ),
      ],
    );
  }

  Widget _categoryCard(
    BuildContext context,
    TxnKind kind,
    Category c,
    bool child,
  ) {
    final repo = context.watch<AppRepository>();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return CardBox(
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
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: child ? 13 : 13.5,
                color: child ? onSurface.withValues(alpha: 0.8) : null,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Shortcut'.tr,
            icon: Icon(
              c.isShortcut ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              size: 18,
              color: c.isShortcut
                  ? (kind == TxnKind.income
                        ? AppTheme.revenue
                        : AppTheme.expense)
                  : onSurface.withValues(alpha: 0.45),
            ),
            onPressed: () => repo.toggleCategoryShortcut(c.id),
          ),
          IconButton(
            tooltip: 'Edit'.tr,
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => _categoryDialog(context, kind, existing: c),
          ),
          IconButton(
            tooltip: 'Delete'.tr,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            onPressed: () async {
              final hasChildren = repo
                  .categoriesOf(kind, scope: c.scope)
                  .any((k) => k.parentId == c.id);
              final message = hasChildren
                  ? 'Delete category "{name}"? Its transactions will become uncategorized. Its subcategories move to the top level.'
                        .trArgs({'name': c.name.tr})
                  : 'Delete category "{name}"? Its transactions will become uncategorized.'
                        .trArgs({'name': c.name.tr});
              final ok = await confirmDialog(
                context,
                title: 'Delete category'.tr,
                message: message,
                okLabel: 'Delete'.tr,
                danger: true,
              );
              if (ok) await repo.deleteCategory(c.id);
            },
          ),
        ],
      ),
    );
  }

  /// The one dialog for creating and editing a category: its name,
  /// parent category, and shortcut pin status.
  Future<void> _categoryDialog(
    BuildContext context,
    TxnKind kind, {
    Category? existing,
  }) async {
    final repo = context.read<AppRepository>();
    final tops = repo
        .categoriesOf(kind, scope: _scope)
        .where((c) => c.parentId == null && c.id != existing?.id)
        .toList();
    final draft = await showDialog<_CategoryDraft>(
      context: context,
      builder: (_) =>
          _CategoryEditDialog(kind: kind, tops: tops, existing: existing),
    );
    if (draft == null) return;
    final rawParent = draft.parentId;
    final parentId = (rawParent == null || rawParent.isEmpty)
        ? null
        : rawParent;
    if (existing == null) {
      await repo.addCategory(
        draft.name,
        kind,
        scope: _scope,
        parentId: parentId,
        isShortcut: draft.isShortcut,
      );
    } else {
      await repo.updateCategoryDetails(
        existing,
        name: draft.name,
        parentId: parentId,
        isShortcut: draft.isShortcut,
      );
    }
  }
}

class _CategoryEditDialog extends StatefulWidget {
  const _CategoryEditDialog({
    required this.kind,
    required this.tops,
    this.existing,
  });

  final TxnKind kind;
  final List<Category> tops;
  final Category? existing;

  @override
  State<_CategoryEditDialog> createState() => _CategoryEditDialogState();
}

class _CategoryEditDialogState extends State<_CategoryEditDialog> {
  late final TextEditingController _nameCtrl;
  late String _parentValue;
  late bool _isShortcut;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    final initialParent = widget.existing?.parentId;
    _parentValue =
        (initialParent == null ||
            !widget.tops.any((t) => t.id == initialParent))
        ? ''
        : initialParent;
    _isShortcut = widget.existing?.isShortcut ?? false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existing;
    return AlertDialog(
      title: Text(
        existing == null
            ? (widget.kind == TxnKind.income
                  ? 'New income category'.tr
                  : 'New expense category'.tr)
            : 'Edit category'.tr,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                hintText: 'e.g. Server purchase'.tr,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Parent category'.tr,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<String?>(
              initialValue: _parentValue,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: '',
                  child: Text('Top-level category'.tr),
                ),
                for (final t in widget.tops)
                  DropdownMenuItem<String?>(value: t.id, child: Text(t.name.tr)),
              ],
              onChanged: (v) => setState(() => _parentValue = v ?? ''),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _isShortcut,
              onChanged: (v) => setState(() => _isShortcut = v ?? false),
              title: Text(
                'Pin as shortcut on main sheet'.tr,
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'.tr),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _nameCtrl,
          builder: (context, value, child) => FilledButton(
            onPressed: value.text.trim().isEmpty
                ? null
                : () => Navigator.pop(
                    context,
                    _CategoryDraft(
                      name: _nameCtrl.text.trim(),
                      parentId: _parentValue,
                      isShortcut: _isShortcut,
                    ),
                  ),
            child: Text(existing == null ? 'Add'.tr : 'Save'.tr),
          ),
        ),
      ],
    );
  }
}

/// One row of the category list (a category and whether it is indented
/// under a parent).
class _CatRow {
  const _CatRow(this.category, {required this.child});
  final Category category;
  final bool child;
}

/// The result of the category create/edit dialog.
class _CategoryDraft {
  const _CategoryDraft({
    required this.name,
    required this.parentId,
    required this.isShortcut,
  });
  final String name;
  final String? parentId;
  final bool isShortcut;
}

/// ---------- Archived customers page ----------
class ArchivedCustomersPage extends StatelessWidget {
  const ArchivedCustomersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final archived = repo.customers.where((c) => c.archived).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: Text('Archived customers'.tr)),
      body: archived.isEmpty
          ? EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No archived customers'.tr,
              message:
                  'Archived customers appear here so you can restore them anytime.'
                      .tr,
            )
          : RepaintBoundary(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                itemCount: archived.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final c = archived[index];
                  final debt = repo.debtOf(c.id);
                  return CardBox(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CustomerDetailPage(customer: c),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: onSurface.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            c.name.characters.first,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                debt > 0
                                    ? '${'Debtor'.tr}: ${Money.text(debt)}'
                                    : (debt < 0
                                          ? '${'Creditor'.tr}: ${Money.text(-debt)}'
                                          : 'Settled'.tr),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: debt > 0
                                      ? AppTheme.expense
                                      : onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            await repo.updateCustomer(
                              c.copyWith(archived: false),
                            );
                            if (context.mounted) {
                              showSnack(context, 'Customer unarchived');
                            }
                          },
                          icon: const Icon(Icons.unarchive_outlined, size: 17),
                          label: Text('Unarchive'.tr),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// ---------- Monthly budgets management page ----------
class BudgetsManagePage extends StatelessWidget {
  const BudgetsManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final usages = repo.budgetUsages();
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: Text('Monthly budgets'.tr)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showLedgerSheet(
          context,
          builder: (_) => const BudgetEditSheet(),
        ),
        icon: const Icon(Icons.add_rounded),
        label: Text('New budget'.tr),
      ),
      body: usages.isEmpty
          ? EmptyState(
              icon: Icons.pie_chart_outline_rounded,
              title: 'Monthly budgets'.tr,
              message:
                  'Set a monthly limit for each category (such as food or transport); this page will show how much of each limit remains.'
                      .tr,
            )
          : RepaintBoundary(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                itemCount: usages.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final u = usages[index];
                  final pct = u.ratio;
                  final Color color = pct >= 1
                      ? AppTheme.expense
                      : (pct >= 0.8 ? AppTheme.warning : AppTheme.revenue);
                  return CardBox(
                    onTap: () => showLedgerSheet(
                      context,
                      builder: (_) => BudgetEditSheet(initial: u.budget),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                u.categoryName.tr,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            Text(
                              '${Money.text(u.spent, compact: true)} / ${Money.text(u.budget.limit, compact: true)}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: color,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Delete'.tr,
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 18,
                              ),
                              onPressed: () => repo.deleteBudget(u.budget.id),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          height: 7,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: onSurface.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: FractionallySizedBox(
                            alignment: AlignmentDirectional.centerStart,
                            widthFactor: pct < 0 ? 0 : (pct > 1 ? 1 : pct),
                            child: Container(
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// ---------- Recurring transactions management page ----------
class RecurringManagePage extends StatelessWidget {
  const RecurringManagePage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final rules = repo.recurringRules;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: Text('Recurring transactions'.tr)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showLedgerSheet(
          context,
          builder: (_) => const RecurringEditSheet(),
        ),
        icon: const Icon(Icons.add_rounded),
        label: Text('New rule'.tr),
      ),
      body: rules.isEmpty
          ? EmptyState(
              icon: Icons.autorenew_rounded,
              title: 'Recurring transactions'.tr,
              message:
                  'Set up rent, internet, subscriptions, and salary once; the app will record them automatically on schedule.'
                      .tr,
            )
          : RepaintBoundary(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                itemCount: rules.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final rule = rules[index];
                  final isIncome = rule.kind == TxnKind.income;
                  final color = isIncome ? AppTheme.revenue : AppTheme.expense;
                  final next = rule.nextDue(DateTime.now());
                  return CardBox(
                    onTap: () => showLedgerSheet(
                      context,
                      builder: (_) => RecurringEditSheet(initial: rule),
                    ),
                    child: Row(
                      children: [
                        _SettingIconBadge(
                          icon: Icons.autorenew_rounded,
                          color: color,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                rule.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                next == null
                                    ? '{period} • {amount}'.trArgs({
                                        'period': rule.period.label,
                                        'amount': Money.text(rule.amount),
                                      })
                                    : '{period} • {amount} • Next: {date}'
                                          .trArgs({
                                            'period': rule.period.label,
                                            'amount': Money.text(rule.amount),
                                            'date': J.d(next),
                                          }),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!rule.enabled)
                          TagChip(
                            'Inactive',
                            color: onSurface.withValues(alpha: 0.5),
                            dense: true,
                          ),
                        IconButton(
                          tooltip: 'Delete'.tr,
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 18,
                          ),
                          onPressed: () => repo.deleteRecurring(rule.id),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

/// Fingerprint switch, shown only when the phone can actually do it.
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
    if (!_available) return const SizedBox.shrink();

    final repo = context.watch<AppRepository>();
    return Column(
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: repo.biometricUnlock,
          onChanged: repo.setBiometricUnlock,
          secondary: const _SettingIconBadge(
            icon: Icons.fingerprint_rounded,
            color: AppTheme.revenue,
          ),
          title: Text(
            'Unlock with fingerprint'.tr,
            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
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
