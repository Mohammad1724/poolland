import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/localization.dart';
import '../data/repository.dart';
import 'design.dart';
import 'widgets/widgets.dart';

/// Discoverability for the app's gestures.
///
/// Swipes, long-presses and drag-to-dismiss are invisible by nature: nothing
/// on the screen hints that they exist. This tour is the hint — a bottom
/// sheet that shows each gesture once, with a small looping animation of
/// exactly what the finger should do. It opens by itself the first time
/// after an update ([maybeShowGestureTour]) and can be replayed any time
/// from Settings.

/// Shows the tour once per install/update.
///
/// Skipped entirely when motion is off: that is both the reduced-motion
/// preference and the widget-test environment, and neither should get a
/// modal sheet popping up on its own.
Future<void> maybeShowGestureTour(BuildContext context) async {
  if (!Motion.motionEnabled) return;
  final repo = context.read<AppRepository>();
  if (repo.settings.gestureTourSeen) return;
  if (!context.mounted) return;
  await showGestureTour(context);
  if (!context.mounted) return;
  await repo.updateSettings(repo.settings.copyWith(gestureTourSeen: true));
}

/// Opens the gesture tour sheet right now (Settings → Gesture guide).
Future<void> showGestureTour(BuildContext context) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Theme.of(context).colorScheme.surface,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (ctx) => const _TourSheet(),
);

class _TourSheet extends StatelessWidget {
  const _TourSheet();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.68,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        builder: (ctx, controller) => Column(
          children: [
            const SizedBox(height: 12),
            const SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Icon(
                    Icons.touch_app_rounded,
                    size: 20,
                    color: scheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Gesture guide'.tr,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                children: const [
                  _TourCard(
                    title: 'Swipe actions',
                    desc:
                        'Swipe a transaction row sideways to edit, duplicate '
                        'or delete it.',
                    demo: _SwipeDemo(),
                  ),
                  _TourCard(
                    title: 'Copy money',
                    desc: 'Hold any amount to copy the plain number.',
                    demo: _CopyDemo(),
                  ),
                  _TourCard(
                    title: 'Quick menu',
                    desc: 'Hold the + button, drag onto an option and release.',
                    demo: _DialDemo(),
                  ),
                  _TourCard(
                    title: 'Dismiss sheets',
                    desc: 'Drag any sheet down to close it.',
                    demo: _SheetDemo(),
                  ),
                  _TourCard(
                    title: 'Customer shortcuts',
                    desc: 'Hold a customer card for receive, pay and edit '
                        'shortcuts.',
                    demo: _HoldDemo(),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Got it'.tr),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TourCard extends StatelessWidget {
  const _TourCard({required this.title, required this.desc, required this.demo});

  final String title;
  final String desc;
  final Widget demo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CardBox(
        child: Row(
          children: [
            Container(
              width: 88,
              height: 64,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: demo,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title.tr,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    desc.tr,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: scheme.onSurface.withValues(alpha: 0.65),
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

/// A tiny looping animation. With motion disabled (reduced-motion setting
/// or widget tests) it freezes on a representative mid-frame instead.
class _Loop extends StatefulWidget {
  const _Loop({required this.builder, this.ms = 1800});

  final Widget Function(double t) builder;
  final int ms;

  @override
  State<_Loop> createState() => _LoopState();
}

class _LoopState extends State<_Loop> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: widget.ms),
    value: Motion.motionEnabled ? 0 : 0.55,
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      AnimatedBuilder(animation: _c, builder: (_, __) => widget.builder(_c.value));
}

/// Ping-pong 0→1→0 so demos sweep back and forth.
double _pp(double t) => t < 0.5 ? t * 2 : (1 - t) * 2;

class _SwipeDemo extends StatelessWidget {
  const _SwipeDemo();

  @override
  Widget build(BuildContext context) => _Loop(
    builder: (t) {
      final dx = 30 * Curves.easeInOut.transform(_pp(t));
      return Stack(
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.edit_rounded, size: 12, color: Color(0xFF2563EB)),
                  SizedBox(width: 6),
                  Icon(Icons.delete_rounded, size: 12, color: Color(0xFFE11D48)),
                ],
              ),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Transform.translate(
              offset: Offset(-dx, 0),
              child: Container(
                width: 62,
                height: 26,
                margin: const EdgeInsetsDirectional.only(start: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
                child: Center(
                  child: Container(
                    width: 34,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _CopyDemo extends StatelessWidget {
  const _CopyDemo();

  @override
  Widget build(BuildContext context) => _Loop(
    builder: (t) {
      final p = _pp(t);
      final pop = 1 + 0.14 * (p > 0.35 && p < 0.75 ? 1.0 : 0.0);
      final chip = p > 0.5 ? ((p - 0.5) / 0.3).clamp(0.0, 1.0) : 0.0;
      return Stack(
        alignment: Alignment.center,
        children: [
          Transform.scale(
            scale: pop,
            child: Text(
              '125,000',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          if (chip > 0)
            Opacity(
              opacity: chip,
              child: Transform.translate(
                offset: Offset(0, -18 - 6 * chip),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.inverseSurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_rounded, size: 10, color: Colors.white),
                      SizedBox(width: 3),
                      Text(
                        'Copied',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _DialDemo extends StatelessWidget {
  const _DialDemo();

  @override
  Widget build(BuildContext context) => _Loop(
    builder: (t) {
      final p = Curves.easeOutBack.transform(_pp(t).clamp(0.0, 1.0));
      return Stack(
        children: [
          for (var i = 0; i < 3; i++)
            Positioned(
              right: 14 + 20.0 * i * 0.4 + 16 * p,
              bottom: 12 + (i + 1) * 13.0 * p,
              child: Opacity(
                opacity: p.clamp(0.0, 1.0),
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    color: const [
                      Color(0xFF16A34A),
                      Color(0xFF0F766E),
                      Color(0xFFD97706),
                    ][i],
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          Positioned(
            right: 10,
            bottom: 8,
            child: Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: Color(0xFF0F766E),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.add_rounded, size: 14, color: Colors.white),
            ),
          ),
        ],
      );
    },
  );
}

class _SheetDemo extends StatelessWidget {
  const _SheetDemo();

  @override
  Widget build(BuildContext context) => _Loop(
    builder: (t) {
      final p = t; // one way: sheet rests, then slides down and resets
      final dy = Curves.easeInCubic.transform(p < 0.7 ? 0 : (p - 0.7) / 0.3);
      return Stack(
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Container(
                width: 52,
                height: 8,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Transform.translate(
              offset: Offset(0, 46 * dy),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Center(
                  child: Container(
                    width: 26,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _HoldDemo extends StatelessWidget {
  const _HoldDemo();

  @override
  Widget build(BuildContext context) => _Loop(
    builder: (t) {
      final p = _pp(t);
      final press = 1 - 0.07 * (p > 0.3 && p < 0.8 ? 1.0 : 0.0);
      final sheet = p > 0.55 ? ((p - 0.55) / 0.3).clamp(0.0, 1.0) : 0.0;
      return Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Align(
            alignment: Alignment.center,
            child: Transform.scale(
              scale: press,
              child: Container(
                width: 56,
                height: 26,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: const Center(
                  child: Icon(Icons.person_rounded, size: 13, color: Color(0xFF0F766E)),
                ),
              ),
            ),
          ),
          if (sheet > 0)
            Transform.translate(
              offset: Offset(0, 22 * (1 - sheet)),
              child: Container(
                height: 22,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.inverseSurface
                      .withValues(alpha: 0.14 + 0.1 * sheet),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(10),
                  ),
                ),
                child: const Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.call_received_rounded, size: 10, color: Color(0xFF0F766E)),
                      SizedBox(width: 8),
                      Icon(Icons.edit_rounded, size: 10, color: Color(0xFF2563EB)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
