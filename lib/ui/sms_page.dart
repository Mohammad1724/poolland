import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/format_utils.dart';
import '../core/jalali_utils.dart';
import '../core/money.dart';
import '../core/notifications/notify.dart';
import '../core/platform_info.dart';
import '../core/sms/sms_access.dart';
import '../core/sms/sms_models.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'design.dart';
import 'motion_kit.dart';
import 'forms/transaction_edit_page.dart';
import 'sms_rules_page.dart';
import 'widgets/widgets.dart';

import '../core/localization.dart';
import 'forms/sms_review_sheet.dart';

/// ============================================================
///  Bank SMS — inbox sync, review, and approval queue
///
///  Android inbox sync is opt-in through READ_SMS. New-message alerts are a
///  separate RECEIVE_SMS opt-in. Matching transactions enter the review queue,
///  and nothing is recorded until the user approves it. Pasting remains
///  available if SMS access is declined.
/// ============================================================
class SmsPage extends StatefulWidget {
  const SmsPage({super.key, this.openReviewKey});

  /// Opens this queued message's approval sheet after a notification tap.
  final String? openReviewKey;

  @override
  State<SmsPage> createState() => _SmsPageState();
}

enum _SmsFilter { all, deposit, withdraw }
enum _HistoryFilter { all, recorded, rejected }

class _SmsPageState extends State<SmsPage> with WidgetsBindingObserver {
  _SmsFilter _filter = _SmsFilter.all;
  _HistoryFilter _historyFilter = _HistoryFilter.all;
  bool? _smsPermissionGranted;
  bool _checkingPermission = true;
  bool _syncing = false;
  bool _arrivalNotificationsEnabled = false;
  bool _loadingArrivalNotifications = true;
  bool _updatingArrivalNotifications = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (isAndroidPlatform) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        await _checkPermission(syncWhenGranted: widget.openReviewKey == null);
        if (!mounted) return;
        await _loadArrivalNotifications();
        if (!mounted) return;
        if (widget.openReviewKey != null) await _openInitialReview();
      });
    } else {
      _checkingPermission = false;
      _loadingArrivalNotifications = false;
      if (widget.openReviewKey != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_openInitialReview());
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && isAndroidPlatform) {
      unawaited(_checkPermission(syncWhenGranted: true));
      unawaited(_loadArrivalNotifications());
    }
  }

  Future<void> _checkPermission({bool syncWhenGranted = false}) async {
    if (!mounted || _syncing) return;
    setState(() => _checkingPermission = true);
    final granted = await smsAccess.hasReadPermission();
    if (!mounted) return;
    setState(() {
      _smsPermissionGranted = granted;
      _checkingPermission = false;
    });
    if (granted && syncWhenGranted) {
      await _syncInbox(showResult: false);
    }
  }

  Future<void> _loadArrivalNotifications() async {
    if (!mounted) return;
    final repo = context.read<AppRepository>();
    final enabled = await smsAccess.arrivalNotificationsEnabled();
    final receiveGranted = await smsAccess.hasReceivePermission();
    final notificationsGranted = await repo.refreshNotificationPermission();
    var canRemainEnabled = enabled && receiveGranted && notificationsGranted;
    if (enabled) {
      if (canRemainEnabled) {
        canRemainEnabled =
            await smsAccess.setArrivalNotificationsEnabled(true);
      }
      if (!canRemainEnabled) {
        await smsAccess.setArrivalNotificationsEnabled(false);
      }
    }
    if (!mounted) return;
    setState(() {
      _arrivalNotificationsEnabled = canRemainEnabled;
      _loadingArrivalNotifications = false;
    });
  }

  Future<void> _setArrivalNotifications(bool enabled) async {
    if (_updatingArrivalNotifications) return;
    setState(() => _updatingArrivalNotifications = true);
    try {
      if (!enabled) {
        await smsAccess.setArrivalNotificationsEnabled(false);
        if (mounted) {
          setState(() => _arrivalNotificationsEnabled = false);
          showSnack(context, 'Bank SMS notifications turned off.');
        }
        return;
      }

      final repo = context.read<AppRepository>();
      var notificationsGranted = await repo.refreshNotificationPermission();
      if (!notificationsGranted) {
        await reminder.requestPermission();
        notificationsGranted = await repo.refreshNotificationPermission();
      }
      if (!notificationsGranted) {
        if (mounted) {
          showSnack(
            context,
            'Notification permission denied. Enable it in Android settings.',
            error: true,
            actionLabel: 'Open app settings',
            onAction: () => smsAccess.openAppSettings(),
          );
        }
        return;
      }

      final receiveGranted = await smsAccess.requestReceivePermission();
      if (!receiveGranted) {
        if (mounted) {
          showSnack(
            context,
            'Incoming SMS permission denied. Enable it in Android settings.',
            error: true,
            actionLabel: 'Open app settings',
            onAction: () => smsAccess.openAppSettings(),
          );
        }
        return;
      }

      final rules = repo.activeSmsRules;
      await smsAccess.syncArrivalRules(
        senderHints: rules.expand((rule) => rule.senderHints).toList(),
        bodyHints: rules.expand((rule) => rule.bodyHints).toList(),
      );
      final saved = await smsAccess.setArrivalNotificationsEnabled(true);
      if (!saved) {
        if (mounted) {
          showSnack(
            context,
            'Could not enable bank SMS notifications.',
            error: true,
          );
        }
        return;
      }
      if (mounted) {
        setState(() => _arrivalNotificationsEnabled = true);
        showSnack(context, 'Bank SMS notifications enabled.');
      }
    } catch (_) {
      if (mounted) {
        showSnack(
          context,
          'Could not enable bank SMS notifications.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _updatingArrivalNotifications = false);
    }
  }

  Future<void> _openInitialReview() async {
    final reviewKey = widget.openReviewKey;
    if (!mounted || reviewKey == null) return;
    final repo = context.read<AppRepository>();
    final sms = repo.smsSuggestions
        .where((item) => item.key == reviewKey)
        .firstOrNull;
    if (sms == null) {
      showSnack(context, 'This SMS is no longer waiting for review.');
      // The page was opened for a suggestion that has already been handled;
      // leaving it here would be a dead end.
      if (mounted) Navigator.maybePop(context);
      return;
    }
    final ok = await showLedgerSheet<bool>(
      context,
      builder: (_) => SmsReviewSheet(
        sms: sms,
        initialCustomer: repo.matchCustomerForSms(sms),
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      showSnack(context, 'Transaction recorded from SMS');
      // The notification opened this page only to review this one item; once
      // it is recorded the page has nothing else to do.
      Navigator.maybePop(context);
    }
  }

  Future<void> _syncInbox({bool showResult = true}) async {
    if (_syncing) return;
    final repo = context.read<AppRepository>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _syncing = true);
    try {
      var granted = _smsPermissionGranted ?? false;
      if (!granted) {
        granted = await smsAccess.requestReadPermission();
        if (!mounted) return;
        setState(() => _smsPermissionGranted = granted);
      }
      if (!granted) {
        if (showResult) {
          showMessengerSnack(
            messenger,
            'SMS permission denied. Enable it in Android settings or keep using paste.',
            error: true,
            actionLabel: 'Open app settings',
            onAction: () => smsAccess.openAppSettings(),
          );
        }
        return;
      }

      final messages = await smsAccess.readInbox();
      final added = repo.importInboxSms(messages);
      if (!mounted || !showResult) return;
      showMessengerSnack(
        messenger,
        added > 0
            ? '{count} bank messages added to review'.trArgs({
                'count': added,
              })
            : 'No new transaction messages found. Tap Sync to check recent messages.',
      );
    } on PlatformException {
      if (mounted && showResult) {
        showMessengerSnack(
          messenger,
          'Could not read SMS. Please try again.',
          error: true,
        );
      }
    } catch (_) {
      if (mounted && showResult) {
        showMessengerSnack(
          messenger,
          'Could not read SMS. Please try again.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final onSurface = Theme.of(context).colorScheme.onSurface;

    if (!isAndroidPlatform) {
      return Scaffold(
        appBar: AppBar(title: Text('Bank SMS'.tr)),
        body: const EmptyState(
          icon: Icons.sms_outlined,
          title: 'Android only',
          text: 'SMS access is not available on web or desktop. Try this feature on an Android phone.',
        ),
      );
    }

    final all = repo.smsSuggestions;
    final list = switch (_filter) {
      _SmsFilter.all => all,
      _SmsFilter.deposit =>
        all.where((s) => s.direction == SmsDirection.deposit).toList(),
      _SmsFilter.withdraw =>
        all.where((s) => s.direction == SmsDirection.withdraw).toList(),
    };

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Bank SMS'.tr),
          actions: [
            IconButton(
              tooltip: 'Manage recognition rules'.tr,
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SmsRulesPage()),
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'reject_all':
                    final ok = await confirmDialog(
                      context,
                      title: 'Reject all'.tr,
                      message: 'Reject all suggestions? (They will no longer appear, but no transactions will be deleted.)'
                          .tr,
                      okLabel: 'Reject'.tr,
                      danger: true,
                    );
                    if (!ok || !context.mounted) break;
                    final messenger = ScaffoldMessenger.of(context);
                    await repo.rejectAllSms();
                    // The queue empties itself, which can look like a glitch
                    // unless the app says what happened.
                    showMessengerSnack(messenger, 'All suggestions rejected');
                    break;
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'reject_all', child: Text('Reject all'.tr)),
              ],
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(
                text: 'Unregistered ({count})'.trArgs({
                  'count': all.length,
                }),
              ),
              Tab(
                text: 'Review history ({count})'.trArgs({
                  'count': repo.smsHistory.length,
                }),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _pendingTab(context, repo, all, list, onSurface),
            _historyTab(context, repo),
          ],
        ),
      ),
    );
  }

  Widget _pendingTab(
    BuildContext context,
    AppRepository repo,
    List<ParsedSms> all,
    List<ParsedSms> list,
    Color onSurface,
  ) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
    children: [
      _summaryCard(context, all.length),
      const SizedBox(height: 10),
      Text(
        _smsPermissionGranted == true
            ? 'Sync recent bank messages on this device. Matching messages enter review; nothing is recorded until you approve it.'
                  .tr
            : 'Grant SMS access to sync recent bank messages. You can still paste a message manually.'
                  .tr,
        style: TextStyle(
          fontSize: 12,
          height: 1.6,
          color: onSurface.withValues(alpha: 0.68),
        ),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          onPressed: (_checkingPermission || _syncing)
              ? null
              : () => _syncInbox(),
          icon: _syncing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _smsPermissionGranted == true
                      ? Icons.sync_rounded
                      : Icons.lock_open_rounded,
                  size: 18,
                ),
          label: Text(
            _syncing
                ? 'Syncing…'.tr
                : _checkingPermission
                    ? 'Checking SMS access…'.tr
                    : _smsPermissionGranted == true
                        ? 'Sync bank SMS'.tr
                        : 'Grant SMS access'.tr,
          ),
        ),
      ),
      const SizedBox(height: 4),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _importSms(context, repo),
          icon: const Icon(Icons.content_paste_rounded, size: 18),
          label: Text('Add from SMS text'.tr),
        ),
      ),
      const SizedBox(height: 10),
      CardBox(
        child: SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _arrivalNotificationsEnabled,
          onChanged: (_loadingArrivalNotifications ||
                  _updatingArrivalNotifications)
              ? null
              : _setArrivalNotifications,
          secondary: _updatingArrivalNotifications
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.notifications_active_outlined),
          title: Text('Notify me about new bank SMS'.tr),
          subtitle: Text(
            'New messages are checked on this device against enabled bank rules. Matching transaction messages send a private notification; nothing is recorded until you approve it.'
                .tr,
            style: const TextStyle(fontSize: 11.5, height: 1.45),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          _chip('All', _SmsFilter.all, all.length),
          const SizedBox(width: 8),
          _chip(
            'Deposit',
            _SmsFilter.deposit,
            all.where((s) => s.direction == SmsDirection.deposit).length,
          ),
          const SizedBox(width: 8),
          _chip(
            'Withdrawal',
            _SmsFilter.withdraw,
            all.where((s) => s.direction == SmsDirection.withdraw).length,
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (list.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 40),
          child: EmptyState(
            icon: Icons.sms_outlined,
            title: 'No items found',
            text: _smsPermissionGranted == true
                ? 'No new transaction messages found. Tap Sync to check recent messages.'
                : 'Grant SMS access to sync recent bank messages. You can still paste a message manually.',
          ),
        )
      else
        for (final (i, sms) in list.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SlipIn(index: i, child: _SmsCard(sms: sms, onSurface: onSurface)),
          ),
    ],
  );

  /// Asks for a pasted bank message and queues it for review.
  ///
  /// Every outcome gets its own message: a queued card is visible, but a
  /// duplicate or a non-transaction paste must say why nothing appeared.
  Future<void> _importSms(BuildContext context, AppRepository repo) async {
    final text = await showLedgerSheet<String>(
      context,
      builder: (_) => const _ImportSmsSheet(),
    );
    if (text == null || !context.mounted) return;
    final result = repo.importSmsText(text);
    if (!context.mounted) return;
    switch (result) {
      case SmsImportResult.added:
        showSnack(context, 'SMS added to review');
        break;
      case SmsImportResult.duplicate:
        showSnack(
          context,
          'This message is already in the review queue',
          error: true,
        );
        break;
      case SmsImportResult.notRecognized:
        showSnack(
          context,
          'No transaction found in this text',
          error: true,
        );
        break;
    }
  }

  Widget _historyTab(BuildContext context, AppRepository repo) {
    final history = repo.smsHistory;
    final visible = switch (_historyFilter) {
      _HistoryFilter.all => history,
      _HistoryFilter.recorded => history.where((e) => e.wasRecorded).toList(),
      _HistoryFilter.rejected => history.where((e) => e.wasRejected).toList(),
    };

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
      children: [
        CardBox(
          child: Text(
            'Reviewed SMS history is kept in this app’s storage and omitted from its export/restore files. Recorded entries can be opened from here; rejected messages do not create transactions. Older status-only records may not be displayable.'
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
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _historyChip('All', _HistoryFilter.all, history.length),
            _historyChip(
              'Recorded',
              _HistoryFilter.recorded,
              history.where((e) => e.wasRecorded).length,
            ),
            _historyChip(
              'Rejected',
              _HistoryFilter.rejected,
              history.where((e) => e.wasRejected).length,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 35),
            child: EmptyState(
              icon: Icons.history_rounded,
              title: 'No review history yet',
              text: 'Approved or rejected SMS messages will appear here.',
            ),
          )
        else
          for (final entry in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SmsHistoryCard(entry: entry),
            ),
      ],
    );
  }

  Widget _historyChip(String label, _HistoryFilter filter, int count) =>
      ChoiceChip(
        label: Text('${label.tr} ($count)'),
        showCheckmark: false,
        selected: _historyFilter == filter,
        onSelected: (_) => setState(() => _historyFilter = filter),
      );

  Widget _chip(String label, _SmsFilter f, int count) => ChoiceChip(
    label: Text(count > 0 ? '${label.tr} ($count)' : label.tr),
    showCheckmark: false,
    selected: _filter == f,
    onSelected: (_) => setState(() => _filter = f),
  );

  Widget _summaryCard(BuildContext context, int count) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final subtitle =
        'SMS stays on this device. Review each matched message before recording it.'
            .tr;
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sms_rounded, size: 18),
              const SizedBox(width: 8),
              Text(
                count > 0
                    ? '{count} transactions awaiting review'.trArgs({
                        'count': count,
                      })
                    : 'Nothing awaiting review'.tr,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11.5,
              color: onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

}

/// ---------------- SMS card ----------------
class _SmsCard extends StatelessWidget {
  const _SmsCard({required this.sms, required this.onSurface});

  final ParsedSms sms;
  final Color onSurface;

  Color get _color => switch (sms.direction) {
    SmsDirection.deposit => const Color(0xFF16A34A),
    SmsDirection.withdraw => const Color(0xFFE11D48),
    SmsDirection.unknown => const Color(0xFFF59E0B),
  };

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final matched = repo.matchCustomerForSms(sms);

    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  sms.direction == SmsDirection.deposit
                      ? Icons.call_received_rounded
                      : Icons.call_made_rounded,
                  size: 18,
                  color: _color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (sms.bankName ??
                              (sms.manual ? 'Pasted message' : 'Unknown bank'))
                          .tr,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${J.d(sms.message.date)} · ${Fmt.clock(sms.message.date)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${sms.direction == SmsDirection.deposit ? '+' : '−'}'
                    '${Money.text(sms.amount, currency: sms.currency)}',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: _color,
                    ),
                  ),
                  const SizedBox(height: 3),
                  TagChip(sms.direction.label, color: _color, dense: true),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (sms.cardMask != null)
                TagChip(
                  'Card {card}'.trArgs({'card': sms.cardMask}),
                  color: const Color(0xFF7C3AED),
                  dense: true,
                ),
              if (sms.reference != null)
                TagChip(
                  'Reference {reference}'.trArgs({'reference': sms.reference}),
                  color: const Color(0xFF0F766E),
                  dense: true,
                ),
              if (sms.balance != null)
                TagChip(
                  'Balance {balance}'.trArgs({
                    'balance': Money.text(sms.balance!, compact: true),
                  }),
                  color: const Color(0xFF2563EB),
                  dense: true,
                ),
              if (matched != null && sms.direction == SmsDirection.deposit)
                if (repo.balanceOf(matched) > 0.5)
                  TagChip(
                    'Suggested: Debt settlement',
                    color: const Color(0xFF0F766E),
                    dense: true,
                  )
                else if (repo.activeSubsOfCustomer(matched.id).isNotEmpty)
                  TagChip(
                    'Suggested: Subscription renewal',
                    color: const Color(0xFF4F46E5),
                    dense: true,
                  ),
            ],
          ),
          if (matched != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.person_outline_rounded, size: 15),
                const SizedBox(width: 5),
                Text(
                  matched.name,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '(Auto-matched)'.tr,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            sms.message.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.6,
              color: onSurface.withValues(alpha: 0.6),
            ),
          ),
          if (sms.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              sms.note,
              style: const TextStyle(fontSize: 10.5, color: Color(0xFFB45309)),
            ),
          ],
          if (sms.bankName == null) ...[
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        SmsRuleEditPage(initialMessage: sms.message),
                  ),
                ),
                icon: const Icon(Icons.add_moderator_outlined, size: 16),
                label: Text(
                  'Create recognition rule'.tr,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  // Rejecting removes the card from the queue, so without a
                  // word it looks like the card vanished. Say so.
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await repo.rejectSms(sms);
                    showMessengerSnack(messenger, 'SMS rejected');
                  },
                  icon: const Icon(Icons.close_rounded, size: 17),
                  label: Text('Reject'.tr),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () => _openReview(context, sms, matched),
                  icon: const Icon(Icons.check_rounded, size: 17),
                  label: Text(
                    (matched == null ? 'Review and record' : 'Confirm').tr,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openReview(
    BuildContext context,
    ParsedSms sms,
    Customer? matched,
  ) async {
    final ok = await showLedgerSheet<bool>(
      context,
      builder: (ctx) => SmsReviewSheet(sms: sms, initialCustomer: matched),
    );
    if (ok == true && context.mounted) {
      final repo = context.read<AppRepository>();
      final nextSms = repo.smsSuggestions.firstOrNull;
      if (nextSms != null) {
        showSnack(
          context,
          'Transaction recorded from SMS',
          actionLabel: 'Next SMS',
          onAction: () =>
              _openReview(context, nextSms, repo.matchCustomerForSms(nextSms)),
        );
      } else {
        showSnack(context, 'Transaction recorded from SMS');
      }
    }
  }
}

class _SmsHistoryCard extends StatelessWidget {
  const _SmsHistoryCard({required this.entry});

  final SmsHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppRepository>();
    final recorded = entry.wasRecorded;
    final statusColor = recorded
        ? const Color(0xFF16A34A)
        : const Color(0xFF64748B);
    final directionColor = entry.direction == SmsDirection.deposit
        ? const Color(0xFF16A34A)
        : const Color(0xFFE11D48);
    final title = entry.bankName?.isNotEmpty == true
        ? entry.bankName!.tr
        : entry.message.address.isNotEmpty
        ? entry.message.address
        : 'Pasted message'.tr;
    Txn? transaction;
    if (entry.transactionId != null) {
      for (final item in repo.transactions) {
        if (item.id == entry.transactionId) {
          transaction = item;
          break;
        }
      }
    }
    final transactionToOpen = transaction;

    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                recorded ? Icons.check_circle_outline : Icons.block_outlined,
                color: statusColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty ? 'Unknown sender'.tr : title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Received {received} · reviewed {reviewed}'.trArgs({
                        'received': '${J.d(entry.message.date)} · ${Fmt.clock(entry.message.date)}',
                        'reviewed': '${J.d(entry.reviewedAt)} · ${Fmt.clock(entry.reviewedAt)}',
                      }),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              if (entry.amount > 0)
                Text(
                  '${entry.direction == SmsDirection.deposit ? '+' : '−'}'
                  '${Money.text(entry.amount, currency: entry.currency)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: directionColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              TagChip(
                recorded ? 'Recorded'.tr : 'Rejected'.tr,
                color: statusColor,
                dense: true,
              ),
              if (entry.direction != SmsDirection.unknown)
                TagChip(
                  entry.direction.label,
                  color: directionColor,
                  dense: true,
                ),
              if (transactionToOpen != null &&
                  transactionToOpen.categoryId != null)
                TagChip(
                  repo.categoryName(transactionToOpen.categoryId),
                  color: const Color(0xFF4F46E5),
                  dense: true,
                ),
              if (transactionToOpen != null &&
                  transactionToOpen.customerId != null)
                TagChip(
                  repo.customerName(transactionToOpen.customerId),
                  color: const Color(0xFF0F766E),
                  dense: true,
                ),
            ],
          ),
          if (transactionToOpen != null &&
              transactionToOpen.note.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              transactionToOpen.note.tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            entry.message.body,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.55,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.68),
            ),
          ),
          if (entry.wasRejected) ...[
            const SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  await context.read<AppRepository>().restoreRejectedSms(entry);
                  showMessengerSnack(
                    messenger,
                    'SMS returned to review queue',
                  );
                },
                icon: const Icon(Icons.restore_rounded, size: 16),
                label: Text('Return to review queue'.tr),
              ),
            ),
          ],
          if (entry.transactionId != null) ...[
            const SizedBox(height: 6),
            if (transactionToOpen != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TransactionEditPage(
                        existing: transactionToOpen,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text('Open transaction'.tr),
                ),
              )
            else
              Row(
                children: [
                  const Icon(Icons.receipt_long_outlined, size: 15),
                  const SizedBox(width: 5),
                  Text(
                    'Transaction recorded'.tr,
                    style: const TextStyle(fontSize: 10.5),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
/// one message without syncing the device inbox.
class _ImportSmsSheet extends StatefulWidget {
  const _ImportSmsSheet();

  @override
  State<_ImportSmsSheet> createState() => _ImportSmsSheetState();
}

class _ImportSmsSheetState extends State<_ImportSmsSheet> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty || !mounted) return;
    setState(() {
      _text.text = text;
      _text.selection = TextSelection.collapsed(offset: text.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final canAdd = _text.text.trim().isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHandle(),
            const SizedBox(height: 16),
            Text(
              'Add from SMS text'.tr,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Copy a bank SMS and paste it here. It is parsed on this device and only added to the review queue.'
                  .tr,
              style: TextStyle(
                fontSize: 12,
                height: 1.7,
                color: onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              minLines: 4,
              maxLines: 8,
              textAlignVertical: TextAlignVertical.top,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Bank SMS text'.tr,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: Text('Paste'.tr),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: canAdd
                      ? () => Navigator.pop(context, _text.text.trim())
                      : null,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text('Add to review'.tr),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
