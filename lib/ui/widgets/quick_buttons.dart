import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format_utils.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import 'widgets.dart';
import '../motion_kit.dart';

import '../../core/localization.dart';

/// Icons available for quick-entry buttons.
///
/// This list must be `const` so icon tree shaking in a release build
/// can detect which icons are in use.
/// Creating IconData dynamically with a constructor causes a build error.
const List<IconData> quickIcons = <IconData>[
  Icons.restaurant_outlined,
  Icons.directions_bus_outlined,
  Icons.shopping_bag_outlined,
  Icons.receipt_outlined,
  Icons.local_cafe_outlined,
  Icons.local_hospital_outlined,
  Icons.home_outlined,
  Icons.wifi_rounded,
  Icons.bolt_rounded,
  Icons.school_outlined,
  Icons.fitness_center_rounded,
  Icons.card_giftcard_rounded,
  Icons.flight_takeoff_rounded,
  Icons.sports_soccer_outlined,
  Icons.movie_outlined,
  Icons.payments_outlined,
  Icons.medical_services_outlined,
  Icons.account_balance_wallet_outlined,
];

/// Convert a saved code point to one of the [quickIcons].
/// (Returns the default icon if the code is unknown.)
IconData materialIcon(int? codePoint) {
  if (codePoint != null) {
    for (final ic in quickIcons) {
      if (ic.codePoint == codePoint) return ic;
    }
  }
  return Icons.receipt_long_outlined;
}

/// Row of quick-entry buttons.
///
/// On the personal page one tap records the button straight away; inside a
/// transaction form [onTap] instead prefills the form so the entry stays
/// fully editable. [scopeFilter] and [incomeFilter] keep the row separated
/// by section (business/personal) and by direction (income/expense), so each
/// form only offers the buttons that fit what is being recorded right now.
class QuickButtonsRow extends StatelessWidget {
  const QuickButtonsRow({
    super.key,
    this.emptyHint,
    this.onLongPress,
    this.onTap,
    this.scopeFilter,
    this.incomeFilter,
    this.hideWhenEmpty = false,
    this.trailing,
  });

  final String? emptyHint;
  final void Function(QuickExpense q)? onLongPress;

  /// When set, tapping a chip calls this instead of recording immediately.
  final void Function(QuickExpense q)? onTap;

  /// Only show buttons of this section (null = both).
  final TxnScope? scopeFilter;

  /// Only show income (true) or expense (false) buttons; null = both.
  final bool? incomeFilter;

  /// Render nothing (except [trailing]) when no button matches, so forms
  /// stay clean for users who have not configured buttons for that case.
  final bool hideWhenEmpty;

  /// Extra widget appended after the chips (typically an "add" chip).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final items = repo.quickExpenses
        .where(
          (q) =>
              (scopeFilter == null || q.scope == scopeFilter) &&
              (incomeFilter == null ||
                  (q.kind == TxnKind.income) == incomeFilter),
        )
        .toList();
    if (items.isEmpty && trailing == null) {
      if (hideWhenEmpty) return const SizedBox.shrink();
      return Text(
        emptyHint ?? 'No quick buttons configured.'.tr,
        style: TextStyle(
          fontSize: 12,
          height: 1.7,
          color: Theme.of(context).colorScheme.onSurface
              .withValues(alpha: 0.65),
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final q in items)
          QuickChip(
            quick: q,
            onTap: onTap == null
                ? () => recordQuickExpense(context, q)
                : () => onTap!(q),
            onLongPress: onLongPress == null ? null : () => onLongPress!(q),
          ),
        ?trailing,
      ],
    );
  }
}

/// A quick-entry button
class QuickChip extends StatelessWidget {
  const QuickChip({
    super.key,
    required this.quick,
    this.onTap,
    this.onLongPress,
  });

  final QuickExpense quick;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final q = quick;
    final isIncome = q.kind == TxnKind.income;
    final color = isIncome ? const Color(0xFF16A34A) : const Color(0xFFE11D48);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(materialIcon(q.iconCodePoint), size: 17, color: color),
            const SizedBox(width: 7),
            Text(
              q.label.tr,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            if (q.hasFixedAmount) ...[
              const SizedBox(width: 6),
              Text(
                Money.text(q.amount, compact: true),
                style: TextStyle(
                  fontSize: 11,
                  color: color.withValues(alpha: 0.75),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Record a quick expense or income (asks for an amount if none is fixed).
Future<void> recordQuickExpense(BuildContext context, QuickExpense q) async {
  final repo = context.read<AppRepository>();
  var amount = q.amount;
  DateTime? date;
  if (!q.hasFixedAmount) {
    final res = await showLedgerSheet<QuickAmountResult>(
      context,
      builder: (_) => QuickAmountSheet(quick: q),
    );
    if (res == null || res.amount <= 0) return;
    amount = res.amount;
    // The sheet has a date picker; honour the day the user picked instead
    // of silently recording everything as "today".
    date = res.date;
  }
  final txn = await repo.addQuickExpense(q, amount: amount, date: date);
  if (!context.mounted) return;
  MoneyCelebration.recorded(context);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          '{label} • {amount} recorded'.trArgs({
            'label': q.label.tr,
            'amount': Money.text(amount),
          }),
        ),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Cancel'.tr,
          onPressed: () => repo.deleteTxn(txn.id),
        ),
      ),
    );
}

/// What [QuickAmountSheet] hands back: the entered amount plus the day it
/// belongs to.
class QuickAmountResult {
  const QuickAmountResult({required this.amount, required this.date});

  final double amount;
  final DateTime date;
}

/// Sheet for entering an amount (and date) for buttons without a fixed amount.
class QuickAmountSheet extends StatefulWidget {
  const QuickAmountSheet({super.key, required this.quick});

  final QuickExpense quick;

  @override
  State<QuickAmountSheet> createState() => _QuickAmountSheetState();
}

class _QuickAmountSheetState extends State<QuickAmountSheet> {
  final _ctrl = TextEditingController();
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
    _ctrl.text = widget.quick.hasFixedAmount
        ? groupedNumber(widget.quick.amount)
        : '';
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
      // The amount field autofocuses, so this sheet always opens with the
      // keyboard up: on a short screen the remaining space is tighter than the
      // form. Scroll instead of overflowing — and scrolling also gives the
      // sheet the usual pull-down-to-close at its top.
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHandle(),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(materialIcon(widget.quick.iconCodePoint), size: 20),
                const SizedBox(width: 8),
                Text(
                  widget.quick.label.tr,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            AmountField(controller: _ctrl, autofocus: true),
            const SizedBox(height: 10),
            JalaliDateField(
              label: 'Date'.tr,
              value: _date,
              onChanged: (d) => setState(() => _date = d),
            ),
            const SizedBox(height: 16),
            // Disabled until there is something to record. The button used to
            // stay live and silently do nothing on an empty or zero amount, so
            // the sheet simply refused to close and gave no clue why.
            AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                final amount = parseAmount(_ctrl.text);
                return FilledButton(
                  onPressed: amount <= 0
                      ? null
                      : () => Navigator.pop(
                          context,
                          QuickAmountResult(amount: amount, date: _date),
                        ),
                  child: Text('Record'.tr),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
