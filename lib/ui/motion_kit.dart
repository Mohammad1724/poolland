import 'dart:math' as math;

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
    final plain =
        ctx == null ||
        !Motion.motionEnabled ||
        (MediaQuery.maybeOf(ctx)?.disableAnimations ?? false);
    if (plain) {
      return FadeTransition(opacity: animation, child: child);
    }
    final rtl = Directionality.of(ctx) == TextDirection.rtl;
    final enter = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return AnimatedBuilder(
      animation: Listenable.merge([enter, secondaryAnimation]),
      builder: (context, inner) {
        final t = enter.value;
        final s = Curves.easeOutCubic.transform(secondaryAnimation.value);
        final back = Matrix4.diagonal3Values(
          1 - 0.03 * s,
          1 - 0.03 * s,
          1,
        );
        final turn = Matrix4.diagonal3Values(
          0.95 + 0.05 * t,
          0.95 + 0.05 * t,
          1,
        )
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
      child: child,
    );
  }
}

/// Receipt-style bottom sheet.
///
/// Drop-in replacement for `showModalBottomSheet` with the app's signature
/// motion: the sheet rises like a printed receipt while its top edge tilts
/// back a few degrees and settles flat. On dismiss the same animation plays
/// in reverse — the receipt folds back down.
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
    pageBuilder: (ctx, _, _) => Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(ctx).height * 0.92,
        ),
        child: Material(color: Colors.transparent, child: builder(ctx)),
      ),
    ),
    transitionBuilder: (ctx, anim, _, child) {
      if (!Motion.motionEnabled ||
          (MediaQuery.maybeOf(ctx)?.disableAnimations ?? false)) {
        return FadeTransition(opacity: anim, child: child);
      }
      final slide = CurvedAnimation(
        parent: anim,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final settle = CurvedAnimation(parent: anim, curve: Curves.easeOutQuint);
      return AnimatedBuilder(
        animation: anim,
        builder: (ctx, inner) {
          final tilt = Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateX((1 - settle.value) * 0.09);
          return FractionalTranslation(
            translation: Offset(0, 1 - slide.value),
            child: Transform(
              alignment: Alignment.bottomCenter,
              transform: tilt,
              child: inner,
            ),
          );
        },
        child: child,
      );
    },
  );
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
