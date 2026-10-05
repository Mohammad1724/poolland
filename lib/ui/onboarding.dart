import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format_utils.dart';
import '../data/repository.dart';
import 'widgets/widgets.dart';

import '../core/localization.dart';

/// Initial setup: business name, opening balance, a fresh start, or sample data
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _name = TextEditingController(text: 'My VPN Business'.tr);
  final _cash = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _cash.dispose();
    super.dispose();
  }

  Future<void> _finish(AppRepository repo, {required bool demo}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final s = repo.settings.copyWith(
        businessName: _name.text.trim().isEmpty
            ? 'My VPN Business'.tr
            : _name.text.trim(),
        openingCash: parseAmount(_cash.text),
        setupDone: true,
      );
      await repo.updateSettings(s);
      if (demo) await repo.loadDemoData();
    } catch (e) {
      if (mounted) {
        showSnack(
          context,
          'Setup failed: {error}'.trArgs({'error': '$e'}),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 30),
          children: [
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: () => repo.updateSettings(
                  repo.settings.copyWith(
                    languageCode: repo.settings.languageCode == 'fa'
                        ? 'en'
                        : 'fa',
                  ),
                ),
                child: Text(
                  repo.settings.languageCode == 'fa' ? 'English' : 'فارسی',
                ),
              ),
            ),
            Center(
              child: Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.shield_moon_rounded,
                  size: 44,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Center(
              child: Text(
                'Poolland Ledger'.tr,
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Column(
                children: [
                  Text(
                    'A simple offline ledger for VPN sellers'.tr,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Customers, balances, subscriptions, and real profit — all in one place'
                        .tr,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.8,
                      color: onSurface.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            CardBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    controller: _name,
                    label: 'Business name'.tr,
                    icon: Icons.storefront_outlined,
                    hint: 'e.g. Alex VPN'.tr,
                  ),
                  const SizedBox(height: 14),
                  AmountField(
                    controller: _cash,
                    label: 'Opening cash balance (optional)'.tr,
                    currency: 'IRT',
                    validator: (_) => null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _feature(
              context,
              Icons.people_alt_outlined,
              'Manage customers and balances',
              'Track each customer’s sales, payments, and balance in one place',
            ),
            _feature(
              context,
              Icons.vpn_key_outlined,
              'Subscriptions and expiry dates',
              'Automatic expiry reminders and one-tap renewals',
            ),
            _feature(
              context,
              Icons.insights_outlined,
              'Real profit and reports',
              'Income, expenses, monthly profit, and top customers',
            ),
            _feature(
              context,
              Icons.currency_exchange_rounded,
              'Multiple currencies',
              'Toman, US dollars, USDT, and any currency you add',
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : () => _finish(repo, demo: false),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow_rounded),
              label: Text('Get started'.tr),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _finish(repo, demo: true),
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: Text('Try with sample data first'.tr),
            ),
            const SizedBox(height: 14),
            Center(
              child: Column(
                children: [
                  Text(
                    'All data stays on this device'.tr,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  Text(
                    'No account and no internet required'.tr,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.9,
                      color: onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _feature(
    BuildContext context,
    IconData icon,
    String title,
    String sub,
  ) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 17,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.tr,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub.tr,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
