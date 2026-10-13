import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Shared layout and typography tokens.
///
/// Shared tokens keep spacing, type, and tap targets predictable across the
/// app. The scale uses a four-point spacing rhythm and readable defaults; dense
/// data can still opt into a smaller label when it is genuinely secondary.
class Insets {
  Insets._();

  static const double xxs = 2;
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;

  /// Horizontal page padding used by every scrollable list.
  static const EdgeInsets page = EdgeInsets.fromLTRB(16, 8, 16, 100);

  /// Bottom padding for scrollable pages so the floating action button never
  /// covers the last row.
  static const double listBottom = 100;
}

/// Font sizes for the text hierarchy: captions, body copy, and titles.
class FontSizes {
  FontSizes._();

  /// Smallest labels: helper text under a field, dense badges.
  static const double micro = 12;

  /// Secondary text: subtitles, list metadata.
  static const double caption = 12;

  /// Small body text.
  static const double small = 13;

  /// Default body text.
  static const double body = 14;

  /// Section titles and card headers.
  static const double title = 15;

  /// Prominent values inside cards.
  static const double value = 16;

  /// Screen and hero titles.
  static const double headline = 19;
}

/// Corner radii for cards, sheets, and fields.
class Radii {
  Radii._();

  static const double field = 14;
  static const double card = 20;
  static const double sheet = 22;
}

/// Minimum sizes for tappable controls.
///
/// Material's `compact` density shaves segmented buttons and dense icon
/// buttons down to roughly 32–36 logical pixels, which is below the ~44 that a
/// fingertip reliably hits. Screens ask for these values instead of shrinking
/// any further.
class Taps {
  Taps._();

  /// Minimum height of an interactive control; width stays as wide as the
  /// content needs.
  static const double minHeight = 44;

  /// Minimum side of a square icon button.
  static const double icon = 44;
}

/// Shared animation durations; keeping them equal keeps motion coherent.
class Motion {
  Motion._();

  /// Expand/collapse of collapsible sections and inline panels.
  static const Duration expand = Duration(milliseconds: 180);

  /// Small state changes such as a floating action button sliding away.
  static const Duration quick = Duration(milliseconds: 200);

  /// Pushed routes: the "ledger page turn" transition.
  static const Duration page = Duration(milliseconds: 320);

  /// One item of a staggered entrance (list items, dashboard cards).
  static const Duration staggerStep = Duration(milliseconds: 28);

  /// Master switch for the motion kit (page turn, stagger, odometer,
  /// celebration, sheets). Widget tests flip it off so suites stay
  /// deterministic: no overlays, no pending stagger timers, no loops, and
  /// values settle instantly. Production never touches it.
  static bool motionEnabled = true;

  /// Whether continuously running "ambient" motion (breathing gradients,
  /// shimmer sweeps, spinning coins) may play: the kit must be enabled and
  /// the user must not have asked for reduced motion.
  static bool ambientOn(BuildContext context) =>
      motionEnabled && !reduced(context);

  /// Whether the operating system asked for reduced motion.
  ///
  /// Aspect-scoped (`MediaQuery.maybeDisableAnimationsOf`) rather than a whole
  /// `MediaQuery` dependency: a transition that reads this must not rebuild
  /// every time the keyboard opens or the device rotates. Safe without a
  /// `MediaQuery` ancestor, which the `maybe` variant guarantees.
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// Whether any of the kit's motion may play at all.
  static bool on(BuildContext context) => motionEnabled && !reduced(context);

  /// Respect the operating system's reduced-motion preference.
  ///
  /// Aspect-scoped like [reduced], so the hundreds of call sites do not each
  /// register a whole-`MediaQuery` dependency and rebuild when the keyboard
  /// opens, the device rotates, or the system UI insets change.
  static Duration adaptive(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}

/// Staggered entrance: fade + rise, with an index-based delay.
///
/// Used for list items and cards so a freshly built page "arrives" instead of
/// popping. Only plays on first mount of each item; widget tests skip it via
/// [Motion.motionEnabled].
class EnterMotion extends StatefulWidget {
  const EnterMotion({
    super.key,
    required this.child,
    this.index = 0,
    this.rise = 12,
    this.staggerCap = 8,
  });

  final Widget child;
  final int index;
  final double rise;
  final int staggerCap;

  @override
  State<EnterMotion> createState() => _EnterMotionState();
}

class _EnterMotionState extends State<EnterMotion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );

  @override
  void initState() {
    super.initState();
    if (!Motion.motionEnabled) {
      _c.value = 1;
      return;
    }
    final i = math.min(widget.index, widget.staggerCap);
    final delay = Duration(milliseconds: 28 * i);
    if (delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Motion.motionEnabled) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_c.value);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, widget.rise * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Paper-slip entrance: an item drops into place like a slip falling into a
/// tray — a slight tilt that straightens itself with a soft overshoot.
class SlipIn extends StatefulWidget {
  const SlipIn({super.key, required this.child, this.index = 0});

  final Widget child;
  final int index;

  @override
  State<SlipIn> createState() => _SlipInState();
}

class _SlipInState extends State<SlipIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  );

  @override
  void initState() {
    super.initState();
    if (!Motion.motionEnabled) {
      _c.value = 1;
      return;
    }
    final delay = Duration(milliseconds: 40 * math.min(widget.index, 6));
    if (delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Motion.motionEnabled) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeOutBack.transform(_c.value);
        return Opacity(
          opacity: _c.value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, -16 * (1 - t)),
            child: Transform.rotate(angle: -0.035 * (1 - t), child: child),
          ),
        );
      },
      child: widget.child,
    );
  }
}
