import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format_utils.dart';
import '../core/jalali_utils.dart';
import '../core/localization.dart';
import '../core/money.dart';
import '../core/sms/sms_models.dart';
import '../core/sms/sms_parser.dart';
import '../data/repository.dart';
import 'sms_rules_page.dart';
import 'widgets/widgets.dart';

/// Transaction-shaped SMS messages that did not match an active recognition
/// rule. Adding a rule only moves future matches into manual review.
class UnrecognizedSmsPage extends StatefulWidget {
  const UnrecognizedSmsPage({super.key});

  @override
  State<UnrecognizedSmsPage> createState() => _UnrecognizedSmsPageState();
}

class _UnrecognizedSmsPageState extends State<UnrecognizedSmsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final repo = context.read<AppRepository>();
      repo.initSms();
      final allowed = await repo.refreshSmsPermission();
      if (allowed) await repo.scanUnrecognizedSms(force: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    if (!repo.smsSupported) {
      return Scaffold(
        appBar: AppBar(title: Text('Unrecognized SMS'.tr)),
        body: const EmptyState(
          icon: Icons.sms_outlined,
          title: 'Android only',
          text: 'SMS access is not available on web or desktop. Try this feature on an Android phone.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Unrecognized SMS'.tr),
        actions: [
          IconButton(
            tooltip: 'Scan again'.tr,
            onPressed: repo.smsUnrecognizedBusy
                ? null
                : () => repo.scanUnrecognizedSms(force: true),
            icon: repo.smsUnrecognizedBusy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded),
          ),
        ],
      ),
      body: !repo.smsPermissionGranted
          ? _permissionView(context, repo)
          : RefreshIndicator(
              onRefresh: () async {
                await repo.scanUnrecognizedSms(force: true);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                children: [
                  CardBox(
                    child: Text(
                      'These messages look like deposits or withdrawals but do not match an enabled rule. Create a sender or phrase rule to add matching messages to manual review. Nothing is recorded automatically.'
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
                  if (repo.smsUnrecognizedMessages.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 26),
                      child: EmptyState(
                        icon: Icons.mark_email_read_outlined,
                        title: repo.smsUnrecognizedBusy
                            ? 'Checking SMS...'
                            : 'No unrecognized transaction SMS found',
                        text: repo.smsUnrecognizedBusy
                            ? 'Please wait'
                            : 'Try scanning again after receiving a bank or payment-service SMS.',
                      ),
                    )
                  else
                    for (final message in repo.smsUnrecognizedMessages)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _UnrecognizedSmsCard(message: message),
                      ),
                ],
              ),
            ),
    );
  }

  Widget _permissionView(BuildContext context, AppRepository repo) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      CardBox(
        child: Column(
          children: [
            Text(
              'SMS access is needed to scan for unrecognized messages. Messages are read on this device only.'
                  .tr,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, height: 1.6),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () async {
                final allowed = await repo.requestSmsPermission();
                if (allowed) await repo.scanUnrecognizedSms(force: true);
              },
              icon: const Icon(Icons.sms_rounded),
              label: Text('Grant SMS access'.tr),
            ),
          ],
        ),
      ),
    ],
  );
}

class _UnrecognizedSmsCard extends StatelessWidget {
  const _UnrecognizedSmsCard({required this.message});

  final SmsMessage message;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final parsed = SmsParser.parse(
      message,
      extraRules: repo.smsRules,
      disabledRuleIds: repo.settings.disabledSmsRuleIds.toSet(),
    );
    final isDeposit = parsed.direction == SmsDirection.deposit;
    final color = isDeposit
        ? const Color(0xFF16A34A)
        : const Color(0xFFE11D48);

    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sms_outlined, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.address.isEmpty
                          ? 'Unknown sender'.tr
                          : message.address,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '${J.d(message.date)} · ${Fmt.clock(message.date)}',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              if (parsed.isPotentialUnrecognizedTransaction)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      Money.text(parsed.amount, currency: parsed.currency),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    Text(
                      parsed.direction.label,
                      style: TextStyle(fontSize: 10, color: color),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message.body,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.55,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                final saved = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SmsRuleEditPage(initialMessage: message),
                  ),
                );
                if (saved == true && context.mounted) {
                  await repo.scanUnrecognizedSms(force: true);
                }
              },
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: Text('Create recognition rule'.tr),
            ),
          ),
        ],
      ),
    );
  }
}
