import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format_utils.dart';
import '../../core/jalali_utils.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import 'date_picker.dart';

import '../../core/localization.dart';

/// ---------------- Amount display ----------------
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.amount, {
    super.key,
    this.currency = 'IRT',
    this.style,
    this.signed = false,
    this.withSymbol = true,
    this.compact = false,
    this.positiveColor,
    this.negativeColor,
  });

  final double amount;
  final String currency;
  final TextStyle? style;
  final bool signed;
  final bool withSymbol;
  final bool compact;
  final Color? positiveColor;
  final Color? negativeColor;

  @override
  Widget build(BuildContext context) {
    Color? color = style?.color;
    if (signed && amount != 0) {
      color = amount > 0
          ? (positiveColor ?? const Color(0xFF16A34A))
          : (negativeColor ?? const Color(0xFFE11D48));
    }
    return Text(
      Money.text(
        amount,
        currency: currency,
        withSymbol: withSymbol,
        signed: signed,
        compact: compact,
      ),
      textDirection: TextDirection.ltr,
      style: style?.copyWith(color: color) ?? TextStyle(color: color),
    );
  }
}

/// ---------------- Card ----------------
class CardBox extends StatelessWidget {
  const CardBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A compact localized search field with a one-tap clear action.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.isDense = false,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool isDense;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    textInputAction: TextInputAction.search,
    decoration: InputDecoration(
      hintText: hint.tr,
      prefixIcon: const Icon(Icons.search_rounded, size: 20),
      isDense: isDense,
      suffixIcon: controller.text.isEmpty
          ? null
          : IconButton(
              tooltip: 'Clear search'.tr,
              icon: const Icon(Icons.close_rounded),
              onPressed: () {
                controller.clear();
                onChanged('');
              },
            ),
    ),
    onChanged: onChanged,
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.title, {
    super.key,
    this.action,
    this.onAction,
    this.icon,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: onSurface.withValues(alpha: 0.6)),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              title.tr,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: onSurface.withValues(alpha: 0.85),
              ),
            ),
          ),
          if (action != null && onAction != null)
            TextButton(
              onPressed: onAction,
              child: Text(action!.tr, style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}

/// Centers data-entry forms on large screens while remaining full-width on phones.
class FormPageContent extends StatelessWidget {
  const FormPageContent({super.key, required this.child, this.maxWidth = 760});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// A persistent save action for long mobile forms. Keeping the primary action
/// visible avoids scrolling back to the end of a form after editing fields.
class FormActionBar extends StatelessWidget {
  const FormActionBar({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.check_rounded,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: theme.dividerColor)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(icon),
              label: Text(label.tr),
            ),
          ),
        ),
      ),
    );
  }
}

/// ---------------- Colored tag ----------------
class TagChip extends StatelessWidget {
  const TagChip(
    this.text, {
    super.key,
    required this.color,
    this.icon,
    this.dense = false,
  });

  final String text;
  final Color color;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 9,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text.tr,
            style: TextStyle(
              fontSize: dense ? 10.5 : 11.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------- Empty state ----------------
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.text,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary
                    .withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 28,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title.tr,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (text != null) ...[
              const SizedBox(height: 6),
              Text(
                text!.tr,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.6,
                  color: onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!.tr),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// ---------------- Amount field ----------------
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    this.label = 'Amount',
    this.currency = 'IRT',
    this.autofocus = false,
    this.validator,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final String currency;
  final bool autofocus;
  final String? Function(String?)? validator;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final decimals = Money.decimals(currency);
    return TextFormField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textDirection: TextDirection.ltr,
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp(r'[0-9,.\u066C\u066B\u06F0-\u06F9]'),
        ),
      ],
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.5,
      ),
      decoration: InputDecoration(
        labelText: label.tr,
        hintText: '0',
        suffixText: Money.symbol(currency),
      ),
      onChanged: (_) => onChanged?.call(),
      validator: (v) {
        if (validator != null) return validator!(v)?.tr;
        if (parseAmount(v ?? '') <= 0) return 'Enter an amount'.tr;
        return null;
      },
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      onEditingComplete: () {
        final v = parseAmount(controller.text);
        final s = groupedNumber(v, decimals: decimals);
        controller.value = TextEditingValue(
          text: s,
          selection: TextSelection.collapsed(offset: s.length),
        );
        FocusScope.of(context).unfocus();
      },
      onFieldSubmitted: (_) {
        final v = parseAmount(controller.text);
        final s = groupedNumber(v, decimals: decimals);
        controller.value = TextEditingValue(
          text: s,
          selection: TextSelection.collapsed(offset: s.length),
        );
      },
    );
  }
}

/// ---------------- Jalali date field ----------------
class JalaliDateField extends StatelessWidget {
  const JalaliDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.icon = Icons.calendar_month_rounded,
    this.helper,
  });

  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final IconData icon;
  final String? helper;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final res = await showJalaliPicker(context, initial: value);
        if (res != null) onChanged(res);
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label.tr,
          prefixIcon: Icon(icon, size: 19),
          helperText: helper?.tr,
        ),
        child: Text(
          J.dFull(value),
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// ---------------- Generic selection field ----------------
class SelectField<T> extends StatelessWidget {
  const SelectField({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
    this.subOf,
    this.iconOf,
    this.icon,
    this.placeholder = 'Select',
    this.clearable = false,
    this.searchHint = 'Search...',
    this.sheetTitle,
    this.extraActionLabel,
    this.onExtraAction,
    this.validator,
  });

  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) labelOf;
  final String Function(T)? subOf;
  final IconData Function(T)? iconOf;
  final IconData? icon;
  final ValueChanged<T?> onChanged;
  final String placeholder;
  final bool clearable;
  final String searchHint;
  final String? sheetTitle;
  final String? extraActionLabel;
  final VoidCallback? onExtraAction;
  final String? Function(T?)? validator;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final res = await showModalBottomSheet<_PickResult<T>>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _PickSheet<T>(
            title: sheetTitle ?? label,
            items: items,
            current: value,
            labelOf: labelOf,
            subOf: subOf,
            iconOf: iconOf,
            clearable: clearable,
            searchHint: searchHint,
            extraActionLabel: extraActionLabel,
          ),
        );
        if (res == null) return;
        if (res.cleared) {
          onChanged(null);
        } else if (res.extra) {
          onExtraAction?.call();
        } else {
          onChanged(res.value);
        }
      },
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label.tr,
          prefixIcon: icon == null ? null : Icon(icon, size: 19),
          errorText: validator != null ? validator!(value)?.tr : null,
        ),
        child: Text(
          hasValue ? labelOf(value as T).tr : placeholder.tr,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
            color: hasValue ? onSurface : onSurface.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}

class _PickResult<T> {
  final T? value;
  final bool cleared;
  final bool extra;
  const _PickResult(this.value, {this.cleared = false, this.extra = false});
}

class _PickSheet<T> extends StatefulWidget {
  const _PickSheet({
    required this.title,
    required this.items,
    required this.current,
    required this.labelOf,
    this.subOf,
    this.iconOf,
    this.clearable = false,
    this.searchHint = 'Search...',
    this.extraActionLabel,
  });

  final String title;
  final List<T> items;
  final T? current;
  final String Function(T) labelOf;
  final String Function(T)? subOf;
  final IconData Function(T)? iconOf;
  final bool clearable;
  final String searchHint;
  final String? extraActionLabel;

  @override
  State<_PickSheet<T>> createState() => _PickSheetState<T>();
}

class _PickSheetState<T> extends State<_PickSheet<T>> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = widget.items
        .where(
          (e) =>
              _q.isEmpty ||
              widget.labelOf(e).tr.toLowerCase().contains(_q.toLowerCase()),
        )
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      maxChildSize: 0.92,
      minChildSize: 0.35,
      builder: (ctx, controller) => Container(
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: theme.dividerColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title.tr,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
            ),
            if (widget.items.length > 7)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: widget.searchHint.tr,
                    prefixIcon: const Icon(Icons.search_rounded, size: 19),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _q = v.trim()),
                ),
              ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  if (widget.clearable)
                    ListTile(
                      leading: const Icon(Icons.block_rounded, size: 20),
                      title: Text('None'.tr),
                      onTap: () => Navigator.pop(
                        context,
                        const _PickResult(null, cleared: true),
                      ),
                    ),
                  for (final item in items)
                    ListTile(
                      leading: widget.iconOf == null
                          ? null
                          : Icon(widget.iconOf!(item), size: 20),
                      title: Text(widget.labelOf(item).tr),
                      subtitle: widget.subOf == null
                          ? null
                          : Text(widget.subOf!(item)),
                      trailing: widget.current == item
                          ? Icon(
                              Icons.check_circle_rounded,
                              size: 20,
                              color: theme.colorScheme.primary,
                            )
                          : null,
                      onTap: () => Navigator.pop(context, _PickResult(item)),
                    ),
                  if (widget.extraActionLabel != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                      child: FilledButton.tonalIcon(
                        onPressed: () => Navigator.pop(
                          context,
                          const _PickResult(null, extra: true),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(widget.extraActionLabel!.tr),
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

/// ---------------- Plain text field ----------------
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.icon,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label.tr,
        hintText: hint?.tr,
        prefixIcon: icon == null ? null : Icon(icon, size: 19),
      ),
      validator: (value) => validator?.call(value)?.tr,
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
    );
  }
}

/// ---------------- Confirmation dialog ----------------
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String okLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool danger = false,
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title.tr),
      content: Text(message.tr, style: const TextStyle(height: 1.7)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelLabel.tr),
        ),
        FilledButton(
          style: danger
              ? FilledButton.styleFrom(backgroundColor: const Color(0xFFE11D48))
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(okLabel.tr),
        ),
      ],
    ),
  );
  return res ?? false;
}

void showSnack(BuildContext context, String message, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message.tr),
        backgroundColor: error ? const Color(0xFFB91C1C) : null,
        duration: const Duration(seconds: 2),
      ),
    );
}

/// A row formatted as “label: value”.
class InfoRow extends StatelessWidget {
  const InfoRow(
    this.label,
    this.value, {
    super.key,
    this.valueColor,
    this.icon,
  });

  final String label;
  final Widget value;
  final Color? valueColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: onSurface.withValues(alpha: 0.5)),
            const SizedBox(width: 6),
          ],
          Text(
            label.tr,
            style: TextStyle(
              fontSize: 12.5,
              color: onSurface.withValues(alpha: 0.7),
            ),
          ),
          const Spacer(),
          DefaultTextStyle.merge(
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: valueColor,
            ),
            child: value,
          ),
        ],
      ),
    );
  }
}

/// Transaction row shared across pages
class TxnTile extends StatelessWidget {
  const TxnTile({
    super.key,
    required this.txn,
    required this.categoryName,
    this.customerName,
    this.symbol = 'Toman',
    this.onTap,
    this.showCustomer = true,
  });

  final Txn txn;
  final String categoryName;
  final String? customerName;
  final String symbol;
  final VoidCallback? onTap;
  final bool showCustomer;

  Color get _color => switch (txn.kind) {
    TxnKind.income => const Color(0xFF16A34A),
    TxnKind.expense => const Color(0xFFE11D48),
    TxnKind.receive => const Color(0xFF0F766E),
    TxnKind.refund => const Color(0xFFD97706),
    TxnKind.payablePayment => const Color(0xFF7C3AED),
  };

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final title = txn.note.isNotEmpty ? txn.note : categoryName.tr;
    final sub = <String>[
      J.d(txn.date),
      if (showCustomer && customerName != null) customerName!,
      if (txn.kind.isProfitKind) (txn.credit ? 'Credit'.tr : 'Cash'.tr),
    ].join(' • ');

    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: _color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Icon(txn.kind.icon, size: 17, color: _color),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        sub,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          color: onSurface.withValues(alpha: 0.55),
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            Money.text(
              txn.amount *
                  switch (txn.kind) {
                    TxnKind.income || TxnKind.receive => 1,
                    TxnKind.expense ||
                    TxnKind.refund ||
                    TxnKind.payablePayment => -1,
                  },
              currency: txn.currency,
              signed: false,
            ),
            textDirection: TextDirection.ltr,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: _color,
            ),
          ),
          if (txn.currency != 'IRT' || txn.rateToBase != 1)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                Money.text(txn.amount * txn.rateToBase, withSymbol: false),
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 10.5,
                  color: onSurface.withValues(alpha: 0.55),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
