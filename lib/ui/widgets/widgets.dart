import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/format_utils.dart';
import '../../core/haptics.dart';
import '../../core/jalali_utils.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../design.dart';
import '../motion_kit.dart';
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
    this.maxLines,
    this.overflow,
    this.softWrap = true,
  });

  final double amount;
  final String currency;
  final TextStyle? style;
  final bool signed;
  final bool withSymbol;
  final bool compact;
  final Color? positiveColor;
  final Color? negativeColor;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool softWrap;

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
      maxLines: maxLines,
      overflow: overflow,
      softWrap: softWrap,
      style: style?.copyWith(color: color) ?? TextStyle(color: color),
    );
  }
}

/// ---------------- Card ----------------
class CardBox extends StatefulWidget {
  const CardBox({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<CardBox> createState() => _CardBoxState();
}

class _CardBoxState extends State<CardBox> {
  bool _down = false;

  bool get _squishy => Motion.motionEnabled && widget.onTap != null;

  void _setDown(bool v) {
    if (_squishy && _down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    Widget card = Card(
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        borderRadius: BorderRadius.circular(Radii.card),
        child: Padding(padding: widget.padding, child: widget.child),
      ),
    );
    // Tappable cards compress a hair under the finger — the whole app feels
    // physically pressable without changing any layout.
    if (_squishy) {
      card = Listener(
        onPointerDown: (_) => _setDown(true),
        onPointerUp: (_) => _setDown(false),
        onPointerCancel: (_) => _setDown(false),
        child: AnimatedScale(
          scale: _down ? 0.982 : 1,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: card,
        ),
      );
    }
    // Every card arrives instead of popping: a light fade + rise the first
    // time it is mounted (skipped in tests and under reduced motion).
    return EnterMotion(child: card);
  }
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
                fontSize: FontSizes.title,
                fontWeight: FontWeight.w700,
                color: onSurface.withValues(alpha: 0.9),
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
///
/// The bar also owns the saving feedback: while [onPressed] is running the
/// button shows a spinner and its label switches to “Saving…”. Taps during
/// that window are ignored, so a nervous double-tap cannot record the same
/// entry twice. If the callback throws, a red snackbar reports the failure
/// instead of silently swallowing it.
class FormActionBar extends StatefulWidget {
  const FormActionBar({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.check_rounded,
  });

  final String label;
  final Future<void> Function()? onPressed;
  final IconData icon;

  @override
  State<FormActionBar> createState() => _FormActionBarState();
}

class _FormActionBarState extends State<FormActionBar> {
  bool _busy = false;

  Future<void> _handleTap() async {
    final action = widget.onPressed;
    // Ignore taps while a save is already in flight (double-tap guard).
    if (_busy || action == null) return;
    Haptics.confirm();
    // Resolved before the await so nothing below reads the BuildContext.
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
    } catch (_) {
      showMessengerSnack(
        messenger,
        'Saving failed. Please try again.',
        error: true,
      );
    } finally {
      // The page usually pops itself after a successful save, so this state
      // may already be disposed by the time the future completes.
      if (mounted) setState(() => _busy = false);
    }
  }

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
              onPressed: widget.onPressed == null ? null : _handleTap,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(widget.icon),
              label: Text((_busy ? 'Saving…' : widget.label).tr),
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
    this.maxWidth,
  });

  final String text;
  final Color color;
  final IconData? icon;
  final bool dense;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final label = Text(
      text.tr,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: dense ? 11.5 : 12.5,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    );
    return Container(
      constraints: maxWidth == null ? null : BoxConstraints(maxWidth: maxWidth!),
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
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
            Icon(icon, size: dense ? 13 : 15, color: color),
            const SizedBox(width: 4),
          ],
          if (maxWidth == null) label else Flexible(child: label),
        ],
      ),
    );
  }
}

/// ---------------- Empty state ----------------
class EmptyState extends StatefulWidget {
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
  State<EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<EmptyState>
    with TickerProviderStateMixin {
  /// Slow breathing of the icon: the empty state stays gently alive.
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  );

  /// One-shot: the dashed ledger line under the icon draws itself.
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (Motion.motionEnabled) _draw.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.ambientOn(context)) {
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
    } else {
      _breath.stop();
      _breath.value = 0;
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    _draw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final icon = widget.icon;
    final title = widget.title;
    final text = widget.text;
    final actionLabel = widget.actionLabel;
    final onAction = widget.onAction;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(26),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _breath,
                builder: (context, child) {
                  final b = Curves.easeInOut.transform(_breath.value);
                  return Opacity(
                    opacity: 1 - 0.14 * b,
                    child: Transform.scale(scale: 1 + 0.05 * b, child: child),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 34,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
              // The dashed rule of a ledger page, drawn in once.
              SizedBox(
                height: 12,
                width: 190,
                child: AnimatedBuilder(
                  animation: _draw,
                  builder: (context, _) => CustomPaint(
                    painter: _DashLinePainter(
                      t: Motion.motionEnabled
                          ? Curves.easeOutCubic.transform(_draw.value)
                          : 1,
                      line: onSurface.withValues(alpha: 0.2),
                      tip: Theme.of(context).colorScheme.primary
                          .withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                title.tr,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (text != null) ...[
                const SizedBox(height: 8),
                Text(
                  text.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.6,
                    color: onSurface.withValues(alpha: 0.72),
                  ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: onAction,
                  child: Text(actionLabel.tr),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Search input shared by the list pages.
///
/// Keeps search affordances consistent and gives users an explicit, labeled
/// clear action. The controller is owned by the page so its query survives
/// tab changes alongside the filters.
class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        autocorrect: false,
        decoration: InputDecoration(
          hintText: hint.tr,
          hintMaxLines: 1,
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search'.tr,
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
        onChanged: onChanged,
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
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
    this.livePreview = true,
    this.textInputAction = TextInputAction.done,
  });

  final TextEditingController controller;
  final String label;
  final String currency;
  final bool autofocus;
  final String? Function(String?)? validator;
  final VoidCallback? onChanged;

  /// Keyboard action button. Pass [TextInputAction.next] when another field
  /// follows, so the user can move on without reaching for the screen.
  final TextInputAction textInputAction;

  /// Shows a live, grouped preview of the entered amount below the field
  /// (e.g. typing `1500000` renders `= 1,500,000 Toman` while typing),
  /// so users always see the value that will actually be saved.
  final bool livePreview;

  @override
  Widget build(BuildContext context) {
    final decimals = Money.decimals(currency);
    final field = TextFormField(
      controller: controller,
      autofocus: autofocus,
      textInputAction: textInputAction,
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
        _groupAmount(controller, decimals);
        // Supplying onEditingComplete turns off Flutter's own focus handling,
        // so advancing to the next field is done by hand here: move from the
        // node that currently has focus, exactly like TextField would.
        if (textInputAction == TextInputAction.next) {
          FocusManager.instance.primaryFocus?.nextFocus();
        } else {
          FocusScope.of(context).unfocus();
        }
      },
      onFieldSubmitted: (_) => _groupAmount(controller, decimals),
    );

    if (!livePreview) return field;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final parsed = parseAmount(value.text);
        final preview = value.text.trim().isNotEmpty && parsed > 0
            ? Money.text(parsed, currency: currency)
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            field,
            AnimatedSize(
              duration: const Duration(milliseconds: 160),
              alignment: Alignment.topCenter,
              child: preview == null
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '= $preview',
                        textDirection: TextDirection.ltr,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary
                              .withValues(alpha: 0.9),
                        ),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Rewrite the field with grouped digits, keeping the caret at the end.
void _groupAmount(TextEditingController controller, int decimals) {
  final s = groupedNumber(parseAmount(controller.text), decimals: decimals);
  controller.value = TextEditingValue(
    text: s,
    selection: TextSelection.collapsed(offset: s.length),
  );
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
          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
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
    this.isChild,
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

  /// When provided, matching items render indented in the pick sheet
  /// (one level of nesting, e.g. subcategories under their category).
  final bool Function(T)? isChild;

  @override
  Widget build(BuildContext context) {
    final hasValue = value != null;
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final res = await showPickSheet<T>(
          context,
          title: sheetTitle ?? label,
          items: items,
          current: value,
          labelOf: labelOf,
          subOf: subOf,
          iconOf: iconOf,
          clearable: clearable,
          searchHint: searchHint,
          extraActionLabel: extraActionLabel,
          isChild: isChild,
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
            fontSize: 14.5,
            fontWeight: hasValue ? FontWeight.w600 : FontWeight.w400,
            color: hasValue ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// The result of the shared pick sheet: a chosen item, an explicit "none"
/// (clearable fields), or a request for the sheet's extra action.
class PickResult<T> {
  final T? value;
  final bool cleared;
  final bool extra;
  const PickResult(this.value, {this.cleared = false, this.extra = false});
}

/// Opens the shared selection sheet and returns what the user picked.
///
/// [SelectField] uses it internally, and forms that offer a compact chip row
/// (top customers, categories) reuse it behind a "see all" chip, so the sheet
/// stays one widget with one behavior everywhere.
Future<PickResult<T>?> showPickSheet<T>(
  BuildContext context, {
  required String title,
  required List<T> items,
  required T? current,
  required String Function(T) labelOf,
  String Function(T)? subOf,
  IconData Function(T)? iconOf,
  bool clearable = false,
  String searchHint = 'Search...',
  String? extraActionLabel,
  bool Function(T)? isChild,
}) {
  return showLedgerSheet<PickResult<T>>(
    context,
    builder: (_) => _PickSheet<T>(
      title: title,
      items: items,
      current: current,
      labelOf: labelOf,
      isChild: isChild,
      subOf: subOf,
      iconOf: iconOf,
      clearable: clearable,
      searchHint: searchHint,
      extraActionLabel: extraActionLabel,
    ),
  );
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
    this.isChild,
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

  /// When provided, items for which it returns true render indented
  /// (one level of nesting, e.g. subcategories under their category).
  final bool Function(T)? isChild;

  @override
  State<_PickSheet<T>> createState() => _PickSheetState<T>();
}

class _PickSheetState<T> extends State<_PickSheet<T>> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isChild = widget.isChild;
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
      // The sheet's surface is a Material (not a decorated Container):
      // ListTiles with a tap handler assert that no colored DecoratedBox
      // sits between them and their nearest Material ancestor.
      builder: (ctx, controller) => Material(
        color: theme.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: Column(
          children: [
            const SizedBox(height: 10),
            SheetHandle(),
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
                    tooltip: 'Close'.tr,
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
                        const PickResult(null, cleared: true),
                      ),
                    ),
                  for (final item in items)
                    ListTile(
                      leading: widget.iconOf == null
                          ? null
                          : Icon(widget.iconOf!(item), size: 20),
                      title: isChild != null && isChild(item)
                          ? Padding(
                              padding:
                                  const EdgeInsetsDirectional.only(
                                    start: 24,
                                  ),
                              child: Text(widget.labelOf(item).tr),
                            )
                          : Text(widget.labelOf(item).tr),
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
                      onTap: () => Navigator.pop(context, PickResult(item)),
                    ),
                  if (widget.extraActionLabel != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
                      child: FilledButton.tonalIcon(
                        onPressed: () => Navigator.pop(
                          context,
                          const PickResult(null, extra: true),
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
    this.textInputAction,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? icon;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  /// Keyboard action button; single-line fields default to "next" so tabbing
  /// through a form never requires tapping the screen. Pass
  /// [TextInputAction.done] on the last field of a form.
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textInputAction:
          textInputAction ?? (maxLines == 1 ? TextInputAction.next : null),
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

void showSnack(
  BuildContext context,
  String message, {
  bool error = false,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 2),
}) {
  showMessengerSnack(
    ScaffoldMessenger.of(context),
    message,
    error: error,
    actionLabel: actionLabel,
    onAction: onAction,
    duration: duration,
  );
}

/// Same as [showSnack], but for callers that already hold the messenger.
///
/// Saving flows resolve the messenger *before* their `await` and then use this
/// function afterwards, so no `BuildContext` is read once the async work has
/// started (see `use_build_context_synchronously`).
void showMessengerSnack(
  ScaffoldMessengerState messenger,
  String message, {
  bool error = false,
  String? actionLabel,
  VoidCallback? onAction,
  Duration duration = const Duration(seconds: 2),
}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message.tr),
        backgroundColor: error ? const Color(0xFFB91C1C) : null,
        duration: actionLabel == null ? duration : const Duration(seconds: 5),
        action: actionLabel == null
            ? null
            : SnackBarAction(
                label: actionLabel.tr,
                onPressed: () => onAction?.call(),
              ),
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

  Color get _color => txn.kind.color;

  @override
  Widget build(BuildContext context) {
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    final compactAmounts = MediaQuery.sizeOf(context).width < 360;
    // Notes written by the app itself ('Payment received', 'Imported from
    // SMS', ...) are localization keys; free-typed user notes simply miss
    // the map and render as-is.
    final title = txn.note.isNotEmpty ? txn.note.tr : categoryName.tr;
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
          fontSize: FontSizes.caption,
          color: onSurfaceVariant,
        ),
      ),
      trailing: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: compactAmounts ? 104 : 160),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            CopyMoney(
              value: txn.amount,
              child: Text(
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
                compact: compactAmounts,
              ),
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.ltr,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _color,
              ),
            ),
            ),
            if (txn.currency != 'IRT' || txn.rateToBase != 1)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  Money.text(
                    txn.amount * txn.rateToBase,
                    withSymbol: false,
                    compact: compactAmounts,
                  ),
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontSize: FontSizes.micro,
                    color: onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// ---------------- Collapsible section ----------------
/// A card whose header (title, optional summary, and chevron) is always
/// visible while the body expands on tap.
///
/// Used for reference content such as charts: the section stays one glance
/// away, but the page does not have to carry it at full height all the time.
/// The header summary is a good place for the key number, so collapsing never
/// hides the headline figure.
class CollapsibleCard extends StatefulWidget {
  const CollapsibleCard({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.summary,
    this.bodyPadding = const EdgeInsets.fromLTRB(14, 0, 14, 14),
    this.initiallyExpanded = false,
  });

  final String title;
  final Widget child;
  final IconData? icon;

  /// Key figure shown in the header, always visible.
  final Widget? summary;
  final EdgeInsets bodyPadding;
  final bool initiallyExpanded;

  @override
  State<CollapsibleCard> createState() => _CollapsibleCardState();
}

class _CollapsibleCardState extends State<CollapsibleCard> {
  late bool _expanded = widget.initiallyExpanded;

  void _toggle() {
    Haptics.selection();
    setState(() => _expanded = !_expanded);
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            child: InkWell(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                child: Row(
                  children: [
                    if (widget.icon != null) ...[
                      Icon(
                        widget.icon,
                        size: 17,
                        color: onSurface.withValues(alpha: 0.6),
                      ),
                      const SizedBox(width: Insets.sm),
                    ],
                    Expanded(
                      child: Text(
                        widget.title.tr,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: FontSizes.body,
                          fontWeight: FontWeight.w700,
                          color: onSurface.withValues(alpha: 0.85),
                        ),
                      ),
                    ),
                    if (widget.summary != null) ...[
                      Flexible(
                        fit: FlexFit.loose,
                        child: Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.centerEnd,
                            child: widget.summary!,
                          ),
                        ),
                      ),
                      const SizedBox(width: Insets.xs),
                    ],
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: Motion.adaptive(context, Motion.expand),
                      child: Icon(
                        Icons.expand_more_rounded,
                        size: 20,
                        color: onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: Motion.adaptive(context, Motion.expand),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            child: _expanded
                ? Padding(padding: widget.bodyPadding, child: widget.child)
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// ---------------- Filter toggle ----------------
/// Square button that opens the filter panel. A count badge shows how many
/// filters are active, and the icon highlights while the panel is open, so the
/// current filter state stays visible even though the chips are tucked away.
class FilterToggleButton extends StatelessWidget {
  const FilterToggleButton({
    super.key,
    required this.activeCount,
    required this.expanded,
    required this.onPressed,
  });

  final int activeCount;
  final bool expanded;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highlighted = expanded || activeCount > 0;
    return Semantics(
      button: true,
      label: 'Filters'.tr,
      value: activeCount == 0
          ? null
          : 'Active filters: {count}'.trArgs({'count': activeCount}),
      expanded: expanded,
      onTap: () {
        Haptics.tap();
        onPressed();
      },
      child: ExcludeSemantics(
        child: Tooltip(
          message: 'Filters'.tr,
          child: Material(
            color: highlighted
                ? scheme.primary.withValues(alpha: 0.12)
                : Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(Radii.field),
            child: InkWell(
              borderRadius: BorderRadius.circular(Radii.field),
              onTap: () {
                Haptics.tap();
                onPressed();
              },
              child: Container(
                width: 52,
                height: 56,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.field),
                  border: Border.all(
                    color: highlighted
                        ? scheme.primary.withValues(alpha: 0.5)
                        : Theme.of(context).dividerColor,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 20,
                      color: highlighted ? scheme.primary : null,
                    ),
                    if (activeCount > 0)
                      PositionedDirectional(
                        top: 8,
                        end: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$activeCount',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: scheme.onPrimary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Removable chip describing one active filter; tapping it clears that filter.
class FilterPill extends StatelessWidget {
  const FilterPill({
    super.key,
    required this.label,
    required this.onClear,
    this.icon,
  });

  final String label;
  final VoidCallback onClear;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Clear filter: {filter}'.trArgs({'filter': label}),
      onTap: onClear,
      child: ExcludeSemantics(
        child: Material(
          color: scheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onClear,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: Taps.minHeight),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 16, color: scheme.primary),
                      const SizedBox(width: Insets.xs),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: FontSizes.caption,
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: Insets.xs),
                    Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: scheme.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ---------------- Swipe hint ----------------
/// Revealed behind a row while it is being swiped: the icon and the name of the
/// action the swipe will perform.
///
/// A gesture has nothing to tap, so the hint is what makes it discoverable and
/// what tells the two directions apart. The action itself is confirmed by the
/// row snapping back (the row is never dismissed), so nothing disappears from
/// the list.
class SwipeHint extends StatelessWidget {
  const SwipeHint({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.alignment,
    this.borderRadius,
  });

  final IconData icon;
  final String label;
  final Color color;

  /// Where the hint sits: the leading edge for a right swipe, the trailing edge
  /// for a left swipe.
  final AlignmentGeometry alignment;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: borderRadius,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: Insets.sm),
          Flexible(
            child: Text(
              label.tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: FontSizes.small,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Runs [action] on the frame after a swipe has been let go, so a swiped row
/// is already on its way home before anything opens over it.
///
/// `Dismissible` slides its row a full row-width off-screen *before* it calls
/// `confirmDismiss`, and it leaves the row there until that future resolves.
/// Awaiting a sheet or a page inside the callback therefore parks the row off
/// screen for the whole time the sheet is open — visible as a coloured gap in
/// the list through the sheet's translucent barrier. Returning `false`
/// straight away and opening on the next frame lets the row spring home and
/// the sheet rise at the same time.
///
/// Use it like this:
///
/// ```dart
/// confirmDismiss: (direction) {
///   afterSwipeSnapBack(context, () => showPaymentSheet(context, ...));
///   return Future.value(false);
/// },
/// ```
void afterSwipeSnapBack(BuildContext context, Future<void> Function() action) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!context.mounted) return;
    action();
  });
}

/// ---------------- Status dot ----------------
/// Tiny colored dot for a status that would otherwise need a full chip.
///
/// The label is not dropped: screen readers announce it and long-pressing the
/// dot shows it as a tooltip.
class StatusDot extends StatelessWidget {
  const StatusDot({
    super.key,
    required this.color,
    required this.label,
    this.size = 8,
  });

  final Color color;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label.tr,
      child: Tooltip(
        message: label.tr,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
      ),
    );
  }
}

/// The dashed rule of a ledger page drawing itself under the empty-state
/// icon; a small dot rides the tip like a pen while it is still moving.
class _DashLinePainter extends CustomPainter {
  _DashLinePainter({required this.t, required this.line, required this.tip});

  final double t;
  final Color line;
  final Color tip;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    const dash = 9.0;
    const gap = 6.5;
    final y = size.height / 2 + 2;
    final total = size.width * t;
    final paint = Paint()
      ..color = line
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    var x = 0.0;
    while (x < total) {
      final end = x + dash > total ? total : x + dash;
      if (end > x) canvas.drawLine(Offset(x, y), Offset(end, y), paint);
      x += dash + gap;
    }
    if (t < 1) {
      canvas.drawCircle(Offset(total, y), 2.4, Paint()..color = tip);
    }
  }

  @override
  bool shouldRepaint(_DashLinePainter old) =>
      old.t != t || old.line != line || old.tip != tip;
}

/// The little grab handle at the top of every bottom sheet.
///
/// One shared widget instead of ten hand-rolled containers: always
/// centered, always 44x4 with soft corners — in every sheet of the app
/// (ledger, payment, quick record, SMS review, pickers...). `Align` keeps
/// it centered even inside `CrossAxisAlignment.stretch` columns, which is
/// where the old handles used to stretch to the full sheet width.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: 44,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// ---------------- Copy on long-press ----------------
/// Long-press any money amount to copy the plain number to the clipboard.
///
/// Feedback: a haptic tick, the number pops, and a small "Copied" chip
/// floats up and fades. No dialogs, no menus — the fastest possible path
/// from "I see this number" to "it is in the clipboard".
class CopyMoney extends StatefulWidget {
  const CopyMoney({super.key, required this.value, required this.child});

  final double value;
  final Widget child;

  @override
  State<CopyMoney> createState() => _CopyMoneyState();
}

class _CopyMoneyState extends State<CopyMoney> {
  bool _pop = false;

  Future<void> _copy() async {
    Haptics.tap();
    await Clipboard.setData(
      ClipboardData(text: widget.value.round().toString()),
    );
    if (!mounted) return;
    setState(() => _pop = true);
    Future.delayed(const Duration(milliseconds: 240), () {
      if (mounted) setState(() => _pop = false);
    });
    _showChip();
  }

  void _showChip() {
    if (!Motion.motionEnabled) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    final box = context.findRenderObject();
    if (overlay == null || box is! RenderBox || !box.hasSize) return;
    final at = box.localToGlobal(box.size.center(Offset.zero));
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _CopyChip(
        at: at,
        onDone: () {
          if (entry.mounted) entry.remove();
        },
      ),
    );
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: _copy,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1, end: _pop ? 1.10 : 1),
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: widget.child,
      ),
    );
  }
}

class _CopyChip extends StatefulWidget {
  const _CopyChip({required this.at, required this.onDone});

  final Offset at;
  final VoidCallback onDone;

  @override
  State<_CopyChip> createState() => _CopyChipState();
}

class _CopyChipState extends State<_CopyChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  )
    ..addListener(() {
      if (_c.isCompleted) widget.onDone();
    })
    ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) {
          final t = _c.value;
          final appear = Curves.easeOutBack.transform(
            (t / 0.22).clamp(0.0, 1.0),
          );
          final fade = t < 0.72 ? 1.0 : 1 - ((t - 0.72) / 0.28).clamp(0.0, 1.0);
          final rise = 30 * Curves.easeOutCubic.transform(t);
          return Opacity(
            opacity: fade,
            child: Transform.translate(
              offset: Offset(widget.at.dx - 46, widget.at.dy - 52 - rise),
              child: Transform.scale(scale: appear, child: child),
            ),
          );
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.inverseSurface,
            borderRadius: BorderRadius.circular(11),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_rounded, size: 14, color: scheme.inversePrimary),
                const SizedBox(width: 5),
                Text(
                  'Copied'.tr,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ---------------- Swipe row actions ----------------
/// One row action revealed by a trailing swipe.
class SwipeAction {
  const SwipeAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;

  /// Localization key, translated at render time.
  final String label;
  final Color color;
  final VoidCallback onTap;
}

/// Swipe a row toward its trailing edge to fan open a panel of actions.
///
/// Direction-aware (RTL mirrors everything), rubber-bands past full open,
/// snaps open or shut on fling, ticks once when the release threshold is
/// crossed, and each button scales in with a small stagger. Tapping the row
/// while open closes the panel instead of activating the row.
class SwipeActions extends StatefulWidget {
  const SwipeActions({
    super.key,
    required this.child,
    required this.actions,
    this.panelWidth = 150,
  });

  final Widget child;
  final List<SwipeAction> actions;
  final double panelWidth;

  @override
  State<SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<SwipeActions>
    with SingleTickerProviderStateMixin {
  /// A flick decides on its own, in either direction.
  static const double _flingVelocity = 600;

  double _open = 0;
  double _snapFrom = 0;
  double _snapTarget = 0;
  bool _ticked = false;
  bool _watchingOutside = false;
  late final AnimationController _snap = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );

  @override
  void dispose() {
    _watchOutside(false);
    _snap.dispose();
    super.dispose();
  }

  double get _current => _snap.isAnimating
      ? _snapFrom +
            (_snapTarget - _snapFrom) *
                Curves.easeOutCubic.transform(_snap.value)
      : _open;

  /// Reads the animated value *before* the spring is stopped. `_open` holds the
  /// target, so re-grabbing a row that is still settling would otherwise
  /// teleport it to where it was heading.
  double _adopt() {
    final now = _current;
    _snap.stop();
    return now;
  }

  void _animateTo(double target) {
    final from = _current;
    // Watching for outside touches is also what keeps two rows from being open
    // at once: the pointer-down that starts a swipe on another row lands
    // outside this one and closes it first.
    _watchOutside(target > 0);
    // Nothing to animate. Starting the controller anyway would rebuild the row
    // for 200 ms and keep `pumpAndSettle` busy for no reason.
    if (from == target && !_snap.isAnimating && _open == target) return;
    // `_open` is read by the PopScope above and by the buttons' `enabled`, and
    // neither of them sits under the AnimatedBuilder that rebuilds on every
    // tick. Without setState the row would close visually while `canPop` stayed
    // false — and the page could then never be popped again.
    setState(() {
      _snapFrom = from;
      _snapTarget = target;
      _open = target;
    });
    _snap.forward(from: 0);
  }

  void _watchOutside(bool on) {
    if (on == _watchingOutside) return;
    _watchingOutside = on;
    final router = WidgetsBinding.instance.pointerRouter;
    if (on) {
      router.addGlobalRoute(_onGlobalPointerDown);
    } else {
      router.removeGlobalRoute(_onGlobalPointerDown);
    }
  }

  /// Closes the row when anything else in the app is touched — another row, the
  /// list behind it, the navigation bar. Without this an opened row stayed open
  /// until it was touched again, and several rows could be open at once.
  void _onGlobalPointerDown(PointerEvent e) {
    if (e is! PointerDownEvent || !mounted) return;
    final box = context.findRenderObject();
    if (box is RenderBox &&
        box.hasSize &&
        box.paintBounds.contains(box.globalToLocal(e.position))) {
      // Inside this row: tapping its content already closes it, and the action
      // buttons must stay tappable, so this pointer is the row's own business.
      return;
    }
    _animateTo(0);
  }

  double _sign(BuildContext context) =>
      Directionality.of(context) == TextDirection.rtl ? 1 : -1;

  void _onUpdate(DragUpdateDetails d) {
    final now = _adopt();
    final delta = (d.delta.dx * _sign(context)) / widget.panelWidth;
    setState(() => _open = (now + delta).clamp(-0.02, 1.25));
    if (!_ticked && _open >= 0.5) {
      _ticked = true;
      Haptics.selection();
    } else if (_ticked && _open < 0.45) {
      _ticked = false;
    }
  }

  void _onEnd(DragEndDetails d) {
    final v = (d.primaryVelocity ?? 0) * _sign(context);
    if (v < -_flingVelocity) {
      // Flicking an open row shut has to close it, even though the drag had not
      // travelled back past the halfway point yet — the old check re-opened it.
      _animateTo(0);
    } else if (_open > 0.5 || v > _flingVelocity) {
      _animateTo(1);
    } else {
      _animateTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.actions.isEmpty) return widget.child;
    // An open row is a mode of its own, so the system back button — and
    // Android's predictive back — folds the row instead of leaving the page.
    // Touching anywhere else already closes it, which is also what keeps a
    // single row open at a time, so at most one row ever refuses to pop.
    //
    // The scope stays in the tree whether or not it refuses: swapping it in
    // and out would remount the row underneath and replay its enter motion.
    return PopScope(
      canPop: _open < 0.99,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _animateTo(0);
      },
      child: _row(context),
    );
  }

  Widget _row(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      onHorizontalDragCancel: () => _animateTo(0),
      child: AnimatedBuilder(
        animation: _snap,
        builder: (context, child) {
          final raw = _current;
          final t = raw.clamp(0.0, 1.0);
          final dx = _sign(context) * widget.panelWidth * t;
          return Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: SizedBox(
                    width: widget.panelWidth,
                    child: Row(
                      children: [
                        for (var i = 0; i < widget.actions.length; i++)
                          Expanded(
                            child: _SwipeButton(
                              action: widget.actions[i],
                              appear: ((t * widget.actions.length) - i)
                                  .clamp(0.0, 1.0),
                              // Gated on the target rather than on the
                              // animated value: waiting for the 200 ms settle
                              // to reach 0.99 left the buttons dead for ~160 ms
                              // after the row had visibly opened, so a quick
                              // swipe-then-tap did nothing at all.
                              enabled: _open >= 0.99,
                              onUsed: () => _animateTo(0),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(dx, 0),
                child: raw > 0.02
                    ? GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _animateTo(0),
                        child: child,
                      )
                    : child,
              ),
            ],
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _SwipeButton extends StatelessWidget {
  const _SwipeButton({
    required this.action,
    required this.appear,
    required this.enabled,
    required this.onUsed,
  });

  final SwipeAction action;
  final double appear;
  final bool enabled;
  final VoidCallback onUsed;

  @override
  Widget build(BuildContext context) {
    final e = Curves.easeOutBack.transform(appear);
    return Opacity(
      opacity: appear.clamp(0.0, 1.0),
      child: Transform.scale(
        scale: 0.4 + 0.6 * e,
        child: Semantics(
          button: true,
          label: action.label.tr,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: enabled
                ? () {
                    onUsed();
                    action.onTap();
                  }
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: action.color.withValues(alpha: 0.13),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(action.icon, size: 18, color: action.color),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    action.label.tr,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                      color: action.color,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- Shared entry-form sections ----------------
// The transaction entry page and the SMS review sheet share these pieces
// so the two record flows look like one flow, wherever they appear.

/// One line of kind tiles, color-coded exactly like the ledger rows, so a
/// selection is confirmed at a glance while the keyboard is open on the
/// amount.
class TxnKindStrip extends StatelessWidget {
  const TxnKindStrip({
    super.key,
    required this.kinds,
    required this.selected,
    required this.onSelect,
  });

  final List<TxnKind> kinds;
  final TxnKind selected;
  final ValueChanged<TxnKind> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          for (final k in kinds)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: TxnKindTile(
                kind: k,
                selected: selected == k,
                onSelect: () => onSelect(k),
              ),
            ),
        ],
      ),
    );
  }
}

/// One kind tile: the kind's accent color carries the selection.
class TxnKindTile extends StatelessWidget {
  const TxnKindTile({
    super.key,
    required this.kind,
    required this.selected,
    required this.onSelect,
  });

  final TxnKind kind;
  final bool selected;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final color = kind.color;
    return Semantics(
      button: true,
      selected: selected,
      label: kind.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () {
          Haptics.selection();
          onSelect();
        },
        child: AnimatedContainer(
          duration: Motion.adaptive(context, Motion.quick),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.5)
                  : theme.dividerColor,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                kind.icon,
                size: 17,
                color: selected ? color : onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 2),
              Text(
                kind.shortLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? color : onSurface.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Business/personal scope: a full-width 44dp segment plus the one-line
/// hint that says what the choice does to the books.
class ScopeSegment extends StatelessWidget {
  const ScopeSegment({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final TxnScope selected;
  final ValueChanged<TxnScope> onSelect;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedButton<TxnScope>(
          segments: [
            for (final sc in TxnScope.values)
              ButtonSegment(value: sc, label: Text(sc.label)),
          ],
          selected: {selected},
          onSelectionChanged: (s) => onSelect(s.first),
          style: SegmentedButton.styleFrom(
            // Compact density would shave this down to ~32dp, which is too
            // small to hit reliably; ask for a real 44dp instead.
            minimumSize: const Size(0, Taps.minHeight),
            textStyle: const TextStyle(fontSize: 12),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          selected.hint,
          style: TextStyle(
            fontSize: 11,
            color: onSurface.withValues(alpha: 0.55),
          ),
        ),
      ],
    );
  }
}

/// A small section caption; [label] is a localization key.
class SectionCaption extends StatelessWidget {
  const SectionCaption(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        label.tr,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface
              .withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

/// One horizontal strip of chips. A fixed height keeps the layout from
/// jumping when a strip appears or disappears.
class ChipStrip extends StatelessWidget {
  const ChipStrip({super.key, required this.chips});

  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          for (final chip in chips)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: chip,
            ),
        ],
      ),
    );
  }
}

/// A tappable preset chip: recent-entry repeats, contacts, and the "see
/// all" / "add" openers. Long labels ellipsize inside a fixed width so a
/// strip always stays exactly one line.
class PresetChip extends StatelessWidget {
  const PresetChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    super.key,
  });

  final IconData icon;

  /// Plain display text: already translated for keys, or user data (a
  /// contact name) that must not be translated.
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    final accent = selected
        ? scheme.primary
        : onSurface.withValues(alpha: 0.6);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.adaptive(context, Motion.quick),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.12)
                : onSurface.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.45)
                  : onSurface.withValues(alpha: 0.14),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: accent),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? scheme.primary
                        : onSurface.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Live balance of a selected contact, so "how much do they owe" is
/// answered without leaving the form.
class ContactBalanceCard extends StatelessWidget {
  const ContactBalanceCard({
    super.key,
    required this.customer,
    required this.balance,
  });

  final Customer customer;
  final double balance;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 16,
            color: scheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              customer.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          MoneyText(
            balance,
            signed: true,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
