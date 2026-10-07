import 'package:flutter/material.dart';

import '../../core/format_utils.dart';
import '../../core/localization.dart';

/// The row of dots showing how many digits have been typed so far.
class PinDots extends StatelessWidget {
  const PinDots({
    super.key,
    required this.length,
    required this.filled,
    this.error = false,
  });

  final int length;
  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = error ? scheme.error : scheme.primary;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < length; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.symmetric(horizontal: 7),
            width: 13,
            height: 13,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < filled ? active : Colors.transparent,
              border: Border.all(
                color: i < filled
                    ? active
                    : scheme.onSurface.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
          ),
      ],
    );
  }
}

/// A 3x4 numeric keypad. Deliberately not a text field: a PIN should never
/// reach the system keyboard, its clipboard, or its autofill history.
class PinPad extends StatelessWidget {
  const PinPad({
    super.key,
    required this.onDigit,
    required this.onBackspace,
    this.leading,
    this.enabled = true,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;

  /// Optional extra key in the bottom-left slot (used for biometrics).
  final Widget? leading;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final persian = AppLocalization.languageCode == 'fa';
    String label(int digit) =>
        persian ? Fmt.toFaDigits('$digit') : '$digit';

    Widget key(int digit) => _PinKey(
      onPressed: enabled ? () => onDigit('$digit') : null,
      child: Text(
        label(digit),
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
      ),
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in const [
            [1, 2, 3],
            [4, 5, 6],
            [7, 8, 9],
          ])
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [for (final digit in row) key(digit)],
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: _keyWidth,
                height: _keyHeight,
                child: leading == null ? null : Center(child: leading),
              ),
              key(0),
              _PinKey(
                onPressed: enabled ? onBackspace : null,
                tooltip: 'Delete'.tr,
                child: const Icon(Icons.backspace_outlined, size: 22),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const double _keyWidth = 78;
const double _keyHeight = 62;

class _PinKey extends StatelessWidget {
  const _PinKey({required this.child, required this.onPressed, this.tooltip});

  final Widget child;

  /// Null disables the key; it keeps its shape so the grid never shifts.
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: _keyWidth,
      height: _keyHeight,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          foregroundColor: Theme.of(context).colorScheme.onSurface,
        ),
        child: child,
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
