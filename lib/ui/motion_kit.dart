import 'dart:math' as math;

// GestureRecognizerFactoryWithHandlers comes with material: it is declared in
// src/widgets/gesture_detector.dart, next to RawGestureDetector.
import 'package:flutter/gestures.dart'
    show DragStartBehavior, VerticalDragGestureRecognizer, VelocityTracker;
import 'package:flutter/material.dart';

import '../core/haptics.dart';
import 'design.dart';
import 'widgets/widgets.dart';

// ---------------------------------------------------------------------------
// The motion kit: shared, opinionated animations for the whole app.
//
// Everything here obeys two switches:
//  * `Motion.motionEnabled` — the master switch. Widget tests flip it off so
//    suites stay deterministic (no overlays, no stagger timers, no loops).
//  * `MediaQuery.disableAnimations` — the user's reduced-motion preference.
//    Ambient loops also check `Motion.ambientOn`.
//
// All animations use only opacity/transform so they stay on the fast path.
// ---------------------------------------------------------------------------

/// Page transition: "turning a ledger page".
///
/// The incoming page swings in with a small perspective rotation around the
/// binding edge plus a fractional slide, while the page underneath settles
/// back a touch. Mirrored automatically in RTL. Falls back to a plain fade
/// when motion is reduced or disabled.
class LedgerPageTransitionsBuilder extends PageTransitionsBuilder {
  const LedgerPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T>? route,
    BuildContext? context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final ctx = context;
    if (ctx == null || !Motion.motionEnabled || Motion.reduced(ctx)) {
      return FadeTransition(opacity: animation, child: child);
    }
    // The curved animations live in a State: `buildTransitions` runs on every
    // frame of the transition, and a `CurvedAnimation` registers a status
    // listener on its parent in its constructor. Building one per frame leaked
    // a listener per frame for as long as the route stayed in the stack.
    return _LedgerPageTurn(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

/// The "turning a ledger page" transform, owning its curved animations.
class _LedgerPageTurn extends StatefulWidget {
  const _LedgerPageTurn({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  State<_LedgerPageTurn> createState() => _LedgerPageTurnState();
}

class _LedgerPageTurnState extends State<_LedgerPageTurn> {
  late final CurvedAnimation _enter = CurvedAnimation(
    parent: widget.animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// Both animations, merged once so the [AnimatedBuilder] below keeps the
  /// same [Listenable] across rebuilds.
  late final Listenable _listenable = Listenable.merge([
    _enter,
    widget.secondaryAnimation,
  ]);

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return AnimatedBuilder(
      animation: _listenable,
      builder: (context, inner) {
        final t = _enter.value;
        final s = Curves.easeOutCubic.transform(
          widget.secondaryAnimation.value,
        );
        final back = Matrix4.diagonal3Values(1 - 0.03 * s, 1 - 0.03 * s, 1);
        final turn =
            Matrix4.diagonal3Values(0.95 + 0.05 * t, 0.95 + 0.05 * t, 1)
              ..setEntry(3, 2, 0.0012)
              ..rotateY((rtl ? -1 : 1) * (1 - t) * 0.10);
        return Transform(
          alignment: Alignment.center,
          transform: back,
          child: Transform(
            alignment: rtl ? Alignment.centerLeft : Alignment.centerRight,
            transform: turn,
            child: FractionalTranslation(
              translation: Offset((rtl ? -0.06 : 0.06) * (1 - t), 0),
              child: Opacity(opacity: t.clamp(0.0, 1.0), child: inner),
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Receipt-style bottom sheet.
///
/// Drop-in replacement for `showModalBottomSheet` with the app's signature
/// motion: the sheet rises like a printed receipt while its top edge tilts
/// back a few degrees and settles flat. On dismiss the same animation plays
/// in reverse — the receipt folds back down.
///
/// Every way out of a sheet works the same everywhere in the app:
///  * drag the grab strip at the top edge down ([_SheetDismiss]),
///  * keep pulling down once the sheet's own list is already at its top
///    ([_SheetPullDismiss]), on both clamping and bouncing scroll physics,
///  * drag a [DraggableScrollableSheet] down to its minimum size,
///  * tap the barrier, or press back.
///
/// The route also keeps the sheet clear of the soft keyboard and of the
/// system navigation area, and measures its maximum height against what is
/// actually visible, so a tall form plus a keyboard can never overflow.
/// Sheets therefore must not add their own `viewInsets` padding.
///
/// [isDismissible] turns off *all* of the ways out above, not just the
/// barrier: a sheet that must be answered cannot be dragged or back-pressed
/// away either.
Future<T?> showLedgerSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: isDismissible,
    barrierLabel: MaterialLocalizations.of(
      context,
    ).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 300),
    routeSettings: const RouteSettings(name: 'ledger-sheet'),
    pageBuilder: (ctx, _, _) =>
        _LedgerSheetFrame(dismissible: isDismissible, builder: builder),
    transitionBuilder: (ctx, anim, _, child) =>
        _LedgerSheetTransition(animation: anim, child: child),
  );
}

/// Lays a ledger sheet out inside its dialog route.
///
/// Split out of [showLedgerSheet] because `pageBuilder` is only called once
/// per route while this needs to rebuild whenever the keyboard or the safe
/// area changes.
class _LedgerSheetFrame extends StatelessWidget {
  const _LedgerSheetFrame({required this.dismissible, required this.builder});

  final bool dismissible;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    // `viewPadding` does not shrink when the keyboard opens and `padding`
    // does, so the maximum of the two is the space the sheet must stay clear
    // of in both states.
    final bottom = math.max(mq.viewInsets.bottom, mq.viewPadding.bottom);
    final visible = math.max(0.0, mq.size.height - bottom);

    Widget sheet = _SheetDismiss(
      enabled: dismissible,
      child: Material(
        color: Colors.transparent,
        child: _SheetPullDismiss(
          enabled: dismissible,
          child: Builder(builder: builder),
        ),
      ),
    );

    // A sheet built on `DraggableScrollableSheet` closes when it is dragged
    // down to its minimum size — what the framework's own `BottomSheet`
    // does. This is a plain dialog route, so without this listener such a
    // sheet would just park at its minimum and refuse to leave.
    sheet = NotificationListener<DraggableScrollableNotification>(
      onNotification: (n) {
        if (!dismissible) return false;
        if (!n.shouldCloseOnMinExtent || n.extent > n.minExtent) return false;
        Navigator.maybePop(context);
        return true;
      },
      child: sheet,
    );

    if (!dismissible) {
      sheet = PopScope<Object?>(canPop: false, child: sheet);
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: MediaQuery.removePadding(
        context: context,
        // The route just paid for the bottom inset; a `SafeArea` inside a
        // sheet must not add the same space a second time.
        removeBottom: true,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: visible * 0.92),
            child: sheet,
          ),
        ),
      ),
    );
  }
}

/// The receipt rise-and-settle of a ledger sheet, owning its curved
/// animations (see [_LedgerPageTurn] for why they must not be rebuilt).
class _LedgerSheetTransition extends StatefulWidget {
  const _LedgerSheetTransition({required this.animation, this.child});

  final Animation<double> animation;
  final Widget? child;

  @override
  State<_LedgerSheetTransition> createState() => _LedgerSheetTransitionState();
}

class _LedgerSheetTransitionState extends State<_LedgerSheetTransition> {
  late final CurvedAnimation _slide = CurvedAnimation(
    parent: widget.animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  late final CurvedAnimation _settle = CurvedAnimation(
    parent: widget.animation,
    curve: Curves.easeOutQuint,
  );

  @override
  void dispose() {
    _slide.dispose();
    _settle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Motion.motionEnabled || Motion.reduced(context)) {
      return FadeTransition(opacity: widget.animation, child: widget.child);
    }
    return AnimatedBuilder(
      animation: widget.animation,
      builder: (ctx, inner) {
        final tilt =
            Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateX((1 - _settle.value) * 0.09);
        return FractionalTranslation(
          translation: Offset(0, 1 - _slide.value),
          child: Transform(
            alignment: Alignment.bottomCenter,
            transform: tilt,
            child: inner,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Odometer money: amounts roll digit-by-digit to their new value.
///
/// Renders exactly like [MoneyText]; on value changes it interpolates from
/// the previous amount with an ease-out roll. First build is instant, so
/// screens never open mid-animation.
class OdometerMoney extends StatefulWidget {
  const OdometerMoney(
    this.amount, {
    super.key,
    this.currency = 'IRT',
    this.style,
    this.signed = false,
    this.withSymbol = true,
    this.compact = false,
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
  final int? maxLines;
  final TextOverflow? overflow;
  final bool softWrap;

  @override
  State<OdometerMoney> createState() => _OdometerMoneyState();
}

class _OdometerMoneyState extends State<OdometerMoney>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  late double _from = widget.amount;

  @override
  void didUpdateWidget(OdometerMoney old) {
    super.didUpdateWidget(old);
    if (old.amount == widget.amount) return;
    if (!Motion.motionEnabled) {
      _from = widget.amount;
      return;
    }
    _from = _current;
    _c.forward(from: 0);
  }

  double get _current =>
      _from +
      (widget.amount - _from) * Curves.easeOutCubic.transform(_c.value);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final value = (!Motion.motionEnabled || reduced)
        ? widget.amount
        : _current;
    return MoneyText(
      value,
      currency: widget.currency,
      style: widget.style,
      signed: widget.signed,
      withSymbol: widget.withSymbol,
      compact: widget.compact,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      softWrap: widget.softWrap,
    );
  }
}

/// Paints the app's little gold coin; shared by the celebration overlay and
/// the pull-to-refresh indicator so both feel like the same object.
void paintCoin(Canvas canvas, Offset center, double radius, double rotation) {
  canvas.save();
  canvas.translate(center.dx, center.dy);
  canvas.rotate(rotation);
  final body = Paint()
    ..shader = RadialGradient(
      center: const Alignment(-0.35, -0.4),
      colors: const [Color(0xFFFFE9A8), Color(0xFFF2C14E), Color(0xFFD99B23)],
      stops: const [0.0, 0.55, 1.0],
    ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius));
  canvas.drawCircle(Offset.zero, radius, body);
  canvas.drawCircle(
    Offset.zero,
    radius,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0xFF9A6B12),
  );
  canvas.drawCircle(
    Offset.zero,
    radius * 0.62,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = const Color(0xFFB9821A).withValues(alpha: 0.9),
  );
  // A small four-point sparkle stands in for the mint mark.
  final mark = Path();
  final r = radius * 0.30;
  mark.moveTo(0, -r);
  mark.quadraticBezierTo(0, 0, r, 0);
  mark.quadraticBezierTo(0, 0, 0, r);
  mark.quadraticBezierTo(0, 0, -r, 0);
  mark.quadraticBezierTo(0, 0, 0, -r);
  canvas.drawPath(
    mark,
    Paint()..color = const Color(0xFF8A5E10).withValues(alpha: 0.85),
  );
  canvas.restore();
}

/// The signature "money recorded" moment: a coin arcs up from where the user
/// confirmed, an impact ring pulses at the landing point, and a ledger stamp
/// ("double ring + check") thumps down and fades.
///
/// Fire-and-forget: inserts a root-overlay entry that removes itself. No-ops
/// in tests (`Motion.motionEnabled == false`) and under reduced motion.
class MoneyCelebration {
  MoneyCelebration._();

  static void recorded(BuildContext context, {Offset? from}) {
    if (!Motion.motionEnabled) return;
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final size = MediaQuery.sizeOf(context);
    final start = from ?? Offset(size.width / 2, size.height - 130);
    final end = Offset(size.width / 2, size.height * 0.40);
    final ink = Theme.of(context).colorScheme.primary;
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => IgnorePointer(
        child: _CelebrationLayer(
          size: size,
          start: start,
          end: end,
          ink: ink,
          onDone: () {
            if (entry.mounted) entry.remove();
          },
        ),
      ),
    );
    overlay.insert(entry);
    Haptics.confirm();
  }
}

class _CelebrationLayer extends StatefulWidget {
  const _CelebrationLayer({
    required this.size,
    required this.start,
    required this.end,
    required this.ink,
    required this.onDone,
  });

  final Size size;
  final Offset start;
  final Offset end;
  final Color ink;
  final VoidCallback onDone;

  @override
  State<_CelebrationLayer> createState() => _CelebrationLayerState();
}

class _CelebrationLayerState extends State<_CelebrationLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
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
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size.width,
        height: widget.size.height,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(
            painter: _CelebrationPainter(
              t: _c.value,
              start: widget.start,
              end: widget.end,
              ink: widget.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _CelebrationPainter extends CustomPainter {
  _CelebrationPainter({
    required this.t,
    required this.start,
    required this.end,
    required this.ink,
  });

  final double t;
  final Offset start;
  final Offset end;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    // --- Phase 1 (0.00–0.42): the coin flies along a shallow arc. ---
    final f = Curves.easeInOut.transform((t / 0.42).clamp(0.0, 1.0));
    if (t < 0.44) {
      final ctrl = Offset(
        (start.dx + end.dx) / 2 - size.width * 0.16,
        (start.dy + end.dy) / 2 - 70,
      );
      final a = Offset.lerp(start, ctrl, f)!;
      final b = Offset.lerp(ctrl, end, f)!;
      final pos = Offset.lerp(a, b, f)!;
      paintCoin(canvas, pos, 15 * (1 - 0.18 * f), f * math.pi * 3);
    }

    // --- Phase 2 (0.40–0.58): impact ring at the landing point. ---
    if (t >= 0.40 && t < 0.60) {
      final r = ((t - 0.40) / 0.18).clamp(0.0, 1.0);
      canvas.drawCircle(
        end,
        12 + 42 * Curves.easeOutCubic.transform(r),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 * (1 - r) + 0.5
          ..color = ink.withValues(alpha: 0.55 * (1 - r)),
      );
    }

    // --- Phase 3 (0.46–1.00): the ledger stamp thumps down and fades. ---
    if (t >= 0.46) {
      final s = ((t - 0.46) / 0.22).clamp(0.0, 1.0);
      final scale = 1.45 - 0.45 * Curves.easeOutBack.transform(s);
      final fade = t < 0.84
          ? 1.0
          : (1 - ((t - 0.84) / 0.16).clamp(0.0, 1.0));
      final alpha = (0.9 * fade).clamp(0.0, 1.0);
      canvas.save();
      canvas.translate(end.dx, end.dy);
      canvas.rotate(-0.09 + 0.05 * (1 - s));
      canvas.scale(scale, scale);
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = ink.withValues(alpha: alpha);
      canvas.drawCircle(Offset.zero, 38, ring);
      canvas.drawCircle(
        Offset.zero,
        31,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = ink.withValues(alpha: alpha * 0.85),
      );
      final check = Path()
        ..moveTo(-13, 1)
        ..lineTo(-4, 11)
        ..lineTo(14, -10);
      canvas.drawPath(
        check,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = ink.withValues(alpha: alpha),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_CelebrationPainter old) =>
      old.t != t || old.start != start || old.end != end || old.ink != ink;
}

/// A very slow cross-fade between two gradient states — the "breathing"
/// background used on hero cards. Static when ambient motion is off.
class BreathingGradient extends StatefulWidget {
  const BreathingGradient({
    super.key,
    required this.child,
    required this.base,
    required this.variant,
    this.borderRadius = BorderRadius.zero,
    this.period = const Duration(seconds: 5),
  });

  final Widget child;
  final List<Color> base;
  final List<Color> variant;
  final BorderRadius borderRadius;
  final Duration period;

  @override
  State<BreathingGradient> createState() => _BreathingGradientState();
}

class _BreathingGradientState extends State<BreathingGradient>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.ambientOn(context)) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The wash is laid over the child with alpha colors, so it also works on
    // top of opaque cards.
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        for (var i = 0; i < widget.base.length; i++)
                          Color.lerp(widget.base[i], widget.variant[i], _c.value)!,
                      ],
                    ),
                  ),
                ),
              ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A soft diagonal band of light that sweeps across a card every few seconds,
/// like light passing over laminated paper. Static (invisible) when ambient
/// motion is off.
class ShimmerSweep extends StatefulWidget {
  const ShimmerSweep({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.period = const Duration(milliseconds: 5500),
  });

  final Widget child;
  final BorderRadius borderRadius;
  final Duration period;

  @override
  State<ShimmerSweep> createState() => _ShimmerSweepState();
}

class _ShimmerSweepState extends State<ShimmerSweep>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.ambientOn(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(
                  painter: _ShimmerPainter(
                    t: _c.value,
                    radius: widget.borderRadius,
                    dark: Theme.of(context).brightness == Brightness.dark,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ShimmerPainter extends CustomPainter {
  _ShimmerPainter({required this.t, required this.radius, required this.dark});

  final double t;
  final BorderRadius radius;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    const active = 0.42; // The sweep crosses during the first 42% of a cycle.
    if (t >= active) return;
    final p = Curves.easeInOutSine.transform(t / active);
    final alpha = dark ? 0.05 : 0.10;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.save();
    canvas.clipRRect(radius.toRRect(rect));
    canvas.translate(size.width * (p * 1.5 - 0.25), 0);
    canvas.rotate(0.32);
    final band = Rect.fromCenter(
      center: Offset.zero,
      width: 46,
      height: size.height * 3,
    );
    canvas.drawRect(
      band,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: alpha),
            Colors.white.withValues(alpha: 0),
          ],
        ).createShader(band),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShimmerPainter old) => old.t != t || old.dark != dark;
}

/// Pull-to-refresh with the app's coin: dragging down rotates the coin like
/// it is being rolled on its edge; while refreshing it spins on its own.
class CoinRefresh extends StatefulWidget {
  const CoinRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  State<CoinRefresh> createState() => _CoinRefreshState();
}

class _CoinRefreshState extends State<CoinRefresh>
    with SingleTickerProviderStateMixin {
  static const double _threshold = 64;
  static const double _maxPull = 96;

  double _pull = 0;
  bool _refreshing = false;
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (_refreshing) return false;
    if (n is ScrollUpdateNotification) {
      final atTop = n.metrics.pixels <= n.metrics.minScrollExtent + 0.5;
      final delta = n.scrollDelta ?? 0;
      if (atTop && delta < 0) {
        setState(() => _pull = (_pull - delta).clamp(0.0, _maxPull));
      } else if (_pull > 0 && delta > 0) {
        setState(() => _pull = (_pull - delta).clamp(0.0, _maxPull));
      }
    } else if (n is OverscrollNotification && n.overscroll < 0) {
      setState(() => _pull = (_pull - n.overscroll).clamp(0.0, _maxPull));
    } else if (n is ScrollEndNotification && _pull > 0) {
      if (_pull >= _threshold) {
        _trigger();
      } else {
        setState(() => _pull = 0);
      }
    }
    return false;
  }

  void _trigger() {
    setState(() {
      _refreshing = true;
      _pull = _threshold;
    });
    if (Motion.ambientOn(context)) _spin.repeat();
    widget
        .onRefresh()
        .whenComplete(() {
          if (!mounted) return;
          _spin.stop();
          _spin.value = 0;
          setState(() {
            _refreshing = false;
            _pull = 0;
          });
        });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _pull > 0 || _refreshing;
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: Stack(
        children: [
          widget.child,
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: AnimatedOpacity(
                  opacity: visible ? math.min(1, _pull / 36) : 0,
                  duration: const Duration(milliseconds: 140),
                  child: AnimatedBuilder(
                    animation: _spin,
                    builder: (context, _) {
                      final angle = _refreshing
                          ? _spin.value * 2 * math.pi
                          : (_pull / _threshold) * math.pi;
                      return Transform.rotate(
                        angle: angle,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.18),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: CustomPaint(painter: _CoinFacePainter()),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoinFacePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    paintCoin(canvas, size.center(Offset.zero), 17, 0);
  }

  @override
  bool shouldRepaint(_CoinFacePainter old) => false;
}

/// Drag-to-dismiss for ledger sheets.
///
/// Two paths feed the same pull:
///  * a translucent strip along the top edge, where every sheet has its grab
///    handle, and
///  * the sheet's own scrollable reporting that it was pulled past its top
///    ([_SheetPullDismiss]).
///
/// Whichever one is in use, the sheet follows the finger down and tilts like
/// soft paper. Past [_dismissPull], or on a downward fling, the route pops;
/// otherwise the sheet springs back. Taps still fall through to the content
/// underneath, and a route that refuses to pop is put back rather than left
/// hanging off the bottom of the screen.
class _SheetDismiss extends StatefulWidget {
  const _SheetDismiss({required this.enabled, required this.child});

  /// False for sheets opened with `isDismissible: false`: such a sheet has no
  /// gesture-driven way out at all.
  final bool enabled;

  final Widget child;

  @override
  State<_SheetDismiss> createState() => _SheetDismissState();
}

/// Hands [_SheetDismissState] to the pull detector living inside the sheet.
class _SheetDismissScope extends InheritedWidget {
  const _SheetDismissScope({required this.controller, required super.child});

  final _SheetDismissState controller;

  static _SheetDismissState? maybeOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_SheetDismissScope>()
          ?.controller;

  @override
  bool updateShouldNotify(_SheetDismissScope old) =>
      controller != old.controller;
}

class _SheetDismissState extends State<_SheetDismiss>
    with SingleTickerProviderStateMixin {
  /// Height of the grab strip along the top edge of the sheet.
  ///
  /// Keep this larger than the painted handle: on a phone the handle is only
  /// four logical pixels tall, but people naturally start a swipe anywhere in
  /// the top padding around it.
  static const double _grabHeight = 56;

  /// How far the sheet must be pulled down before letting go dismisses it.
  ///
  /// Short enough to feel light on a thumb swipe, but long enough that an
  /// ordinary scroll bounce at the top of a list cannot cross it by
  /// accident. On phones with very high density the old 110 px threshold
  /// felt too demanding; 72 px keeps the gesture light.
  static const double _dismissPull = 72;

  /// A downward fling dismisses from here, without needing the full pull.
  static const double _flingVelocity = 900;

  /// A fling only counts once the sheet has actually started to move, so a
  /// fast tap can never be mistaken for one.
  static const double _minFlingPull = 8;

  /// Fallback for [_maxPull] before the sheet has been laid out once.
  static const double _fallbackMaxPull = 480;

  double _pull = 0;
  double _springFrom = 0;
  bool _ticked = false;
  bool _decided = false;
  bool _closing = false;

  /// True only while a pointer that went down on this sheet is still down.
  ///
  /// Pull input is gated on it: a mouse wheel, or the ballistic tail of a
  /// fling that has already been released, can report overscroll too, and
  /// neither has a pointer-up that would ever put the sheet back.
  bool _pointerDown = false;

  /// When the pointer went down on the grab strip (top [_grabHeight] pixels),
  /// tracks the origin so the Listener can accumulate pull as a fallback
  /// when the drag recognizer loses the arena to the scrollable.
  Offset? _grabOrigin;

  VelocityTracker? _tracker;

  /// Cached in [build]: the gesture handlers run outside the build phase and
  /// must not register a `MediaQuery` dependency from there.
  bool _animated = true;

  late final AnimationController _spring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  /// The sheet's own height: as far as it can usefully be pulled.
  double get _maxPull {
    final h = context.size?.height ?? 0;
    return h > 0 ? h : _fallbackMaxPull;
  }

  /// Where the sheet is right now — the live pull while a finger is on it,
  /// the spring's value while it settles back.
  double get pull {
    if (!_spring.isAnimating) return _pull;
    return _springFrom * (1 - Curves.easeOutCubic.transform(_spring.value));
  }

  // ---------------- pull input ----------------

  /// Stops the spring and returns wherever the sheet visibly is.
  ///
  /// [_pull] holds the *target* while [pull] is the value the spring is
  /// currently showing. Every handler that stops the spring has to adopt that
  /// value first: re-grabbing a sheet that is on its way back would otherwise
  /// teleport it to where it was heading.
  double _adopt() {
    final now = pull;
    _spring.stop();
    _pull = now;
    return now;
  }

  /// Grows the pull by [delta].
  ///
  /// Both scroll physics feed this one path. Clamping physics pin the offset at
  /// the top and report every extra pixel as an overscroll; bouncing physics
  /// let the offset itself travel past the top and report it as a negative
  /// scroll delta instead. Accumulating deltas rather than adopting an absolute
  /// offset is what keeps the sheet from jumping when a finger comes back while
  /// it is still settling.
  void addPull(double delta) {
    if (!widget.enabled || _closing || _decided || !_pointerDown) return;
    _setPull(_adopt() + delta);
  }

  /// Fallback pull tracker for when the drag recognizer loses the arena.
  ///
  /// Only active when the pointer went down on the grab strip (top
  /// [_grabHeight] pixels). Computes pull from the distance between the
  /// current pointer position and the origin, so the sheet can dismiss
  /// even without the drag recognizer's help.
  void updatePullFromGrab(Offset position) {
    if (!widget.enabled || _closing || _decided || !_pointerDown) return;
    if (_grabOrigin == null) return;
    final delta = position.dy - _grabOrigin!.dy;
    if (delta <= 0) return;
    _setPull(delta);
  }

  /// Shrinks the pull when the content scrolls back up under the finger.
  void reducePull(double delta) {
    if (!widget.enabled || _closing || _pull <= 0) return;
    _setPull(_adopt() - delta);
  }

  void _setPull(double value) {
    final next = value.clamp(0.0, _maxPull);
    if (next == _pull) return;
    setState(() => _pull = next);
    // One tick as the release threshold is crossed, so the gesture can be
    // felt without looking at the screen.
    if (!_ticked && _pull >= _dismissPull) {
      _ticked = true;
      Haptics.selection();
    } else if (_ticked && _pull < _dismissPull * 0.9) {
      _ticked = false;
    }
  }

  // ---------------- release ----------------

  /// The finger left the sheet. The grab strip's drag end and the sheet-wide
  /// pointer-up both arrive here for the same gesture, so the first decides.
  ///
  /// When the drag recognizer lost the arena to the scrollable underneath,
  /// [_pull] may still hold the distance tracked by [updatePullFromPointer] —
  /// so the sheet can dismiss even without the recognizer's help.
  void release({double velocity = 0}) {
    if (!widget.enabled || _closing || _decided) return;
    _decided = true;
    _tracker = null;
    final p = pull;
    final flung = p > _minFlingPull && velocity >= _flingVelocity;
    if (p >= _dismissPull || flung) {
      _dismiss();
    } else {
      _snapBack();
    }
  }

  void _dismiss() {
    _closing = true;
    Haptics.tap();
    final route = ModalRoute.of(context);
    if (route != null &&
        route.popDisposition == RoutePopDisposition.doNotPop) {
      // A `PopScope` inside the sheet refused the close. Mirroring what
      // `Navigator.maybePop` does in that case keeps the vetoing widget
      // informed, and the sheet goes back instead of staying translated.
      route.onPopInvokedWithResult(false, null);
      _closing = false;
      _snapBack();
      return;
    }
    Navigator.maybePop(context);
  }

  /// Returns the sheet to its resting place, animating only where motion is
  /// wanted. A no-op when the sheet never moved, so ordinary taps inside a
  /// sheet do not rebuild it.
  void _snapBack() {
    if (!mounted) return;
    _ticked = false;
    final from = pull;
    _pull = 0;
    if (from == 0 && !_spring.isAnimating) return;
    _springFrom = _animated ? from : 0;
    _spring.stop();
    setState(() {});
    if (_springFrom > 0) _spring.forward(from: 0);
  }

  // ---------------- build ----------------

  @override
  Widget build(BuildContext context) {
    _animated = Motion.motionEnabled && !Motion.reduced(context);
    // Keep pointer bookkeeping above the entire hit-test subtree. The grab
    // strip is a Stack sibling layered over the sheet body, so a Listener on
    // the body itself never receives pointer-downs that start on that strip;
    // without those, its drag recognizer has no active pull to release.
    final content = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _pointerDown = true;
        _decided = false;
        // If the pointer went down on the grab strip (top _grabHeight pixels),
        // track the origin so we can accumulate pull as a fallback when the
        /// drag recognizer loses the arena.
        if (e.position.dy < _grabHeight) {
          _grabOrigin = e.position;
        }
        _tracker = VelocityTracker.withKind(e.kind);
      },
      onPointerMove: (e) {
        _tracker?.addPosition(e.timeStamp, e.position);
        // Fallback pull tracking for when the drag recognizer lost the arena.
        updatePullFromGrab(e.position);
      },
      onPointerUp: (e) {
        _pointerDown = false;
        _grabOrigin = null;
        release(velocity: _tracker?.getVelocity().pixelsPerSecond.dy ?? 0);
      },
      onPointerCancel: (_) {
        _pointerDown = false;
        _grabOrigin = null;
        _decided = true;
        _tracker = null;
        if (_pull > 0) _snapBack();
      },
      child: Stack(
        children: [
          widget.child,
          if (widget.enabled)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: _grabHeight,
              child: RawGestureDetector(
                behavior: HitTestBehavior.translucent,
                gestures: {
                  _DownOnlyDrag:
                      GestureRecognizerFactoryWithHandlers<_DownOnlyDrag>(
                        _DownOnlyDrag.new,
                        (_DownOnlyDrag instance) {
                          instance.dragStartBehavior = DragStartBehavior.start;
                          instance.onStart = (_) {
                            _adopt();
                          };
                          instance.onUpdate = (d) {
                            addPull(d.delta.dy);
                          };
                          instance.onEnd = (d) {
                            release(velocity: d.primaryVelocity ?? 0);
                          };
                          instance.onCancel = () {
                            // The drag recognizer lost the arena — typically
                            // to the scrollable inside the sheet. The user
                            // still has their finger on the screen, and the
                            // [Listener] below continues to track pointer
                            // movement via [updatePullFromPointer], so the
                            // sheet can still dismiss. Do NOT reset [_pull]
                            // here: whatever distance the Listener already
                            // accumulated is the user's real intent.
                          };
                        },
                      ),
                },
                child: const SizedBox.expand(),
              ),
            ),
        ],
      ),
    );

    Widget sheet = _SheetDismissScope(controller: this, child: content);
    if (!widget.enabled) return sheet;

    return AnimatedBuilder(
      animation: _spring,
      builder: (context, child) {
        final now = pull;
        if (now == 0) return child!;
        final tilted = _animated
            ? Transform(
                alignment: Alignment.topCenter,
                transform:
                    Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateX(math.min(now / 3200, 0.05)),
                child: child,
              )
            : child!;
        return Transform.translate(offset: Offset(0, now), child: tilted);
      },
      child: sheet,
    );
  }
}

/// A slow, always-moving aurora of soft colour blobs with a few twinkling
/// sparks: the ambient "alive" layer behind the main pages' headers.
///
/// One repeating controller drives every blob and spark through transforms
/// and opacities only, so the layer composites at 60fps inside its own
/// [RepaintBoundary]. With motion disabled (reduced-motion setting, widget
/// tests) it freezes into a static soft gradient instead of ticking.
class AmbientAurora extends StatefulWidget {
  const AmbientAurora({super.key, this.height = 240});

  final double height;

  @override
  State<AmbientAurora> createState() => _AmbientAuroraState();
}

class _AmbientAuroraState extends State<AmbientAurora>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 16),
    value: Motion.motionEnabled ? 0 : 0.31,
  );

  @override
  void initState() {
    super.initState();
    if (Motion.motionEnabled) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// color, angular speed, peak alpha.
  static const List<(Color, double, double)> _blobs = [
    (Color(0xFF0F766E), 0.9, 0.16),
    (Color(0xFF16A34A), 0.7, 0.13),
    (Color(0xFFD97706), 1.15, 0.10),
  ];

  /// x, y in Alignment units and a phase for each spark.
  static const List<(double, double, double)> _sparks = [
    (-0.62, -0.35, 0.0),
    (0.55, -0.62, 1.7),
    (-0.10, 0.15, 3.1),
    (0.78, -0.05, 4.4),
  ];

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        height: widget.height,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value * 2 * math.pi;
              return Stack(
                children: [
                  for (var i = 0; i < _blobs.length; i++) _blob(i, t),
                  for (var i = 0; i < _sparks.length; i++) _spark(i, t),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _blob(int i, double t) {
    final (color, speed, alpha) = _blobs[i];
    final size = 150.0 + i * 46;
    // Two sines per axis keep the path organic without any physics sim.
    final x = math.sin(t * speed + i * 2.1) * 0.72;
    final y = math.cos(t * speed * 0.8 + i * 1.3) * 0.55;
    return Align(
      alignment: Alignment(x, y),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _spark(int i, double t) {
    final (x, y, phase) = _sparks[i];
    final pulse = 0.5 + 0.5 * math.sin(t * 2.3 + phase);
    return Align(
      alignment: Alignment(x, y),
      child: Opacity(
        opacity: 0.12 + 0.42 * pulse,
        child: Transform.scale(
          scale: 0.8 + 0.35 * pulse,
          child: Icon(
            Icons.star_rounded,
            size: 6.0 + (i % 2) * 3,
            color: i.isEven ? const Color(0xFF0F766E) : const Color(0xFFD97706),
          ),
        ),
      ),
    );
  }
}

/// A vertical drag that only ever claims *downward* movement.
///
/// A plain [VerticalDragGestureRecognizer] for the grab strip.
///
/// The strip is painted on top of the sheet's content and reaches the gesture
/// arena before the list underneath. The old implementation rejected the
/// gesture when the pointer drifted upward by a touch slop before the drag
/// was accepted — handing it back to whatever was underneath so a flick that
/// started on the handle could still scroll the list. On a real phone a thumb
/// naturally wobbles a few pixels in every direction the instant it touches
/// the handle, so that rejection fired on almost every first attempt and
/// forced the user to tap twice before a drag would close the sheet. The
/// strip wins the arena either way; negative deltas are harmless because
/// [_SheetDismissState.addPull] clamps the pull to zero.
class _DownOnlyDrag extends VerticalDragGestureRecognizer {
  _DownOnlyDrag({super.debugOwner});
}

/// Turns "the content is already at its top and the finger keeps going down"
/// into a pull on the sheet around it.
///
/// Both families of scroll physics are covered, because they report the very
/// same gesture differently:
///  * clamping (Android, web, desktop) pins the offset at the top and
///    dispatches an [OverscrollNotification] for every extra pixel;
///  * bouncing (iOS, macOS) lets the offset itself go negative and only ever
///    dispatches [ScrollUpdateNotification] — never an overscroll one.
///
/// Listening for overscroll alone therefore silently disabled the gesture on
/// every bouncing-physics platform.
///
/// Horizontal scrollers and scrollables nested inside another scrollable are
/// ignored: only the sheet's own content may close the sheet.
class _SheetPullDismiss extends StatefulWidget {
  const _SheetPullDismiss({required this.enabled, required this.child});

  final bool enabled;
  final Widget child;

  @override
  State<_SheetPullDismiss> createState() => _SheetPullDismissState();
}

class _SheetPullDismissState extends State<_SheetPullDismiss> {
  _SheetDismissState? _sheet;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sheet = _SheetDismissScope.maybeOf(context);
  }

  bool _onNotification(ScrollNotification n) {
    final sheet = _sheet;
    if (!widget.enabled || sheet == null) return false;
    // Only the sheet's own scrollable. A vertical list nested inside another
    // one reports a depth above zero, and that inner list being at its own
    // top says nothing about where the sheet should go. A horizontal chip row
    // dragged past its start edge reports the same negative overscroll and
    // must never dismiss the sheet sideways.
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;

    if (n is OverscrollNotification) {
      if (n.overscroll < 0 &&
          n.metrics.pixels <= n.metrics.minScrollExtent + 0.5) {
        sheet.addPull(-n.overscroll);
      }
      return false;
    }
    if (n is ScrollUpdateNotification) {
      final delta = n.scrollDelta ?? 0;
      if (delta == 0) return false;
      if (n.metrics.outOfRange && n.metrics.pixels < n.metrics.minScrollExtent) {
        // Bouncing physics: the offset itself travelled past the top, so the
        // movement arrives as a negative delta rather than as an overscroll.
        sheet.addPull(-delta);
      } else if (delta > 0) {
        // Scrolling back up gives the pull back, pixel for pixel.
        sheet.reducePull(delta);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onNotification,
        child: widget.child,
      );
}
