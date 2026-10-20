import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format_utils.dart';
import '../core/haptics.dart';
import '../core/jalali_utils.dart';
import '../core/localization.dart';
import '../core/money.dart';
import '../core/platform_info.dart';
import '../data/ledger.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'customer_detail_page.dart';
import 'design.dart';
import 'forms/sell_subscription_page.dart';
import 'motion_kit.dart';
import 'personal_page.dart';
import 'sms_page.dart';
import 'theme.dart';
import 'widgets/common_charts.dart';
import 'widgets/date_picker.dart';
import 'widgets/txn_actions.dart';
import 'widgets/widgets.dart';

enum _DashboardPeriod {
  thisMonth,
  today,
  thisWeek,
  thisYear,
  all,
  custom,
}

/// Unified home dashboard with Personal (`شخصی`) first and Business (`کسب‌وکار`)
/// second, connected by a 1:1 finger-tracking magnetic horizontal slider and
/// featuring dual multi-color donut charts for total expenses and total income.
class DashboardPage extends StatefulWidget {
  const DashboardPage({
    super.key,
    required this.onNavigate,
    this.controller,
    this.initialScope = TxnScope.personal,
  });

  final void Function(int index) onNavigate;

  /// Owned by the shell, so tapping the already-open tab can scroll this page
  /// back to the top. Tests and other callers can leave it null.
  final ScrollController? controller;

  /// Defaults to [TxnScope.personal] so the Personal view is first, followed
  /// by Business.
  final TxnScope initialScope;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  late TxnScope _scope;

  /// Continuous position controller: 0.0 = Personal (first tab),
  /// 1.0 = Business (second tab).
  late final AnimationController _pos;

  bool _isDragging = false;
  bool _gestureConsumed = false;
  double _startPos = 0.0;
  double _dragDx = 0.0;
  double _signedDir = 1.0;

  _DashboardPeriod _period = _DashboardPeriod.thisMonth;
  DateTime? _customFrom;
  DateTime? _customTo;

  (DateTime?, DateTime?) _dashboardBounds() {
    final now = DateTime.now();
    return switch (_period) {
      _DashboardPeriod.thisMonth => (J.startOfMonth(now), J.endOfMonth(now)),
      _DashboardPeriod.today => (J.startOfDay(now), J.endOfDay(now)),
      _DashboardPeriod.thisWeek => (
        J.startOfDay(J.addDays(now, -6)),
        J.endOfDay(now),
      ),
      _DashboardPeriod.thisYear => (J.startOfYear(now), J.endOfMonth(now)),
      _DashboardPeriod.all => (null, null),
      _DashboardPeriod.custom => (
        J.startOfDay(_customFrom ?? J.startOfMonth(now)),
        J.endOfDay(_customTo ?? now),
      ),
    };
  }

  String _periodLabel() => switch (_period) {
    _DashboardPeriod.thisMonth => 'This month'.tr,
    _DashboardPeriod.today => 'Today'.tr,
    _DashboardPeriod.thisWeek => 'This week'.tr,
    _DashboardPeriod.thisYear => 'This year'.tr,
    _DashboardPeriod.all => 'All transactions'.tr,
    _DashboardPeriod.custom =>
      '{from} to {to}'.trArgs({
        'from': J.d(_customFrom ?? J.startOfMonth(DateTime.now())),
        'to': J.d(_customTo ?? DateTime.now()),
      }),
  };

  Future<void> _showDashboardPeriodSheet(BuildContext context) async {
    final options = <(_DashboardPeriod, String, IconData)>[
      (_DashboardPeriod.all, 'All transactions'.tr, Icons.all_inclusive_rounded),
      (_DashboardPeriod.today, 'Today'.tr, Icons.today_rounded),
      (_DashboardPeriod.thisWeek, 'This week'.tr, Icons.date_range_rounded),
      (
        _DashboardPeriod.thisMonth,
        'This month'.tr,
        Icons.calendar_month_rounded,
      ),
      (
        _DashboardPeriod.thisYear,
        'This year'.tr,
        Icons.calendar_view_month_rounded,
      ),
      (
        _DashboardPeriod.custom,
        'Select date range'.tr,
        Icons.edit_calendar_rounded,
      ),
    ];

    final picked = await showLedgerSheet<_DashboardPeriod>(
      context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              const SizedBox(height: 10),
              for (final (period, label, icon) in options)
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: Icon(
                    icon,
                    size: 20,
                    color: _period == period
                        ? scheme.primary
                        : scheme.onSurface.withValues(alpha: 0.65),
                  ),
                  title: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: _period == period
                          ? FontWeight.w800
                          : FontWeight.w600,
                      color: _period == period
                          ? scheme.primary
                          : scheme.onSurface,
                    ),
                  ),
                  trailing: _period == period
                      ? Icon(
                          Icons.check_circle_rounded,
                          size: 19,
                          color: scheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.pop(ctx, period),
                ),
            ],
          ),
        );
      },
    );

    if (picked == null || !mounted) return;
    if (picked == _DashboardPeriod.custom) {
      await _pickCustomDashboardRange();
    } else {
      setState(() => _period = picked);
    }
  }

  Future<void> _pickCustomDashboardRange() async {
    var tempFrom = _customFrom ?? J.startOfMonth(DateTime.now());
    var tempTo = _customTo ?? DateTime.now();

    final applied = await showLedgerSheet<bool>(
      context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final scheme = Theme.of(ctx).colorScheme;
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(ctx).cardColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SheetHandle(),
                  const SizedBox(height: 12),
                  Text(
                    'Select date range'.tr,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () async {
                            final d = await showJalaliPicker(
                              ctx,
                              initial: tempFrom,
                            );
                            if (d != null) {
                              setSheetState(() => tempFrom = d);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: scheme.primary.withValues(alpha: 0.22),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'From date'.tr,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurface.withValues(
                                      alpha: 0.62,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  J.d(tempFrom),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () async {
                            final d = await showJalaliPicker(
                              ctx,
                              initial: tempTo,
                            );
                            if (d != null) {
                              setSheetState(() => tempTo = d);
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: scheme.primary.withValues(alpha: 0.22),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'To date'.tr,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurface.withValues(
                                      alpha: 0.62,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  J.d(tempTo),
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text('Apply'.tr),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (applied == true && mounted) {
      setState(() {
        if (tempTo.isBefore(tempFrom)) {
          _customFrom = tempTo;
          _customTo = tempFrom;
        } else {
          _customFrom = tempFrom;
          _customTo = tempTo;
        }
        _period = _DashboardPeriod.custom;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _scope = widget.initialScope;
    _startPos = _scope == TxnScope.business ? 1.0 : 0.0;
    _pos = AnimationController(
      vsync: this,
      value: _startPos,
      duration: const Duration(milliseconds: 240),
    );
  }

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  /// Continuous 0.0 (Personal, first tab) -> 1.0 (Business, second tab)
  /// progress for the top segmented pill indicator.
  double get _businessProgress => _pos.value.clamp(0.0, 1.0);

  void _changeScopeByTap(AppRepository repo, TxnScope target) {
    final targetPos = target == TxnScope.business ? 1.0 : 0.0;
    if (_scope == target && (_pos.value - targetPos).abs() < 0.001) return;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final dirForTarget = target == TxnScope.business
        ? (isRtl ? 1.0 : -1.0)
        : (isRtl ? -1.0 : 1.0);
    _signedDir = target == TxnScope.business ? dirForTarget : -dirForTarget;
    _isDragging = false;
    _gestureConsumed = true;
    _scope = target;
    Haptics.selection();
    _pos.animateTo(
      targetPos,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  void _handleHorizontalDragStart(DragStartDetails details) {
    if (_pos.isAnimating) {
      _pos.stop();
    }
    _scope = _pos.value >= 0.5 ? TxnScope.business : TxnScope.personal;
    _startPos = _scope == TxnScope.business ? 1.0 : 0.0;
    _pos.value = _startPos;
    _dragDx = 0.0;
    _isDragging = true;
    _gestureConsumed = false;
  }

  void _handleHorizontalDragUpdate(
    AppRepository repo,
    DragUpdateDetails details,
  ) {
    if (_gestureConsumed || !_isDragging) return;
    final width = (context.size?.width ?? 360.0).clamp(240.0, 700.0);
    _dragDx += details.delta.dx;
    if (_dragDx.abs() < 2.0) {
      _pos.value = _startPos;
      return;
    }

    final dir = _dragDx >= 0 ? 1.0 : -1.0;
    _signedDir = _startPos < 0.5 ? dir : -dir;
    final progress = _dragDx.abs().clamp(0.0, width);
    final fraction = (progress / width).clamp(0.0, 1.0);

    // Require dragging ~45% of the screen before the mid-drag magnet
    // automatically pulls the page to the end and locks out the rest of the
    // finger hold.
    if (fraction >= 0.45) {
      _triggerMagneticSnap(
        toBusiness: _startPos < 0.5,
        fromFraction: fraction,
      );
    } else {
      _pos.value = _startPos < 0.5 ? fraction : (1.0 - fraction);
    }
  }

  void _triggerMagneticSnap({
    required bool toBusiness,
    required double fromFraction,
  }) {
    _gestureConsumed = true;
    _isDragging = false;
    final target = toBusiness ? TxnScope.business : TxnScope.personal;
    final targetPos = toBusiness ? 1.0 : 0.0;
    _scope = target;
    Haptics.selection();
    final remaining = (1.0 - fromFraction).clamp(0.15, 1.0);
    final durationMs = (230 * remaining).round().clamp(110, 230);
    _pos.animateTo(
      targetPos,
      duration: Duration(milliseconds: durationMs),
      curve: Curves.easeOutCubic,
    );
  }

  void _handleHorizontalDragEnd(
    AppRepository repo,
    DragEndDetails details,
  ) {
    if (_gestureConsumed || !_isDragging) {
      _isDragging = false;
      return;
    }
    _isDragging = false;
    _gestureConsumed = true;
    final width = (context.size?.width ?? 360.0).clamp(240.0, 700.0);
    final velocity = details.primaryVelocity ?? 0.0;
    final dir = _dragDx.abs() >= 2.0
        ? (_dragDx >= 0 ? 1.0 : -1.0)
        : (velocity >= 0 ? 1.0 : -1.0);
    _signedDir = _startPos < 0.5 ? dir : -dir;
    final progress = _dragDx.abs().clamp(0.0, width);
    final fraction = (progress / width).clamp(0.0, 1.0);
    final flingInSameDir = _dragDx.abs() < 2.0
        ? velocity.abs() > 240
        : (velocity * dir) > 240;
    final shouldSnapToTarget = progress >= width * 0.32 || flingInSameDir;

    if (shouldSnapToTarget) {
      _triggerMagneticSnap(
        toBusiness: _startPos < 0.5,
        fromFraction: fraction,
      );
    } else {
      _pos.animateTo(
        _startPos,
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _handleHorizontalDragCancel() {
    if (_gestureConsumed || !_isDragging) {
      _isDragging = false;
      return;
    }
    _isDragging = false;
    _gestureConsumed = true;
    _pos.animateTo(
      _startPos,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Stack(
      children: [
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 240,
          child: AmbientAurora(),
        ),
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: _handleHorizontalDragStart,
          onHorizontalDragUpdate: (d) => _handleHorizontalDragUpdate(repo, d),
          onHorizontalDragCancel: _handleHorizontalDragCancel,
          onHorizontalDragEnd: (d) => _handleHorizontalDragEnd(repo, d),
          child: RefreshIndicator(
            onRefresh: () => repo.refreshAll(),
            color: Theme.of(context).colorScheme.primary,
            child: ListView(
              controller: widget.controller,
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 100),
              children: [
                // -------- Top Greeting & Date Header --------
                _topHeader(context, repo, onSurface),
                const SizedBox(height: 12),

                // -------- Magnetic Scope Switcher (Personal first, Business second)
                _scopeSwitchBar(repo),
                const SizedBox(height: 12),

                // -------- Bank SMS Quick Card (Android only) --------
                if (isAndroidPlatform) ...[
                  _bankSmsBanner(context, repo, onSurface),
                  const SizedBox(height: 12),
                ],

                // -------- Magnetic 2-Page Scope Content --------
                _buildMagneticScopeBody(context, repo),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _topHeader(
    BuildContext context,
    AppRepository repo,
    Color onSurface,
  ) {
    return Wrap(
      spacing: Insets.sm,
      runSpacing: Insets.sm,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: MediaQuery.sizeOf(context).width < 360
              ? double.infinity
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hello 👋'.tr,
                style: TextStyle(
                  fontSize: 13,
                  color: onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                J.mLabel(DateTime.now()),
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        AnimatedBuilder(
          animation: _pos,
          builder: (context, _) {
            if (_pos.value >= 0.5) {
              return TagChip(
                '{count} active subscriptions'.trArgs({
                  'count': repo.activeSubsCount,
                }),
                color: const Color(0xFF16A34A),
                icon: Icons.check_circle_rounded,
              );
            }
            return TagChip(
              'Personal'.tr,
              color: Theme.of(context).colorScheme.primary,
              icon: Icons.person_rounded,
            );
          },
        ),
      ],
    );
  }

  /// Segmented bar with «شخصی» (`Personal`) first and «کسب‌وکار» (`Business`)
  /// second, whose active pill glides continuously with finger drag and snaps
  /// magnetically into place.
  Widget _scopeSwitchBar(AppRepository repo) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _pos,
      builder: (context, _) {
        final p = _businessProgress;
        final alignX = -1.0 + 2.0 * p;

        return Container(
          height: 44,
          padding: const EdgeInsets.all(3.5),
          decoration: BoxDecoration(
            color: scheme.onSurface.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: scheme.onSurface.withValues(alpha: 0.08),
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: AlignmentDirectional(alignX, 0),
                  child: FractionallySizedBox(
                    widthFactor: 0.5,
                    heightFactor: 1.0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(10.5),
                        border: Border.all(
                          color: scheme.primary.withValues(alpha: 0.42),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _DashboardScopeTab(
                      label: 'Personal'.tr,
                      icon: Icons.person_outline_rounded,
                      selected: p < 0.5,
                      onTap: () => _changeScopeByTap(repo, TxnScope.personal),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: _DashboardScopeTab(
                      label: 'Business'.tr,
                      icon: Icons.business_center_outlined,
                      selected: p >= 0.5,
                      onTap: () => _changeScopeByTap(repo, TxnScope.business),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _bankSmsBanner(
    BuildContext context,
    AppRepository repo,
    Color onSurface,
  ) {
    return CardBox(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SmsPage()),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (repo.smsPendingCount > 0
                      ? const Color(0xFF16A34A)
                      : const Color(0xFF7C3AED))
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              Icons.sms_rounded,
              size: 19,
              color: repo.smsPendingCount > 0
                  ? const Color(0xFF16A34A)
                  : const Color(0xFF7C3AED),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bank SMS'.tr,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  repo.smsPendingCount > 0
                      ? '{count} transactions awaiting review'.trArgs({
                          'count': repo.smsPendingCount,
                        })
                      : 'Sync bank SMS to review transactions'.tr,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          if (repo.smsPendingCount > 0)
            TagChip(
              '${repo.smsPendingCount}',
              color: const Color(0xFF16A34A),
              dense: true,
            )
          else
            const Icon(Icons.chevron_right_rounded, size: 18),
        ],
      ),
    );
  }

  Widget _buildMagneticScopeBody(BuildContext context, AppRepository repo) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 32;

        // Pre-build and keep both scope pages mounted inside RepaintBoundaries
        // and Offstage so finger dragging and magnetic snapping translate GPU
        // layers at 60–120 FPS with zero widget tree teardown or rebuilds.
        final personalChild = RepaintBoundary(
          child: _buildScopeContent(context, repo, TxnScope.personal),
        );
        final businessChild = RepaintBoundary(
          child: _buildScopeContent(context, repo, TxnScope.business),
        );

        return ClipRect(
          child: AnimatedBuilder(
            animation: _pos,
            builder: (context, _) {
              final p = _pos.value.clamp(0.0, 1.0);
              final isPurePersonal = p <= 0.001;
              final isPureBusiness = p >= 0.999;
              final isMoving = !isPurePersonal && !isPureBusiness;
              final tab0Dx = isPurePersonal ? 0.0 : _signedDir * width * p;
              final tab1Dx = isPureBusiness
                  ? 0.0
                  : _signedDir * width * (p - 1.0);

              return Stack(
                alignment: Alignment.topCenter,
                children: [
                  Offstage(
                    offstage: isPureBusiness,
                    child: IgnorePointer(
                      ignoring: isMoving || isPureBusiness,
                      child: Transform.translate(
                        offset: Offset(tab0Dx, 0),
                        child: personalChild,
                      ),
                    ),
                  ),
                  Offstage(
                    offstage: isPurePersonal,
                    child: IgnorePointer(
                      ignoring: isMoving || isPurePersonal,
                      child: Transform.translate(
                        offset: Offset(tab1Dx, 0),
                        child: businessChild,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildScopeContent(
    BuildContext context,
    AppRepository repo,
    TxnScope pageScope,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _buildScopeChildren(context, repo, pageScope),
    );
  }

  List<Widget> _buildScopeChildren(
    BuildContext context,
    AppRepository repo,
    TxnScope pageScope,
  ) {
    final (rangeFrom, rangeTo) = _dashboardBounds();
    final monthSummary = repo.summary(
      from: rangeFrom,
      to: rangeTo,
      scope: pageScope,
    );
    final expenseByCategory = Ledger.byCategory(
      repo.transactions,
      repo.categories,
      from: rangeFrom,
      to: rangeTo,
      kind: TxnKind.expense,
      scope: pageScope,
    );
    final incomeByCategory = Ledger.byCategory(
      repo.transactions,
      repo.categories,
      from: rangeFrom,
      to: rangeTo,
      kind: TxnKind.income,
      scope: pageScope,
    );
    final series = repo.series(months: 6, scope: pageScope);
    final recent = repo.transactions
        .where((t) => t.scope == pageScope)
        .take(5)
        .toList();
    final hasNoTransactions = repo.transactions.isEmpty;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final compactLayout = MediaQuery.sizeOf(context).width < 360;

    return <Widget>[
        // -------- 1. Hero Monthly Summary Card --------
        _monthlyHeroCard(
          context: context,
          monthSummary: monthSummary,
          onSurface: onSurface,
          compactLayout: compactLayout,
        ),
        const SizedBox(height: 12),

        // -------- 2. Dual Multi-Color Donut Charts (Expense & Income) --------
        _DualDonutSection(
          expenseData: expenseByCategory,
          incomeData: incomeByCategory,
        ),
        const SizedBox(height: 12),

        // -------- 3. Scope-Specific Cards --------
        if (pageScope == TxnScope.business)
          _businessMetricsSection(
            context: context,
            repo: repo,
            monthSummary: monthSummary,
            onSurface: onSurface,
            compactLayout: compactLayout,
          )
        else
          _personalBudgetsSection(
            context: context,
            repo: repo,
            onSurface: onSurface,
            compactLayout: compactLayout,
          ),

        // -------- 4. Six-Month Trend Bar Chart --------
        const SizedBox(height: 14),
        CollapsibleCard(
          title: 'Last 6 months',
          icon: Icons.bar_chart_rounded,
          summary: CopyMoney(
            value: series.fold<double>(0, (sum, p) => sum + p.profit),
            child: OdometerMoney(
              series.fold<double>(0, (sum, p) => sum + p.profit),
              compact: true,
              signed: true,
              style: const TextStyle(
                fontSize: FontSizes.small,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          bodyPadding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
          child: SizedBox(height: 190, child: MonthlyBarChart(points: series)),
        ),

        // -------- 5. Recent Transactions --------
        SectionTitle(
          'Recent transactions',
          icon: Icons.receipt_long_outlined,
          action: 'All'.tr,
          onAction: () {
            repo.setScopeFilter(pageScope);
            widget.onNavigate(3);
          },
        ),
        if (recent.isEmpty)
          EmptyState(
            icon: Icons.receipt_long_outlined,
            title: hasNoTransactions
                ? 'No transactions yet'
                : 'No transactions in this view',
            text: hasNoTransactions
                ? 'Tap + to record your first sale or expense.'
                : 'Change the account filter or show all transactions.',
            actionLabel: hasNoTransactions ? null : 'Show all transactions',
            onAction: hasNoTransactions
                ? null
                : () {
                    repo.setScopeFilter(null);
                    widget.onNavigate(3);
                  },
          )
        else
          Card(
            child: Column(
              children: [
                for (var i = 0; i < recent.length; i++) ...[
                  SwipeActions(
                    actions: txnSwipeActions(context, recent[i], repo),
                    child: TxnTile(
                      txn: recent[i],
                      categoryName: repo.categoryName(recent[i].categoryId),
                      customerName: repo.customerName(recent[i].customerId),
                    ),
                  ),
                  if (i != recent.length - 1)
                    Divider(height: 1, color: Theme.of(context).dividerColor),
                ],
              ],
            ),
          ),
      ];
  }

  Widget _monthlyHeroCard({
    required BuildContext context,
    required Summary monthSummary,
    required Color onSurface,
    required bool compactLayout,
  }) {
    final totalFlow = monthSummary.income + monthSummary.expense;
    final incomeShare = totalFlow <= 0
        ? 0.5
        : (monthSummary.income / totalFlow).clamp(0.06, 0.94);

    return BreathingGradient(
      borderRadius: BorderRadius.circular(Radii.card),
      base: [
        const Color(0xFF087F78).withValues(alpha: 0.030),
        const Color(0xFF7C3AED).withValues(alpha: 0.018),
      ],
      variant: [
        const Color(0xFF087F78).withValues(alpha: 0.075),
        const Color(0xFF7C3AED).withValues(alpha: 0.040),
      ],
      child: CardBox(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => _showDashboardPeriodSheet(context),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_month_rounded,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _periodLabel(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: onSurface.withValues(alpha: 0.78),
                        ),
                      ),
                    ),
                    Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: onSurface.withValues(alpha: 0.58),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (compactLayout)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _miniStat(
                    context,
                    'Income received',
                    monthSummary.income,
                    const Color(0xFF16A34A),
                    Icons.trending_up_rounded,
                  ),
                  const SizedBox(height: 10),
                  Divider(color: Theme.of(context).dividerColor),
                  const SizedBox(height: 10),
                  _miniStat(
                    context,
                    'Expense',
                    monthSummary.expense,
                    const Color(0xFFE11D48),
                    Icons.trending_down_rounded,
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: _miniStat(
                      context,
                      'Income received',
                      monthSummary.income,
                      const Color(0xFF16A34A),
                      Icons.trending_up_rounded,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 42,
                    color: Theme.of(context).dividerColor,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _miniStat(
                      context,
                      'Expense',
                      monthSummary.expense,
                      const Color(0xFFE11D48),
                      Icons.trending_down_rounded,
                    ),
                  ),
                ],
              ),
            if (totalFlow > 0) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: SizedBox(
                  height: 6,
                  child: Row(
                    children: [
                      Expanded(
                        flex: (incomeShare * 100).round(),
                        child: Container(color: const Color(0xFF16A34A)),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        flex: ((1 - incomeShare) * 100).round(),
                        child: Container(color: const Color(0xFFE11D48)),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Divider(color: Theme.of(context).dividerColor),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  Icons.savings_rounded,
                  size: 18,
                  color: monthSummary.profit >= 0
                      ? const Color(0xFF16A34A)
                      : const Color(0xFFE11D48),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Profit this month'.tr,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: CopyMoney(
                    value: monthSummary.profit,
                    child: OdometerMoney(
                      monthSummary.profit,
                      compact: compactLayout,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: monthSummary.profit >= 0
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFE11D48),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _personalBudgetsSection({
    required BuildContext context,
    required AppRepository repo,
    required Color onSurface,
    required bool compactLayout,
  }) {
    final usages = repo.budgetUsages();
    if (usages.isEmpty) {
      return CardBox(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () => showLedgerSheet<void>(
          context,
          builder: (_) => const BudgetEditSheet(),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.pie_chart_outline_rounded,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Monthly budgets'.tr,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Set a spending cap for categories like Food or Transport.'
                        .tr,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.add_rounded, size: 20),
          ],
        ),
      );
    }

    return CardBox(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart_outline_rounded, size: 17),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Monthly budgets'.tr,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'New budget'.tr,
                visualDensity: VisualDensity.compact,
                onPressed: () => showLedgerSheet<void>(
                  context,
                  builder: (_) => const BudgetEditSheet(),
                ),
                icon: const Icon(Icons.add_rounded, size: 19),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final u in usages.take(4))
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (compactLayout) ...[
                    Text(
                      u.categoryName.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${Money.text(u.spent, compact: true)} / ${Money.text(u.budget.limit, compact: true)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ] else
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            u.categoryName.tr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${Money.text(u.spent, compact: true)} / ${Money.text(u.budget.limit, compact: true)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      minHeight: 6,
                      value: u.ratio.clamp(0.0, 1.0),
                      backgroundColor: onSurface.withValues(alpha: 0.08),
                      color: switch (u.level) {
                        2 => AppTheme.expense,
                        1 => const Color(0xFFF59E0B),
                        _ => AppTheme.revenue,
                      },
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _businessMetricsSection({
    required BuildContext context,
    required AppRepository repo,
    required Summary monthSummary,
    required Color onSurface,
    required bool compactLayout,
  }) {
    final totals = repo.totals;
    final alerts = repo.alerts;

    Widget responsivePair(Widget first, Widget second) => LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = compactLayout
            ? constraints.maxWidth
            : (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(width: cardWidth, child: first),
            SizedBox(width: cardWidth, child: second),
          ],
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        responsivePair(
          CardBox(
            onTap: () => widget.onNavigate(1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Business receivables'.tr,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: onSurface.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 6),
                CopyMoney(
                  value: totals.receivable,
                  child: OdometerMoney(
                    totals.receivable,
                    compact: compactLayout,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '{count} debtors'.trArgs({'count': totals.debtorsCount}),
                  style: TextStyle(
                    fontSize: 11,
                    color: onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          CardBox(
            onTap: () => widget.onNavigate(1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Business payables'.tr,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: onSurface.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 6),
                CopyMoney(
                  value: totals.payable,
                  child: OdometerMoney(
                    totals.payable,
                    compact: compactLayout,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2563EB),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '{count} creditors'.trArgs({
                    'count': totals.creditorsCount,
                  }),
                  style: TextStyle(
                    fontSize: 11,
                    color: onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        responsivePair(
          CardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Business cash balance'.tr,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: onSurface.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 6),
                CopyMoney(
                  value: repo.cashBalance,
                  child: OdometerMoney(
                    repo.cashBalance,
                    compact: compactLayout,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF7C3AED),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Cash + bank'.tr,
                  style: TextStyle(
                    fontSize: 11,
                    color: onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          CardBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Received this month'.tr,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: onSurface.withValues(alpha: 0.65),
                  ),
                ),
                const SizedBox(height: 6),
                CopyMoney(
                  value: monthSummary.cashIn,
                  child: OdometerMoney(
                    monthSummary.cashIn,
                    compact: compactLayout,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Cash + collections'.tr,
                  style: TextStyle(
                    fontSize: 11,
                    color: onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (alerts.isNotEmpty) ...[
          const SizedBox(height: 6),
          SectionTitle(
            'Subscriptions expiring soon or expired',
            icon: Icons.notification_important_outlined,
            action: 'All'.tr,
            onAction: () => widget.onNavigate(2),
          ),
          ...alerts.take(4).map((s) {
            final customer = repo.customerById(s.customerId);
            final status = Ledger.subStatus(
              s,
              reminderDays: repo.settings.reminderDays,
            );
            final days = Ledger.daysLeft(s);
            final compact = MediaQuery.sizeOf(context).width < 360;
            final info = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer?.name ?? 'No customer'.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${s.planName.tr} • ${J.d(s.endDate)}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            );
            final expiryTag = TagChip(
              Fmt.expiryLabel(days),
              color: status.color,
              dense: true,
              maxWidth: compact ? 140 : null,
            );
            final renewButton = IconButton(
              tooltip: 'Renew'.tr,
              style: IconButton.styleFrom(
                minimumSize: const Size(Taps.icon, Taps.icon),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SellSubscriptionPage(renewFrom: s),
                ),
              ),
              icon: const Icon(Icons.autorenew_rounded, size: 19),
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CardBox(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                onTap: customer == null
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              CustomerDetailPage(customer: customer),
                        ),
                      ),
                child: compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          info,
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              expiryTag,
                              const Spacer(),
                              renewButton,
                            ],
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: info),
                          expiryTag,
                          const SizedBox(width: 6),
                          renewButton,
                        ],
                      ),
              ),
            );
          }),
        ],
      ],
    );
  }

  Widget _miniStat(
    BuildContext context,
    String label,
    double value,
    Color color,
    IconData icon,
  ) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                label.tr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  color: onSurface.withValues(alpha: 0.65),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        CopyMoney(
          value: value,
          child: OdometerMoney(
            value,
            compact: MediaQuery.sizeOf(context).width < 360,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

/// Renders the two multi-color donut charts side-by-side on wide screens or
/// stacked on mobile, showing category-by-category shares for both Total
/// Expense and Total Income.
class _DualDonutSection extends StatelessWidget {
  const _DualDonutSection({
    required this.expenseData,
    required this.incomeData,
  });

  final Map<String, double> expenseData;
  final Map<String, double> incomeData;

  static const _expensePalette = <Color>[
    Color(0xFFE11D48), // Rose
    Color(0xFFF97316), // Orange
    Color(0xFF8B5CF6), // Violet
    Color(0xFFF59E0B), // Amber
    Color(0xFFEC4899), // Pink
    Color(0xFF6366F1), // Indigo
    Color(0xFF06B6D4), // Cyan
    Color(0xFF14B8A6), // Teal
  ];

  static const _incomePalette = <Color>[
    Color(0xFF10B981), // Emerald
    Color(0xFF0EA5A4), // Teal
    Color(0xFF3B82F6), // Blue
    Color(0xFF6366F1), // Indigo
    Color(0xFF22C55E), // Green
    Color(0xFF8B5CF6), // Purple
    Color(0xFFF59E0B), // Amber
    Color(0xFFEC4899), // Pink
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide = constraints.maxWidth >= 600;
        final expenseCard = _CategoryDonutCard(
          title: 'Total expense'.tr,
          icon: Icons.trending_down_rounded,
          accent: AppTheme.expense,
          data: expenseData,
          palette: _expensePalette,
        );
        final incomeCard = _CategoryDonutCard(
          title: 'Total income'.tr,
          icon: Icons.trending_up_rounded,
          accent: AppTheme.revenue,
          data: incomeData,
          palette: _incomePalette,
        );

        if (sideBySide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: expenseCard),
              const SizedBox(width: 12),
              Expanded(child: incomeCard),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            expenseCard,
            const SizedBox(height: 10),
            incomeCard,
          ],
        );
      },
    );
  }
}

/// Multi-color donut ring + category breakdown card for either Expense or Income.
class _CategoryDonutCard extends StatelessWidget {
  const _CategoryDonutCard({
    required this.title,
    required this.icon,
    required this.accent,
    required this.data,
    required this.palette,
  });

  final String title;
  final IconData icon;
  final Color accent;
  final Map<String, double> data;
  final List<Color> palette;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final entries = data.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = entries.fold<double>(0, (sum, e) => sum + e.value);

    return CardBox(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // -------- Card Header: Title + Total Amount --------
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, size: 16, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: CopyMoney(
                  value: total,
                  child: OdometerMoney(
                    total,
                    compact: MediaQuery.sizeOf(context).width < 360,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // -------- Multi-Color Donut Ring + Category Legend --------
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 290;
              final ringSize = narrow ? 104.0 : 114.0;
              final ring = SizedBox(
                width: ringSize,
                height: ringSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: entries.length > 1 ? 2.5 : 0,
                        centerSpaceRadius: ringSize * 0.30,
                        sections: entries.isEmpty
                            ? [
                                PieChartSectionData(
                                  value: 1,
                                  color: onSurface.withValues(alpha: 0.08),
                                  radius: ringSize * 0.16,
                                  showTitle: false,
                                ),
                              ]
                            : [
                                for (var i = 0; i < entries.length; i++)
                                  PieChartSectionData(
                                    value: entries[i].value,
                                    color: palette[i % palette.length],
                                    radius: ringSize * 0.18,
                                    showTitle:
                                        total > 0 &&
                                        entries[i].value / total >= 0.14,
                                    title: Fmt.percent(
                                      entries[i].value / total,
                                    ),
                                    titleStyle: const TextStyle(
                                      fontFamily: 'Vazirmatn',
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                    ),
                                  ),
                              ],
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.donut_large_rounded,
                          size: 16,
                          color: entries.isEmpty
                              ? onSurface.withValues(alpha: 0.3)
                              : accent,
                        ),
                        if (entries.isNotEmpty)
                          Text(
                            Fmt.persianDigits
                                ? Fmt.toFaDigits('${entries.length}')
                                : '${entries.length}',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: onSurface.withValues(alpha: 0.75),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );

              final legend = entries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No transactions in this view'.tr,
                        style: TextStyle(
                          fontSize: 12,
                          color: onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (
                          var i = 0;
                          i < entries.length && i < 5;
                          i++
                        ) ...[
                          _DonutLegendRow(
                            color: palette[i % palette.length],
                            label: entries[i].key.tr,
                            amount: entries[i].value,
                            share: total <= 0 ? 0 : entries[i].value / total,
                          ),
                          if (i != math.min(entries.length, 5) - 1)
                            const SizedBox(height: 7),
                        ],
                      ],
                    );

              if (narrow) {
                return Column(
                  children: [
                    ring,
                    const SizedBox(height: 12),
                    legend,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ring,
                  const SizedBox(width: 14),
                  Expanded(child: legend),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DonutLegendRow extends StatelessWidget {
  const _DonutLegendRow({
    required this.color,
    required this.label,
    required this.amount,
    required this.share,
  });

  final Color color;
  final String label;
  final double amount;
  final double share;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              Fmt.percent(share),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                Money.text(amount, compact: true, withSymbol: false),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: onSurface.withValues(alpha: 0.82),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            minHeight: 3.5,
            value: share.clamp(0.0, 1.0),
            backgroundColor: onSurface.withValues(alpha: 0.06),
            color: color.withValues(alpha: 0.85),
          ),
        ),
      ],
    );
  }
}

class _DashboardScopeTab extends StatelessWidget {
  const _DashboardScopeTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected
                  ? scheme.primary
                  : onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                  color: selected
                      ? scheme.primary
                      : onSurface.withValues(alpha: 0.72),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
