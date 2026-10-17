import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/localization.dart';
import '../core/notifications/notify.dart';
import '../data/repository.dart';
import 'widgets/widgets.dart';

/// One-time permissions gate shown on the very first app open (and after a
/// backup restore onto a fresh install, where the restored settings claim
/// notifications while no permission was ever granted here).
///
/// The user answers once — grant or skip — and only then does the real app
/// open, so nothing silently runs without the permissions it needs.
///
/// The app asks for one permission only: the notification permission behind
/// the daily reminder. It has no SMS permission at all, so there is nothing
/// to ask about reading messages.
class PermissionsIntroPage extends StatefulWidget {
  const PermissionsIntroPage({super.key});

  @override
  State<PermissionsIntroPage> createState() => _PermissionsIntroPageState();
}

class _PermissionsIntroPageState extends State<PermissionsIntroPage> {
  bool? _notifyGranted;
  bool _busy = false;

  bool get _answered => !reminder.supported || _notifyGranted != null;

  Future<void> _grantAll() async {
    final repo = context.read<AppRepository>();
    setState(() => _busy = true);
    bool? notify;
    if (reminder.supported) {
      notify = await reminder.requestPermission();
      await repo.refreshNotificationPermission();
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _notifyGranted = notify;
    });
    // A denied request is not a dead end: the toggles in Settings ask again,
    // and the primary button now just continues into the app.
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
                  'Required permissions'.tr,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Poolland uses notifications for the daily reminder. You can skip now and grant it later from Settings.'
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
