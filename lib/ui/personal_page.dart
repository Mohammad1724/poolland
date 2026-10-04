import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format_utils.dart';
import '../core/jalali_utils.dart';
import '../core/money.dart';
import '../data/ledger.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/store.dart';
import 'widgets/period_chart.dart';
import 'widgets/quick_buttons.dart';
import 'widgets/widgets.dart';

/// صفحه‌ی حسابداری شخصی: ثبت سریع، بودجه‌بندی،
/// تراکنش‌های تکرارشونده و نمودار روزانه/هفتگی/ماهانه.
class PersonalPage extends StatelessWidget {
  const PersonalPage({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final range = AppRepository.monthOf(DateTime.now());
    final month = repo.summary(
        from: range.start, to: range.end, scope: TxnScope.personal);
    final usages = repo.budgetUsages();
    final personal =
        repo.transactions.where((t) => t.scope == TxnScope.personal).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
      children: [
        // ---- خلاصه‌ی ماه شخصی ----
        CardBox(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.person_outline_rounded, size: 17),
                  const SizedBox(width: 6),
                  Text('خلاصه‌ی شخصیِ ${J.mLabel(DateTime.now())}',
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _miniStat(context, 'درآمد', month.income,
                          const Color(0xFF16A34A), Icons.trending_up_rounded)),
                  Container(
                      width: 1,
                      height: 42,
                      color: Theme.of(context).dividerColor),
                  Expanded(
                      child: _miniStat(context, 'هزینه', month.expense,
                          const Color(0xFFE11D48), Icons.trending_down_rounded)),
                ],
              ),
              const SizedBox(height: 12),
              Divider(color: Theme.of(context).dividerColor),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.account_balance_wallet_rounded, size: 18),
                  const SizedBox(width: 8),
                  Text('مانده',
                      style: TextStyle(
                          fontSize: 12.5,
                          color: onSurface.withValues(alpha: 0.7))),
                  const Spacer(),
                  MoneyText(month.profit,
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: month.profit >= 0
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFE11D48))),
                ],
              ),
            ],
          ),
        ),

        // ---- دکمه‌های ثبت سریع ----
        SectionTitle(
          'ثبت سریع',
          icon: Icons.bolt_rounded,
          action: 'مدیریت',
          onAction: () => _manageQuick(context),
        ),
        QuickButtonsRow(
          emptyHint: 'هنوز دکمه‌ای نساخته‌اید. با «مدیریت» دکمه‌های موردنیازتان '
              '(خوراک، تاکسی، قبض…) را بسازید تا ثبت هزینه فقط یک لمس باشد.',
          onLongPress: (q) => _editQuick(context, q),
        ),

        // ---- بودجه‌ی ماهانه ----
        SectionTitle(
          'بودجه‌ی ماهانه',
          icon: Icons.pie_chart_outline_rounded,
          action: 'افزودن',
          onAction: () => _editBudget(context, null),
        ),
        if (usages.isEmpty)
          CardBox(
            child: Text(
              'برای هر دسته (مثلاً خوراک یا حمل‌ونقل) یک سقف ماهانه تعیین کنید؛ '
              'برنامه در همین صفحه نشان می‌دهد چقدر از سقف باقی مانده است.',
              style: TextStyle(
                  fontSize: 12,
                  height: 1.7,
                  color: onSurface.withValues(alpha: 0.65)),
            ),
          )
        else
          ...usages.map((u) => _BudgetTile(
                usage: u,
                onEdit: () => _editBudget(context, u.budget),
                onDelete: () async {
                  final ok = await confirmDialog(context,
                      title: 'حذف بودجه',
                      message: 'بودجه‌ی «${u.categoryName}» حذف شود؟',
                      okLabel: 'حذف',
                      danger: true);
                  if (ok && context.mounted) {
                    await context.read<AppRepository>().deleteBudget(u.budget.id);
                  }
                },
              )),

        // ---- تراکنش‌های تکرارشونده ----
        SectionTitle(
          'تراکنش‌های تکرارشونده',
          icon: Icons.autorenew_rounded,
          action: 'افزودن',
          onAction: () => _editRecurring(context, null),
        ),
        if (repo.recurringRules.isEmpty)
          CardBox(
            child: Text(
              'اجاره، اینترنت، آبونمان و حقوق را یک‌بار تعریف کنید؛ '
              'برنامه هر ماه خودکار آن‌ها را ثبت می‌کند.',
              style: TextStyle(
                  fontSize: 12,
                  height: 1.7,
                  color: onSurface.withValues(alpha: 0.65)),
            ),
          )
        else
          ...repo.recurringRules.map((r) => _RecurringTile(
                rule: r,
                onEdit: () => _editRecurring(context, r),
                onDelete: () async {
                  final ok = await confirmDialog(context,
                      title: 'حذف قانون',
                      message: '«${r.title}» حذف شود؟ (تراکنش‌های ثبت‌شده باقی می‌مانند)',
                      okLabel: 'حذف',
                      danger: true);
                  if (ok && context.mounted) {
                    await context
                        .read<AppRepository>()
                        .deleteRecurring(r.id);
                  }
                },
              )),
        if (repo.recurringRules.isNotEmpty) ...[
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: () async {
              final n =
                  await context.read<AppRepository>().postDueRecurring();
              if (!context.mounted) return;
              showSnack(context,
                  n == 0 ? 'موردِ سررسیدشده‌ای وجود نداشت' : '$n تراکنش ثبت شد');
            },
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('ثبت موردهای سررسیدشده'),
          ),
        ],

        // ---- نمودارها ----
        const SectionTitle('روند هزینه و درآمد', icon: Icons.bar_chart_rounded),
        _PeriodChartCard(
          daily: Ledger.dailySeries(repo.transactions,
              days: 30, scope: TxnScope.personal),
          weekly: Ledger.weeklySeries(repo.transactions,
              weeks: 12, scope: TxnScope.personal),
          monthly: repo.series(months: 6, scope: TxnScope.personal),
        ),

        // ---- آخرین تراکنش‌های شخصی ----
        SectionTitle('آخرین تراکنش‌های شخصی',
            icon: Icons.receipt_long_outlined),
        if (personal.isEmpty)
          CardBox(
            child: Text(
              'هنوز چیزی ثبت نکرده‌اید. از دکمه‌های بالا شروع کنید.',
              style: TextStyle(
                  fontSize: 12, color: onSurface.withValues(alpha: 0.65)),
            ),
          )
        else
          CardBox(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final t in personal.take(8))
                  TxnTile(
                    txn: t,
                    categoryName: repo.categories
                            .where((c) => c.id == t.categoryId)
                            .firstOrNull
                            ?.name ??
                        'بدون دسته',
                    showCustomer: false,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _miniStat(BuildContext context, String label, double value, Color color,
          IconData icon) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6))),
            ],
          ),
          const SizedBox(height: 5),
          MoneyText(value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        ],
      );

  // ---------- عملیات ----------
  Future<void> _manageQuick(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _QuickManagerSheet(),
    );
  }

  Future<void> _editQuick(BuildContext context, QuickExpense? q) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QuickEditSheet(initial: q),
    );
  }

  Future<void> _editBudget(BuildContext context, Budget? b) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BudgetSheet(initial: b),
    );
  }

  Future<void> _editRecurring(BuildContext context, RecurringRule? r) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RecurringSheet(initial: r),
    );
  }
}

/// ---------------- کارت بودجه ----------------
class _BudgetTile extends StatelessWidget {
  const _BudgetTile(
      {required this.usage, required this.onEdit, required this.onDelete});

  final BudgetUsage usage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final color = usage.level == 2
        ? const Color(0xFFE11D48)
        : usage.level == 1
            ? const Color(0xFFD97706)
            : const Color(0xFF16A34A);
    final pct = usage.ratio > 1 ? 1.0 : usage.ratio;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CardBox(
        onTap: onEdit,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(usage.categoryName,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                MoneyText(usage.spent, compact: true,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: color)),
                Text(' / ${Money.text(usage.budget.limit, compact: true)}',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: onSurface.withValues(alpha: 0.55))),
                const SizedBox(width: 4),
                InkWell(
                  onTap: onDelete,
                  borderRadius: BorderRadius.circular(8),
                  child: Icon(Icons.delete_outline_rounded,
                      size: 17, color: onSurface.withValues(alpha: 0.4)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // نوار پیشرفتِ ساده و بدون انیمیشن (باتری کمتری مصرف می‌کند)
            Container(
              height: 7,
              width: double.infinity,
              decoration: BoxDecoration(
                color: onSurface.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerRight,
                widthFactor: pct < 0 ? 0 : (pct > 1 ? 1 : pct),
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              usage.isOver
                  ? '${Money.text(-usage.remaining, compact: true)} بیشتر از سقف خرج کرده‌اید'
                  : '${Money.text(usage.remaining, compact: true)} تا سقف باقی مانده • '
                      '${Fmt.percent(usage.ratio, persian: true)}',
              style: TextStyle(
                  fontSize: 11, color: onSurface.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------------- کارت قانون تکرارشونده ----------------
class _RecurringTile extends StatelessWidget {
  const _RecurringTile(
      {required this.rule, required this.onEdit, required this.onDelete});

  final RecurringRule rule;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isIncome = rule.kind == TxnKind.income;
    final color = isIncome ? const Color(0xFF16A34A) : const Color(0xFFE11D48);
    final next = rule.nextDue(DateTime.now());

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: CardBox(
        onTap: onEdit,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(Icons.autorenew_rounded, size: 17, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(rule.title,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                    '${rule.period.label} • ${Money.text(rule.amount)}'
                    '${next == null ? '' : ' • بعدی ${J.d(next)}'}',
                    style: TextStyle(
                        fontSize: 11.5,
                        color: onSurface.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
            if (!rule.enabled)
              TagChip('غیرفعال',
                  color: onSurface.withValues(alpha: 0.5), dense: true),
            const SizedBox(width: 6),
            InkWell(
              onTap: onDelete,
              borderRadius: BorderRadius.circular(8),
              child: Icon(Icons.delete_outline_rounded,
                  size: 17, color: onSurface.withValues(alpha: 0.4)),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------------- نمودار دوره‌ای ----------------
class _PeriodChartCard extends StatefulWidget {
  const _PeriodChartCard({
    required this.daily,
    required this.weekly,
    required this.monthly,
  });

  final List<DayPoint> daily;
  final List<DayPoint> weekly;
  final List<MonthPoint> monthly;

  @override
  State<_PeriodChartCard> createState() => _PeriodChartCardState();
}

class _PeriodChartCardState extends State<_PeriodChartCard> {
  int _mode = 0; // ۰ روزانه، ۱ هفتگی، ۲ ماهانه

  @override
  Widget build(BuildContext context) {
    return CardBox(
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      child: Column(
        children: [
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('روزانه')),
              ButtonSegment(value: 1, label: Text('هفتگی')),
              ButtonSegment(value: 2, label: Text('ماهانه')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 12),
          if (_mode == 0)
            PeriodBarChart(
              points: widget.daily,
              labelOf: (p) => Fmt.toFaDigits('${J.of(p.day).day}'),
            )
          else if (_mode == 1)
            PeriodBarChart(
              points: widget.weekly,
              labelOf: (p) =>
                  Fmt.toFaDigits('${J.of(p.day).day}/${J.of(p.day).month}'),
            )
          else
            PeriodBarChart(
              points: [
                for (final m in widget.monthly)
                  DayPoint(day: m.monthStart, income: m.income, expense: m.expense),
              ],
              labelOf: (p) => Fmt.monthName(J.of(p.day).month),
            ),
        ],
      ),
    );
  }
}

/// ---------------- شیتِ بودجه ----------------
class _BudgetSheet extends StatefulWidget {
  const _BudgetSheet({this.initial});

  final Budget? initial;

  @override
  State<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends State<_BudgetSheet> {
  final _limit = TextEditingController();
  String? _categoryId;

  @override
  void initState() {
    super.initState();
    final b = widget.initial;
    _categoryId = b?.categoryId;
    _limit.text = b == null ? '' : groupedNumber(b.limit);
  }

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final cats = repo.categories
        .where((c) => c.kind == TxnKind.expense && c.scope == TxnScope.personal)
        .toList();
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
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
              Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Text(widget.initial == null ? 'بودجه‌ی جدید' : 'ویرایش بودجه',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              SelectField<Category>(
                label: 'دسته‌بندی',
                value: cats.where((c) => c.id == _categoryId).firstOrNull,
                items: cats,
                labelOf: (c) => c.name,
                onChanged: (c) => setState(() => _categoryId = c?.id),
              ),
              const SizedBox(height: 12),
              AmountField(controller: _limit, label: 'سقف ماهانه'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  final limit = parseAmount(_limit.text);
                  if (_categoryId == null || limit <= 0) return;
                  final repo = context.read<AppRepository>();
                  final b = Budget(
                    id: widget.initial?.id ?? LocalStore.newId(),
                    categoryId: _categoryId!,
                    limit: limit,
                  );
                  if (widget.initial == null) {
                    await repo.addBudget(b);
                  } else {
                    await repo.updateBudget(b);
                  }
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('ذخیره'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ---------------- شیتِ قانون تکرارشونده ----------------
class _RecurringSheet extends StatefulWidget {
  const _RecurringSheet({this.initial});

  final RecurringRule? initial;

  @override
  State<_RecurringSheet> createState() => _RecurringSheetState();
}

class _RecurringSheetState extends State<_RecurringSheet> {
  final _title = TextEditingController();
  final _amount = TextEditingController();
  TxnKind _kind = TxnKind.expense;
  RecurringPeriod _period = RecurringPeriod.monthly;
  int _dayOfMonth = 1;
  String? _categoryId;
  late DateTime _start;
  DateTime? _end;
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    final r = widget.initial;
    _title.text = r?.title ?? '';
    _amount.text = r == null ? '' : groupedNumber(r.amount);
    _kind = r?.kind ?? TxnKind.expense;
    _period = r?.period ?? RecurringPeriod.monthly;
    _dayOfMonth = r?.dayOfMonth ?? 1;
    _categoryId = r?.categoryId;
    _start = r?.startDate ?? DateTime.now();
    _end = r?.endDate;
    _enabled = r?.enabled ?? true;
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final cats = repo.categories
        .where((c) =>
            c.scope == TxnScope.personal &&
            c.kind == (_kind == TxnKind.income ? TxnKind.income : TxnKind.expense))
        .toList();
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
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
              Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Text(widget.initial == null ? 'قانون جدید' : 'ویرایش قانون',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              AppTextField(
                  controller: _title,
                  label: 'عنوان',
                  hint: 'مثلاً اجاره خانه',
                  icon: Icons.title_rounded),
              const SizedBox(height: 12),
              AmountField(controller: _amount),
              const SizedBox(height: 12),
              SegmentedButton<TxnKind>(
                segments: const [
                  ButtonSegment(value: TxnKind.expense, label: Text('هزینه')),
                  ButtonSegment(value: TxnKind.income, label: Text('درآمد')),
                ],
                selected: {_kind},
                onSelectionChanged: (s) =>
                    setState(() => _kind = s.first == TxnKind.income ? TxnKind.income : TxnKind.expense),
              ),
              const SizedBox(height: 12),
              SelectField<Category>(
                label: 'دسته‌بندی',
                value: cats.where((c) => c.id == _categoryId).firstOrNull,
                items: cats,
                labelOf: (c) => c.name,
                clearable: true,
                onChanged: (c) => setState(() => _categoryId = c?.id),
              ),
              const SizedBox(height: 12),
              SelectField<RecurringPeriod>(
                label: 'دوره‌ی تکرار',
                value: _period,
                items: RecurringPeriod.values,
                labelOf: (p) => p.label,
                onChanged: (p) => setState(() => _period = p ?? _period),
              ),
              if (_period == RecurringPeriod.monthly) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('روزِ اجرا در ماه:',
                        style: TextStyle(fontSize: 12.5)),
                    const SizedBox(width: 10),
                    DropdownButton<int>(
                      value: _dayOfMonth,
                      items: [
                        for (var d = 1; d <= 30; d++)
                          DropdownMenuItem(
                              value: d,
                              child: Text(Fmt.toFaDigits('$d'))),
                      ],
                      onChanged: (v) => setState(() => _dayOfMonth = v ?? 1),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              JalaliDateField(
                  label: 'شروع',
                  value: _start,
                  onChanged: (d) => setState(() => _start = d)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _end == null
                          ? 'پایان: نامحدود'
                          : 'پایان: ${J.d(_end!)}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  if (_end != null)
                    TextButton(
                        onPressed: () => setState(() => _end = null),
                        child: const Text('نامحدود')),
                ],
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('فعال', style: TextStyle(fontSize: 13)),
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () async {
                  final amount = parseAmount(_amount.text);
                  if (_title.text.trim().isEmpty || amount <= 0) return;
                  final repo = context.read<AppRepository>();
                  final r = RecurringRule(
                    id: widget.initial?.id ?? LocalStore.newId(),
                    title: _title.text.trim(),
                    kind: _kind,
                    amount: amount,
                    categoryId: _categoryId,
                    period: _period,
                    dayOfMonth: _dayOfMonth,
                    startDate: _start,
                    endDate: _end,
                    enabled: _enabled,
                    lastPosted: widget.initial?.lastPosted,
                  );
                  if (widget.initial == null) {
                    await repo.addRecurring(r);
                  } else {
                    await repo.updateRecurring(r);
                  }
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('ذخیره'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ---------------- مدیریت دکمه‌های سریع ----------------
class _QuickManagerSheet extends StatelessWidget {
  const _QuickManagerSheet();

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (ctx, controller) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2))),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  const Expanded(
                      child: Text('دکمه‌های ثبت سریع',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700))),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                children: [
                  for (final q in repo.quickExpenses)
                    ListTile(
                      leading: Icon(materialIcon(q.iconCodePoint), size: 20),
                      title: Text(q.label),
                      subtitle: Text(q.hasFixedAmount
                          ? Money.text(q.amount)
                          : 'مبلغ هنگام ثبت پرسیده می‌شود'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 19),
                            onPressed: () => Navigator.push(context,
                                MaterialPageRoute(
                                    builder: (_) => _QuickEditPage(initial: q))),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 19),
                            onPressed: () async {
                              final ok = await confirmDialog(context,
                                  title: 'حذف دکمه',
                                  message: '«${q.label}» حذف شود؟',
                                  okLabel: 'حذف',
                                  danger: true);
                              if (ok && context.mounted) {
                                await context
                                    .read<AppRepository>()
                                    .deleteQuickButton(q.id);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                    child: FilledButton.tonalIcon(
                      onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const _QuickEditPage())),
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('دکمه‌ی جدید'),
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
}

/// ---------------- ویرایش/ساخت دکمه‌ی سریع ----------------
class _QuickEditSheet extends StatelessWidget {
  const _QuickEditSheet({this.initial});

  final QuickExpense? initial;

  @override
  Widget build(BuildContext context) => _QuickEditPage(
        initial: initial,
        asSheet: true,
      );
}

class _QuickEditPage extends StatefulWidget {
  const _QuickEditPage({this.initial, this.asSheet = false});

  final QuickExpense? initial;
  final bool asSheet;

  @override
  State<_QuickEditPage> createState() => _QuickEditPageState();
}

class _QuickEditPageState extends State<_QuickEditPage> {
  final _label = TextEditingController();
  final _amount = TextEditingController();
  TxnKind _kind = TxnKind.expense;
  String? _categoryId;
  int _iconCodePoint = 0xe15b;

  // همان فهرستِ سراسری (const) در quick_buttons.dart
  static const List<IconData> _icons = quickIcons;

  @override
  void initState() {
    super.initState();
    final q = widget.initial;
    _label.text = q?.label ?? '';
    _amount.text = q == null || !q.hasFixedAmount ? '' : groupedNumber(q.amount);
    _kind = q?.kind ?? TxnKind.expense;
    _categoryId = q?.categoryId;
    _iconCodePoint = q?.iconCodePoint ?? 0xe15b;
  }

  @override
  void dispose() {
    _label.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final cats = repo.categories
        .where((c) =>
            c.scope == TxnScope.personal &&
            c.kind == (_kind == TxnKind.income ? TxnKind.income : TxnKind.expense))
        .toList();

    final body = ListView(
      padding: EdgeInsets.fromLTRB(
          18, widget.asSheet ? 12 : 12, 18, 24 + MediaQuery.of(context).viewInsets.bottom),
      children: [
        AppTextField(controller: _label, label: 'عنوان دکمه', hint: 'مثلاً تاکسی'),
        const SizedBox(height: 12),
        AmountField(
            controller: _amount,
            label: 'مبلغ ثابت (اختیاری)',
            validator: (_) => null),
        const SizedBox(height: 4),
        Text(
          'اگر خالی بماند، هنگام ثبت مبلغ از شما پرسیده می‌شود.',
          style: TextStyle(
              fontSize: 11,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.55)),
        ),
        const SizedBox(height: 14),
        SegmentedButton<TxnKind>(
          segments: const [
            ButtonSegment(value: TxnKind.expense, label: Text('هزینه')),
            ButtonSegment(value: TxnKind.income, label: Text('درآمد')),
          ],
          selected: {_kind},
          onSelectionChanged: (s) => setState(() =>
              _kind = s.first == TxnKind.income ? TxnKind.income : TxnKind.expense),
        ),
        const SizedBox(height: 14),
        SelectField<Category>(
          label: 'دسته‌بندی',
          value: cats.where((c) => c.id == _categoryId).firstOrNull,
          items: cats,
          labelOf: (c) => c.name,
          clearable: true,
          onChanged: (c) => setState(() => _categoryId = c?.id),
        ),
        const SizedBox(height: 14),
        const Text('آیکون', style: TextStyle(fontSize: 12.5)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final ic in _icons)
              InkWell(
                onTap: () => setState(() => _iconCodePoint = ic.codePoint),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: _iconCodePoint == ic.codePoint
                        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.18)
                        : Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _iconCodePoint == ic.codePoint
                          ? Theme.of(context).colorScheme.primary
                          : Colors.transparent,
                    ),
                  ),
                  child: Icon(ic, size: 19),
                ),
              ),
          ],
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: () async {
            if (_label.text.trim().isEmpty) return;
            final repo = context.read<AppRepository>();
            final q = QuickExpense(
              id: widget.initial?.id ?? LocalStore.newId(),
              label: _label.text.trim(),
              amount: parseAmount(_amount.text),
              kind: _kind,
              categoryId: _categoryId,
              iconCodePoint: _iconCodePoint,
              sortOrder: widget.initial?.sortOrder ??
                  (repo.quickExpenses.isEmpty
                      ? 0
                      : repo.quickExpenses.last.sortOrder + 1),
            );
            if (widget.initial == null) {
              await repo.addQuickButton(q);
            } else {
              await repo.updateQuickButton(q);
            }
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('ذخیره'),
        ),
      ],
    );

    if (widget.asSheet) {
      return Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                    color: Theme.of(context).dividerColor,
                    borderRadius: BorderRadius.circular(2))),
            Flexible(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(widget.initial == null ? 'دکمه‌ی جدید' : 'ویرایش دکمه')),
      body: body,
    );
  }
}
