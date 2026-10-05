import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format_utils.dart';
import '../data/repository.dart';
import 'widgets/widgets.dart';

/// راه‌اندازی اولیه: نام کسب‌وکار، موجودی اولیه، شروع تازه یا داده‌ی نمونه
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _name = TextEditingController(text: 'فروش وی‌پی‌ان من');
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
        businessName: _name.text.trim().isEmpty ? 'فروش وی‌پی‌ان من' : _name.text.trim(),
        openingCash: parseAmount(_cash.text),
        setupDone: true,
      );
      await repo.updateSettings(s);
      if (demo) await repo.loadDemoData();
    } catch (e) {
      if (mounted) {
        showSnack(context, 'راه‌اندازی انجام نشد: $e', error: true);
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
          padding: const EdgeInsets.fromLTRB(22, 30, 22, 30),
          children: [
            Center(
              child: Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(Icons.shield_moon_rounded,
                    size: 44, color: theme.colorScheme.primary),
              ),
            ),
            const SizedBox(height: 18),
            const Center(
              child: Text('دفتر وی‌پی‌ان',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'دفتر حسابداری ساده و آفلاین برای فروشندگان VPN\nمشتری‌ها، بدهی‌ها، اشتراک‌ها و سود واقعی — همه در یک جا',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12.5, height: 2, color: onSurface.withValues(alpha: 0.65)),
              ),
            ),
            const SizedBox(height: 26),
            CardBox(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppTextField(
                    controller: _name,
                    label: 'نام کسب‌وکار',
                    icon: Icons.storefront_outlined,
                    hint: 'مثلاً: VPN علی',
                  ),
                  const SizedBox(height: 14),
                  AmountField(
                    controller: _cash,
                    label: 'موجودی اولیه صندوق (اختیاری)',
                    currency: 'IRT',
                    validator: (_) => null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _feature(context, Icons.people_alt_outlined, 'مدیریت مشتری‌ها و بدهی‌ها',
                'هر فروش، دریافت و مانده‌حساب مشتری در یک صفحه'),
            _feature(context, Icons.vpn_key_outlined, 'اشتراک‌ها و تاریخ انقضا',
                'هشدار خودکار برای سرویس‌های نزدیک انقضا و تمدید یک‌کلیکی'),
            _feature(context, Icons.insights_outlined, 'سود واقعی و گزارش‌ها',
                'درآمد، هزینه، سود ماهانه و برترین مشتری‌ها'),
            _feature(context, Icons.currency_exchange_rounded, 'پشتیبانی چند ارز',
                'تومان، دلار، تتر و هر ارزی که خودت اضافه کنی'),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _busy ? null : () => _finish(repo, demo: false),
              icon: _busy
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow_rounded),
              label: const Text('شروع می‌کنم'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _finish(repo, demo: true),
              icon: const Icon(Icons.auto_awesome_outlined, size: 18),
              label: const Text('اول با داده‌ی نمونه امتحان کنم'),
            ),
            const SizedBox(height: 14),
            Center(
              child: Text(
                'همه‌ی اطلاعات فقط روی همین دستگاه ذخیره می‌شود\nبدون حساب کاربری، بدون اینترنت',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 11, height: 1.9, color: onSurface.withValues(alpha: 0.5)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _feature(BuildContext context, IconData icon, String title, String sub) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(sub,
                    style: TextStyle(
                        fontSize: 11.5, color: onSurface.withValues(alpha: 0.6))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
