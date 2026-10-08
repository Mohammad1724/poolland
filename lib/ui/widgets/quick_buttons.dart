import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format_utils.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import 'widgets.dart';

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

/// Row of quick-entry buttons (one tap records an expense or income).
class QuickButtonsRow extends StatelessWidget {
  const QuickButtonsRow({super.key, this.emptyHint, this.onLongPress});

  final String? emptyHint;
  final void Function(QuickExpense q)? onLongPress;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    if (repo.quickExpenses.isEmpty) {
      return Text(
        emptyHint ?? 'No quick buttons configured.',
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
        for (final q in repo.quickExpenses)
          QuickChip(
            quick: q,
            onTap: () => recordQuickExpense(context, q),
            onLongPress: onLongPress == null ? null : () => onLongPress!(q),
          ),
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
            Flexible(
              child: Text(
                q.label.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
            if (q.hasFixedAmount) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  Money.text(q.amount, compact: true),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: color.withValues(alpha: 0.75),
                  ),
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
  if (!q.hasFixedAmount) {
    final res = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => QuickAmountSheet(quick: q),
    );
    if (res == null || res <= 0) return;
    amount = res;
  }
  final txn = await repo.addQuickExpense(q, amount: amount);
  if (!context.mounted) return;
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
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
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
            FilledButton(
              onPressed: () {
                final v = parseAmount(_ctrl.text);
                if (v <= 0) return;
                Navigator.pop(context, v);
              },
              child: Text('Record'.tr),
            ),
          ],
        ),
      ),
    );
  }
}
