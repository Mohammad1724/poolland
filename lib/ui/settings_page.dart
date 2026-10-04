import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/backup.dart';
import '../core/format_utils.dart';
import '../core/jalali_utils.dart';
import '../core/money.dart';
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
      appBar: AppBar(title: const Text('تنظیمات')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          // ---------- کسب‌وکار ----------
          const SectionTitle('کسب‌وکار', icon: Icons.storefront_outlined),
          CardBox(
            child: Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.badge_outlined, size: 20),
                  title: const Text('نام کسب‌وکار', style: TextStyle(fontSize: 13.5)),
                  subtitle: Text(s.businessName, style: const TextStyle(fontSize: 12)),
                  onTap: () => _editText(
                    context,
                    title: 'نام کسب‌وکار',
                    initial: s.businessName,
                    hint: 'مثلاً: VPN علی',
                    onSave: (v) => repo.updateSettings(s.copyWith(businessName: v)),
                  ),
                ),
                Divider(color: Theme.of(context).dividerColor),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.account_balance_wallet_outlined, size: 20),
                  title: const Text('موجودی اولیه صندوق', style: TextStyle(fontSize: 13.5)),
                  subtitle: Text(
                    '${Money.text(s.openingCash)} — پول نقد/بانکی که از قبل داشتید',
                    style: const TextStyle(fontSize: 11.5),
                  ),
                  onTap: () => _editAmount(context,
                      title: 'موجودی اولیه صندوق',
                      initial: s.openingCash,
                      onSave: (v) => repo.updateSettings(s.copyWith(openingCash: v))),
                ),
              ],
            ),
          ),

          // ---------- داده‌های پایه ----------
          const SectionTitle('داده‌های پایه', icon: Icons.tune_rounded),
          CardBox(
            child: Column(
              children: [
                _navTile(context,
                    icon: Icons.local_offer_outlined,
                    title: 'پلن‌های فروش',
                    subtitle: '${Fmt.toFaDigits('${repo.plans.length}')} پلن ثبت شده',
                    page: const PlansPage()),
                Divider(color: Theme.of(context).dividerColor),
                _navTile(context,
                    icon: Icons.category_outlined,
                    title: 'دسته‌بندی درآمد و هزینه',
                    subtitle: '${Fmt.toFaDigits('${repo.categories.length}')} دسته',
                    page: const CategoriesPage()),
                Divider(color: Theme.of(context).dividerColor),
                _navTile(context,
                    icon: Icons.currency_exchange_rounded,
                    title: 'ارزها و نرخ تبدیل',
                    subtitle: s.currencies
                        .map((c) => '${c.code} ${Fmt.toFaDigits(Fmt.number(c.rateToBase))}')
                        .join(' • '),
                    page: const RatesPage()),
              ],
            ),
          ),

          // ---------- نمایش ----------
          const SectionTitle('نمایش', icon: Icons.palette_outlined),
          CardBox(
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: s.persianDigits,
                  onChanged: (v) => repo.updateSettings(s.copyWith(persianDigits: v)),
                  title: const Text('نمایش اعداد فارسی', style: TextStyle(fontSize: 13.5)),
                ),
                Divider(color: Theme.of(context).dividerColor),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.notifications_active_outlined, size: 20),
                  title: const Text('هشدار انقضا', style: TextStyle(fontSize: 13.5)),
                  subtitle: Text('${Fmt.toFaDigits('${s.reminderDays}')} روز قبل از انقضا',
                      style: const TextStyle(fontSize: 11.5)),
                  onTap: () => _editInt(
                    context,
                    title: 'چند روز قبل هشدار بدهیم؟',
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
                      const Text('ظاهر برنامه', style: TextStyle(fontSize: 13.5)),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'system', label: Text('سیستم')),
                          ButtonSegment(value: 'light', label: Text('روشن')),
                          ButtonSegment(value: 'dark', label: Text('تاریک')),
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

          // ---------- پشتیبان‌گیری ----------
          const SectionTitle('پشتیبان‌گیری', icon: Icons.cloud_sync_outlined),
          CardBox(
            child: Column(
              children: [
                _actionTile(context,
                    icon: Icons.share_rounded,
                    title: 'ارسال فایل پشتیبان',
                    subtitle: 'خروجی JSON برای تلگرام/واتس‌اپ یا ذخیره در گوشی',
                    onTap: () => _backup(context, repo, share: true)),
                Divider(color: Theme.of(context).dividerColor),
                _actionTile(context,
                    icon: Icons.download_rounded,
                    title: 'ذخیره پشتیبان در دستگاه',
                    subtitle: 'انتخاب مسیر ذخیره‌ی فایل JSON',
                    onTap: () => _backup(context, repo, share: false)),
                Divider(color: Theme.of(context).dividerColor),
                _actionTile(context,
                    icon: Icons.restore_rounded,
                    title: 'بازگردانی از فایل پشتیبان',
                    subtitle: 'همه‌ی داده‌های فعلی با فایل انتخابی جایگزین می‌شود',
                    onTap: () => _restore(context, repo)),
              ],
            ),
          ),

          // ---------- داده‌ها ----------
          const SectionTitle('داده‌ها', icon: Icons.storage_rounded),
          CardBox(
            child: Column(
              children: [
                _actionTile(context,
                    icon: Icons.auto_awesome_outlined,
                    title: 'بارگذاری داده‌ی نمونه',
                    subtitle: 'برای تست سریع برنامه (داده‌های فعلی پاک می‌شود)',
                    onTap: () async {
                      final ok = await confirmDialog(context,
                          title: 'داده‌ی نمونه',
                          message:
                              'داده‌های فعلی پاک و داده‌ی نمونه جایگزین می‌شود. ادامه می‌دهید؟',
                          okLabel: 'ادامه');
                      if (!ok) return;
                      await repo.loadDemoData();
                      if (context.mounted) showSnack(context, 'داده‌ی نمونه بارگذاری شد');
                    }),
                Divider(color: Theme.of(context).dividerColor),
                _actionTile(context,
                    icon: Icons.delete_forever_outlined,
                    title: 'پاک کردن همه‌ی داده‌ها',
                    subtitle: 'بازگشت به حالت اولیه (قابل بازگشت نیست)',
                    danger: true,
                    onTap: () async {
                      final ok = await confirmDialog(context,
                          title: 'پاک کردن همه‌ی داده‌ها',
                          message:
                              'همه‌ی مشتری‌ها، اشتراک‌ها و تراکنش‌ها حذف می‌شوند. قبل از این کار پشتیبان بگیرید.',
                          okLabel: 'پاک کن',
                          danger: true);
                      if (!ok) return;
                      await repo.wipeAll();
                      if (context.mounted) showSnack(context, 'همه‌ی داده‌ها پاک شد');
                    }),
              ],
            ),
          ),

          // ---------- پیامک‌های بانکی ----------
          if (repo.smsSupported) ...[
            const SectionTitle('پیامک‌های بانکی', icon: Icons.sms_rounded),
            CardBox(
              child: Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: s.smsEnabled,
                    title: const Text('خواندن پیامک‌های بانکی',
                        style: TextStyle(fontSize: 13.5)),
                    subtitle: const Text(
                      'واریز و برداشت‌ها به‌طور خودکار شناسایی می‌شوند '
                      'و در صف بررسی قرار می‌گیرند',
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
                    title: 'بررسی پیامک‌ها',
                    subtitle: repo.smsPendingCount > 0
                        ? '${Fmt.toFaDigits('${repo.smsPendingCount}')} '
                            'تراکنش در انتظار تأیید'
                        : 'موردی در انتظار نیست',
                    page: const SmsPage(),
                  ),
                  Divider(color: Theme.of(context).dividerColor),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.date_range_outlined, size: 20),
                    title: const Text('بازه‌ی بررسی پیامک‌ها',
                        style: TextStyle(fontSize: 13.5)),
                    subtitle: Text(
                      '${Fmt.toFaDigits('${s.smsSyncDays}')} روز گذشته',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    onTap: () => _editInt(
                      context,
                      title: 'چند روز گذشته بررسی شود؟',
                      initial: s.smsSyncDays,
                      onSave: (v) => repo
                          .updateSettings(s.copyWith(smsSyncDays: v.clamp(1, 365))),
                    ),
                  ),
                  Divider(color: Theme.of(context).dividerColor),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: s.smsAutoApprove,
                    title: const Text('ثبت خودکار موارد کاملاً مطمئن',
                        style: TextStyle(fontSize: 13.5)),
                    subtitle: const Text(
                      'بدون تأیید شما هم تراکنش ثبت می‌شود (پیش‌فرض: خاموش)',
                      style: TextStyle(fontSize: 11.5),
                    ),
                    onChanged: (v) =>
                        repo.updateSettings(s.copyWith(smsAutoApprove: v)),
                  ),
                ],
              ),
            ),
          ],

          // ---------- درباره ----------
          const SectionTitle('درباره', icon: Icons.info_outline_rounded),
          CardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('دفتر وی‌پی‌ان',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(
                  'نسخه ۱.۱.۰ • نرم‌افزار آزاد (MIT)\nحسابداری ساده و آفلاین برای فروشندگان VPN.\nهمه‌ی داده‌ها فقط روی همین دستگاه ذخیره می‌شود.',
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
        trailing: const Icon(Icons.chevron_left_rounded, size: 18),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('ذخیره')),
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
          decoration: const InputDecoration(suffixText: 'تومان'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, parseAmount(ctrl.text)),
              child: const Text('ذخیره')),
        ],
      ),
    );
    if (res != null) await onSave(res);
  }

  Future<void> _editInt(BuildContext context,
      {required String title,
      required int initial,
      required Future<void> Function(int) onSave}) async {
    final ctrl = TextEditingController(text: Fmt.toFaDigits('$initial'));
    final res = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: 'روز'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(ctx, parseAmount(ctrl.text).toInt().clamp(0, 60)),
              child: const Text('ذخیره')),
        ],
      ),
    );
    if (res != null) await onSave(res);
  }

  Future<void> _backup(BuildContext context, AppRepository repo,
      {required bool share}) async {
    final content = const JsonEncoder.withIndent('  ').convert(repo.exportData());
    final name = 'hesab-vpn-backup-${J.d(DateTime.now(), persian: false).replaceAll('/', '-')}.json';
    final ok = share
        ? await Backup.shareFile(fileName: name, content: content)
        : await Backup.saveToDevice(fileName: name, content: content);
    if (context.mounted) {
      showSnack(context,
          ok ? 'فایل پشتیبان ساخته شد' : 'ذخیره‌ی پشتیبان لغو شد',
          error: !ok);
    }
  }

  Future<void> _restore(BuildContext context, AppRepository repo) async {
    try {
      final data = await Backup.pickJsonContent();
      if (data == null) return;
      if (!context.mounted) return;
      final ok = await confirmDialog(context,
          title: 'بازگردانی پشتیبان',
          message:
              'همه‌ی داده‌های فعلی با محتوای این فایل جایگزین می‌شود. ادامه می‌دهید؟',
          okLabel: 'بازگردانی');
      if (!ok) return;
      await repo.importData(data);
      if (context.mounted) showSnack(context, 'پشتیبان بازیابی شد');
    } catch (e) {
      if (context.mounted) showSnack(context, 'فایل نامعتبر است: $e', error: true);
    }
  }
}

/// ---------- صفحه‌ی ارزها و نرخ‌ها ----------
class RatesPage extends StatelessWidget {
  const RatesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final s = repo.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('ارزها و نرخ تبدیل')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addCurrency(context, repo),
        icon: const Icon(Icons.add_rounded),
        label: const Text('ارز جدید'),
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
                    'ارز پایه «تومان» است. برای هر ارز، نرخ آن به تومان را وارد کنید تا همه‌ی گزارش‌ها خودکار تبدیل شوند.',
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
                              ? 'ارز پایه'
                              : 'هر ${c.name} = ${Money.text(c.rateToBase)}',
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
                      tooltip: 'حذف',
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      onPressed: () async {
                        final ok = await confirmDialog(context,
                            title: 'حذف ارز',
                            message: 'ارز ${c.name} حذف شود؟ (تراکنش‌های قبلی حذف نمی‌شوند)',
                            okLabel: 'حذف',
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
        title: Text('نرخ ${c.name} به تومان'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(suffixText: 'تومان'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, parseAmount(ctrl.text)),
              child: const Text('ذخیره')),
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
        title: const Text('افزودن ارز'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: code,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'کد (مثلاً AED)')),
              const SizedBox(height: 10),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'نام')),
              const SizedBox(height: 10),
              TextField(
                  controller: symbol, decoration: const InputDecoration(labelText: 'نماد')),
              const SizedBox(height: 10),
              TextField(
                  controller: rate,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'نرخ به تومان', suffixText: 'تومان')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('افزودن')),
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

/// ---------- صفحه‌ی دسته‌بندی‌ها ----------
class CategoriesPage extends StatelessWidget {
  const CategoriesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('دسته‌بندی‌ها'),
          bottom: const TabBar(
            tabs: [Tab(text: 'درآمد'), Tab(text: 'هزینه')],
          ),
        ),
        body: TabBarView(
          children: [
            _list(context, repo, TxnKind.income),
            _list(context, repo, TxnKind.expense),
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context, AppRepository repo, TxnKind kind) {
    final list = repo.categoriesOf(kind);
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
                    tooltip: 'ویرایش',
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    onPressed: () async {
                      final ctrl = TextEditingController(text: c.name);
                      final res = await showDialog<String>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('ویرایش دسته'),
                          content: TextField(controller: ctrl, autofocus: true),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(ctx),
                                child: const Text('انصراف')),
                            FilledButton(
                                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                                child: const Text('ذخیره')),
                          ],
                        ),
                      );
                      if (res != null && res.isNotEmpty) {
                        await repo.renameCategory(c, res);
                      }
                    },
                  ),
                  IconButton(
                    tooltip: 'حذف',
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    onPressed: () async {
                      final ok = await confirmDialog(context,
                          title: 'حذف دسته',
                          message:
                              'دسته «${c.name}» حذف شود؟ تراکنش‌های آن بدون دسته می‌شوند.',
                          okLabel: 'حذف',
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
                title: Text(kind == TxnKind.income ? 'دسته‌ی درآمد جدید' : 'دسته‌ی هزینه جدید'),
                content: TextField(
                    controller: ctrl,
                    autofocus: true,
                    decoration: const InputDecoration(hintText: 'مثلاً: خرید سرور')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                      child: const Text('افزودن')),
                ],
              ),
            );
            if (res != null && res.isNotEmpty) await repo.addCategory(res, kind);
          },
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('افزودن دسته'),
        ),
      ],
    );
  }
}
