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
import 'design.dart';
import '../data/repository.dart';
import 'forms/plan_edit_page.dart';
import 'lock/pin_setup_page.dart';
import 'sms_page.dart';
import 'sms_rules_page.dart';
import 'gesture_tour.dart';
import 'widgets/widgets.dart';

import '../core/localization.dart';

enum _NotificationSoundAction { systemDefault, phoneSound, audioFile }

/// The "Save" action of a small input dialog, disabled while the field holds
/// nothing usable.
///
/// These dialogs used to keep Save enabled and then quietly discard the
/// dialog when the field was empty: the tap did nothing, the dialog closed,
/// and nothing was saved or said. A disabled button that only wakes up when
/// there is something to save is the same rule the entry forms follow.
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
                            '${c.code} ${Fmt.number(c.rateToBase)}',
                      )
                      .join(' • '),
                  page: const RatesPage(),
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
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: s.smsNotify,
                    title: Text(
                      'Bank SMS notification'.tr,
                      style: TextStyle(fontSize: 13.5),
                    ),
                    subtitle: Text(
                      'Show a notification when a new bank SMS arrives, even if the app is closed'
                          .tr,
                      style: TextStyle(fontSize: 11.5),
                    ),
                    onChanged: (v) async {
                      if (v && isAndroidPlatform) {
                        // Android 13+ silently refuses to post notifications
                        // without this; a denied request returns false
                        // without a dialog, so the toggle still saves.
                        final ok = await reminder.requestPermission();
                        if (!ok && context.mounted) {
                          showSnack(
                            context,
                            'Notification permission is required for bank SMS alerts',
                          );
                        }
                      }
                      if (!context.mounted) return;
                      await repo.updateSettings(s.copyWith(smsNotify: v));
                    },
                  ),
                  if (isAndroidPlatform &&
                      s.smsNotify &&
                      !repo.notificationPermissionGranted) ...[
                    Divider(color: Theme.of(context).dividerColor),
                    _actionTile(
                      context,
                      icon: Icons.notification_important_outlined,
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
                  ],
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

          // ---------- Bank SMS (manual) ----------
          //
          // The safe APK declares no SMS permission, so Play Protect installs
          // it; the review page can still parse a message the user pastes.
          // Explaining the trade-off here keeps the missing switches from
          // looking like a bug.
          if (isAndroidPlatform && !repo.smsSupported) ...[
            const SectionTitle('Bank SMS (manual)', icon: Icons.sms_rounded),
            CardBox(
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.shield_outlined, size: 20),
                    title: Text(
                      'SMS reading is off in this build'.tr,
                      style: TextStyle(fontSize: 13.5),
                    ),
                    subtitle: Text(
                      'This build declares no SMS permission, so Google Play Protect installs it. Paste a bank SMS on the review page to record it.'
                          .tr,
                      style: TextStyle(fontSize: 11.5),
                    ),
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
                        : 'Paste a bank SMS to review it'.tr,
                    page: const SmsPage(),
                  ),
                  Divider(color: Theme.of(context).dividerColor),
                  _navTile(
                    context,
                    icon: Icons.tune_rounded,
                    title: 'Recognition rules'.tr,
                    subtitle:
                        'Choose which banks and phrases a pasted SMS can match.'
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
          CardBox(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.touch_app_outlined, size: 20),
              title: Text(
                'Gesture guide'.tr,
                style: const TextStyle(fontSize: 13.5),
              ),
              subtitle: Text(
                'See every swipe, hold and drag again'.tr,
                style: const TextStyle(fontSize: 11.5),
              ),
              onTap: () => showGestureTour(context),
            ),
          ),
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
          const SectionTitle('Backup and data', icon: Icons.cloud_sync_outlined),
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

          // ---------- Data actions (second card of Backup and data) ----------
          const SizedBox(height: 8),
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
          _saveWhen(
            ctrl,
            (v) => v.trim().isNotEmpty,
            () => Navigator.pop(ctx, ctrl.text.trim()),
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
          // A zero opening balance is a real value (start from nothing), so
          // only an empty field is refused here.
          _saveWhen(
            ctrl,
            (v) => v.trim().isNotEmpty,
            () => Navigator.pop(ctx, parseAmount(ctrl.text)),
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
          _saveWhen(
            ctrl,
            (v) => v.trim().isNotEmpty,
            () => Navigator.pop(
              ctx,
              parseAmount(ctrl.text).toInt().clamp(0, 60),
            ),
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
      // A backup restored onto a phone that never granted the permissions
      // must not pretend notifications work: ask for what the restored
      // settings now require, and refresh the displayed state either way.
      await repo.refreshSmsPermission();
      await repo.refreshNotificationPermission();
      if (repo.settings.smsEnabled && !repo.smsPermissionGranted) {
        await repo.requestSmsPermission();
      }
      if ((repo.settings.smsNotify || repo.settings.dailyReminder) &&
          !repo.notificationPermissionGranted) {
        await reminder.requestPermission();
        await repo.refreshNotificationPermission();
      }
      if (context.mounted) showSnack(context, 'Backup restored');
    } catch (e) {
      if (context.mounted) {
        showSnack(
          context,
          'Invalid file: {error}'.trArgs({
            // The store throws localized-key FormatExceptions; anything
            // else is shown as-is for support.
            'error': e is FormatException ? e.message.tr : '$e',
          }),
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
                              ? 'Base currency'.tr
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
          _saveWhen(
            ctrl,
            (v) => parseAmount(v) > 0,
            () => Navigator.pop(ctx, parseAmount(ctrl.text)),
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
                decoration: InputDecoration(labelText: 'Code (e.g. AED)'.tr),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: name,
                decoration: InputDecoration(labelText: 'Name'.tr),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: symbol,
                decoration: InputDecoration(labelText: 'Symbol'.tr),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: rate,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Rate in Toman'.tr,
                  suffixText: 'Toman'.tr,
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
          // A currency needs a code, a name and a real exchange rate: with a
          // rate of zero every amount in it converts to nothing. The dialog
          // used to accept all three mistakes and then throw the result away
          // without a word.
          AnimatedBuilder(
            animation: Listenable.merge([code, name, rate]),
            builder: (context, child) {
              final valid = code.text.trim().isNotEmpty &&
                  name.text.trim().isNotEmpty &&
                  parseAmount(rate.text) > 0;
              return FilledButton(
                onPressed: valid ? () => Navigator.pop(ctx, true) : null,
                child: Text('Add'.tr),
              );
            },
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
                minimumSize: const Size(0, Taps.minHeight),
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

  /// The category list: a parent and, right under it, its subcategories
  /// (indented). Orphans — whose parent was deleted — sit at the top.
  Widget _list(BuildContext context, TxnKind kind) {
    final repo = context.watch<AppRepository>();
    final all = repo.categoriesOf(kind, scope: _scope)
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final byId = {for (final c in all) c.id: c};
    // Pass one: who is under whom. Pass two: parents, then their children.
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
        (childrenOf[t.id] ?? const <Category>[])
            .map((k) => _CatRow(k, child: true)),
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
            tooltip: 'Edit'.tr,
            icon: const Icon(Icons.edit_outlined, size: 18),
            onPressed: () => _categoryDialog(context, kind, existing: c),
          ),
          IconButton(
            tooltip: 'Delete'.tr,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
            onPressed: () async {
              final hasChildren = repo.categoriesOf(
                kind,
                scope: c.scope,
              ).any((k) => k.parentId == c.id);
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

  /// The one dialog for creating and editing a category: its name and,
  /// optionally, the top-level category it lives under.
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
    final initialParent = existing?.parentId;
    final draft = await showDialog<_CategoryDraft>(
      context: context,
      builder: (ctx) {
        final nameCtrl = TextEditingController(text: existing?.name ?? '');
        String? parentValue = (initialParent == null ||
                !tops.any((t) => t.id == initialParent))
            ? ''
            : initialParent;
        return StatefulBuilder(
          builder: (ctx, setDialog) => AlertDialog(
            title: Text(
              existing == null
                  ? (kind == TxnKind.income
                      ? 'New income category'.tr
                      : 'New expense category'.tr)
                  : 'Edit category'.tr,
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: existing == null,
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
                    initialValue: parentValue,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    items: [
                      DropdownMenuItem<String?>(
                        value: '',
                        child: Text('Top-level category'.tr),
                      ),
                      for (final t in tops)
                        DropdownMenuItem<String?>(
                          value: t.id,
                          child: Text(t.name.tr),
                        ),
                    ],
                    onChanged: (v) => setDialog(() => parentValue = v ?? ''),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Cancel'.tr),
              ),
              // A category with no name has nothing to show in the picker.
              // Save used to stay live and silently refuse; it now wakes up
              // as soon as there is a name to save.
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: nameCtrl,
                builder: (context, value, child) => FilledButton(
                  onPressed: value.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(
                          ctx,
                          _CategoryDraft(
                            name: nameCtrl.text.trim(),
                            parentId: parentValue,
                          ),
                        ),
                  child: Text(existing == null ? 'Add'.tr : 'Save'.tr),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (draft == null) return;
    final rawParent = draft.parentId;
    final parentId = (rawParent == null || rawParent.isEmpty)
        ? null
        : rawParent;
    if (existing == null) {
      await repo.addCategory(draft.name, kind, scope: _scope, parentId: parentId);
    } else {
      // Rename first, then move: each write reloads the in-memory list, so
      // the second write must not carry the first write's stale parent.
      await repo.renameCategory(existing, draft.name);
      await repo.setCategoryParent(existing.id, parentId);
    }
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
  const _CategoryDraft({required this.name, required this.parentId});
  final String name;
  final String? parentId;
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
