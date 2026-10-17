import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/localization.dart';
import '../core/notifications/notify.dart';
import '../core/platform_info.dart';
import '../core/sms/sms_access.dart';
import '../data/repository.dart';
import 'widgets/widgets.dart';

/// One-time permissions introduction shown before the app opens for the first
/// time. Notifications and SMS inbox access are optional; the user can grant
/// either permission or skip the screen and enable access later when needed.
class PermissionsIntroPage extends StatefulWidget {
  const PermissionsIntroPage({super.key});

  @override
  State<PermissionsIntroPage> createState() => _PermissionsIntroPageState();
}

class _PermissionsIntroPageState extends State<PermissionsIntroPage> {
  bool? _notifyGranted;
  bool? _smsGranted;
  bool _busy = false;

  bool get _answered =>
      (!reminder.supported || _notifyGranted != null) &&
      (!isAndroidPlatform || _smsGranted != null);

  Future<void> _grantAll() async {
    final repo = context.read<AppRepository>();
    setState(() => _busy = true);

    var notify = _notifyGranted;
    var sms = _smsGranted;
    if (reminder.supported && notify == null) {
      try {
        notify = await reminder.requestPermission();
        await repo.refreshNotificationPermission();
      } catch (_) {
        notify = false;
      }
    }
    if (isAndroidPlatform && sms == null) {
      try {
        sms = await smsAccess.requestReadPermission();
      } catch (_) {
        sms = false;
      }
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _notifyGranted = notify;
      _smsGranted = sms;
    });
    // A denied request is not a dead end: SMS can be requested from its
    // review page later, and notifications can be enabled in Settings.
  }

  Future<void> _finish() async {
    final repo = context.read<AppRepository>();
    await repo.updateSettings(
      repo.settings.copyWith(permissionsIntroDone: true),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              children: [
                Icon(
                  Icons.privacy_tip_outlined,
                  size: 54,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  'Permissions'.tr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Notifications and SMS access are optional. You can sync recent messages or enable on-device alerts for new bank SMS. Matching messages enter review; no transaction is recorded until you approve it.'
                      .tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.7,
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 24),
                if (reminder.supported)
                  _PermissionRow(
                    icon: Icons.notifications_active_outlined,
                    title: 'Show notifications'.tr,
                    reason: 'For the daily expense reminder'.tr,
                    state: _notifyGranted,
                  ),
                if (isAndroidPlatform) ...[
                  if (reminder.supported) const SizedBox(height: 10),
                  _PermissionRow(
                    icon: Icons.sms_outlined,
                    title: 'Read bank SMS'.tr,
                    reason: _smsGranted == false
                        ? 'SMS access was not granted. You can enable it later from the SMS review page.'
                              .tr
                        : 'For syncing recent bank messages into review'.tr,
                    state: _smsGranted,
                  ),
                ],
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: _busy ? null : (_answered ? _finish : _grantAll),
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _answered
                              ? Icons.arrow_forward_rounded
                              : Icons.verified_user_outlined,
                          size: 19,
                        ),
                  label: Text(
                    (_answered ? 'Continue' : 'Grant permissions').tr,
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _busy ? null : _finish,
                  child: Text('Skip for now'.tr),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.title,
    required this.reason,
    this.state,
  });

  final IconData icon;
  final String title;
  final String reason;

  /// null = not answered yet, true = granted, false = denied.
  final bool? state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      true => const Color(0xFF16A34A),
      false => const Color(0xFFE11D48),
      null => Theme.of(context).colorScheme.primary,
    };
    return CardBox(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    reason,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.6,
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
            if (state != null) ...[
              const SizedBox(width: 8),
              Icon(
                state! ? Icons.check_circle_rounded : Icons.cancel_rounded,
                size: 20,
                color: color,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
