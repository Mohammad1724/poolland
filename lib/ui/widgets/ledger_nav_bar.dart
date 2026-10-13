import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// One destination of [LedgerNavBar].
class LedgerNavDestination {
  const LedgerNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

/// The bottom navigation bar with the app's "elastic pill" motion.
///
/// Geometry and colors mirror the themed Material [NavigationBar] (equal
/// cells, 80dp tall, same indicator color) so layouts and tests that measure
/// the bar keep working. The difference is the indicator: when the selection
/// moves, the leading edge arrives first and the trailing edge catches up, so
/// the pill stretches like elastic between destinations and snaps back to
/// size. The newly selected icon also gets a small bounce.
class LedgerNavBar extends StatefulWidget {
  const LedgerNavBar({
    super.key,
    required this.index,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int index;
  final ValueChanged<int> onDestinationSelected;
  final List<LedgerNavDestination> destinations;

  @override
  State<LedgerNavBar> createState() => _LedgerNavBarState();
}

class _LedgerNavBarState extends State<LedgerNavBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pill = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    value: 1,
  );
  // Leading edge arrives first, trailing edge catches up: the span between
  // the two curves is what makes the pill stretch like elastic.
  late final CurvedAnimation _fast = CurvedAnimation(
    parent: _pill,
    curve: const Interval(0, 0.55, curve: Curves.easeOutCubic),
  );
  late final CurvedAnimation _slow = CurvedAnimation(
    parent: _pill,
    curve: const Interval(0.30, 1.0, curve: Curves.easeOutQuint),
  );
  int _from = 0;

  @override
  void initState() {
    super.initState();
    _from = widget.index;
  }

  @override
  void didUpdateWidget(LedgerNavBar old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      _from = old.index;
      _pill.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _fast.dispose();
    _slow.dispose();
    _pill.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final navTheme = NavigationBarTheme.of(context);
    final background = navTheme.backgroundColor ?? scheme.surfaceContainer;
    final indicator =
        navTheme.indicatorColor ?? scheme.primary.withValues(alpha: 0.12);
    final height = navTheme.height ?? 80;
    final n = widget.destinations.length;

    return Material(
      color: background,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cellW = constraints.maxWidth / n;
              // The Row lays cells out in the ambient text direction, but
              // `Positioned.left` is always physical: mirror the centers in
              // RTL or the pill lands on the wrong tab.
              final rtl = Directionality.of(context) == TextDirection.rtl;
              double centerOf(int i) {
                final c = (i + 0.5) * cellW;
                return rtl ? constraints.maxWidth - c : c;
              }
              return Stack(
                children: [
                  // The elastic pill. Two curves on one controller: the
                  // leading edge (fast) reaches the destination first, the
                  // trailing edge (slow) catches up — the span between them
                  // is the stretch.
                  AnimatedBuilder(
                    animation: _pill,
                    builder: (context, _) {
                      final a = lerpDouble(
                        centerOf(_from),
                        centerOf(widget.index),
                        _fast.value,
                      )!;
                      final b = lerpDouble(
                        centerOf(_from),
                        centerOf(widget.index),
                        _slow.value,
                      )!;
                      final left = math.min(a, b) - 32;
                      final width = (math.max(a, b) - math.min(a, b)) + 64;
                      return Positioned(
                        left: left,
                        top: 12,
                        width: width,
                        height: 34,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: indicator,
                            borderRadius: BorderRadius.circular(17),
                          ),
                        ),
                      );
                    },
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < n; i++)
                        Expanded(child: _cell(context, i, cellW)),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, int i, double cellW) {
    final scheme = Theme.of(context).colorScheme;
    final dest = widget.destinations[i];
    final selected = i == widget.index;
    final labelColor = selected ? scheme.primary : scheme.onSurfaceVariant;
    final labelSize = cellW < 68 ? 10.0 : 12.0;

    return Semantics(
      button: true,
      selected: selected,
      label: dest.label,
      // No `Tooltip`: the destination's name is already printed under its icon
      // and repeated in the semantics label, so all the tooltip added was a
      // long-press recognizer competing in the gesture arena on every cell of
      // the bar — and a bubble repeating the text the user is looking at.
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        splashColor: scheme.primary.withValues(alpha: 0.10),
        highlightColor: scheme.primary.withValues(alpha: 0.06),
        onTap: () => widget.onDestinationSelected(i),
        child: SizedBox.expand(
          // The selected icon bounces once while the pill travels. Scaling the
          // content instead of the cell keeps the tap target exactly one cell
          // wide: an InkWell scaled up 22% reaches into its neighbours, so a
          // quick second tap can land on the tab that just bounced.
          child: AnimatedBuilder(
            animation: _pill,
            builder: (context, child) {
              final bounce = selected && _pill.value < 1
                  ? math.sin(math.min(_pill.value / 0.65, 1.0) * math.pi)
                  : 0.0;
              return Transform.scale(scale: 1 + 0.22 * bounce, child: child);
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? dest.selectedIcon : dest.icon,
                  size: 23,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    dest.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Vazirmatn',
                      fontSize: labelSize,
                      height: 1.1,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: labelColor,
                    ),
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
