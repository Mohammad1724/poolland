import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format_utils.dart';
import '../../core/haptics.dart';
import '../../core/localization.dart';
import '../../core/money.dart';
import '../../core/sms/sms_models.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../design.dart';
import '../motion_kit.dart';
import '../settings_page.dart';
import '../theme.dart';
import '../widgets/widgets.dart';
import 'contact_edit_page.dart';

/// Compact, one-screen sheet for reviewing and approving a bank SMS.
///
/// Supports:
/// - Interactive Income (`درآمد`) / Expense (`هزینه`) toggle in the top header.
/// - Finger-tracking horizontal drag with magnetic snap between Personal
///   (`شخصی`, first) and Business (`کسب‌وکار`, second), keeping the sheet
///   height constant.
/// - «به حساب» (Expense) / «از حساب» (Income) button that opens a hierarchical
///   category -> subcategory picker window, plus an inline search bar for
///   directly searching categories and subcategories.
/// - One-tap subcategory shortcuts (`میان‌بر`) pinned directly on the sheet,
///   color-coded to match Expense (red) or Income (green).
/// - Contact («مخاطب») selector button in Business scope that opens a contact
///   picker sheet.
class SmsReviewSheet extends StatefulWidget {
  const SmsReviewSheet({super.key, required this.sms, this.initialCustomer});

  final ParsedSms sms;
  final Customer? initialCustomer;

  @override
  State<SmsReviewSheet> createState() => _SmsReviewSheetState();
}

class _SmsReviewSheetState extends State<SmsReviewSheet>
    with SingleTickerProviderStateMixin {
  late TextEditingController _amount;
  late AnimationController _pos;
  Customer? _customer;
  late bool _isIncome;
  TxnKind _kind = TxnKind.income;
  TxnScope _scope = TxnScope.personal;

  // Magnetic pager state: 0.0 = Personal (first tab), 1.0 = Business (second tab).
  bool _isDragging = false;
  bool _gestureConsumed = false;
  double _startPos = 0.0;
  double _dragDx = 0.0;
  double _dragDir = 0.0;
  double _signedDir = 1.0;

  // Locked height so switching between Personal and Business never changes
  // the bottom sheet's vertical size.
  final GlobalKey _businessMeasureKey = GlobalKey();
  double _lockedScopeHeight = 192.0;

  // Separate category selections per scope so peeking the other page during
  // a drag shows a valid category for that scope too.
  String? _categoryId;
  bool _presetDone = false;

  @override
  void initState() {
    super.initState();
    _isIncome = widget.sms.direction != SmsDirection.withdraw;
    _amount = TextEditingController(
      text: groupedNumber(
        widget.sms.amount,
        decimals: Money.decimals(widget.sms.currency),
      ),
    );
    final initialPos = widget.initialCustomer != null ? 1.0 : 0.0;
    _startPos = initialPos;
    _pos = AnimationController(
      vsync: this,
      value: initialPos,
      duration: const Duration(milliseconds: 240),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_presetDone) return;
    _presetDone = true;
    final repo = context.read<AppRepository>();
    _scope = widget.initialCustomer != null
        ? TxnScope.business
        : TxnScope.personal;
    _startPos = _scope == TxnScope.business ? 1.0 : 0.0;
    _pos.value = _startPos;
    _customer = widget.initialCustomer;
    _kind = _suggestedKind(repo, _scope);
    _categoryId = _suggestedCategoryId(repo, _scope);
  }

  @override
  void dispose() {
    _pos.dispose();
    _amount.dispose();
    super.dispose();
  }

  /// Continuous 1.0 (Personal, first tab) -> 0.0 (Business, second tab)
  /// progress for the top tab pill.
  double get _personalProgress => (1.0 - _pos.value).clamp(0.0, 1.0);

  void _measureScopeHeights() {
    if (_customer != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _businessMeasureKey.currentContext;
      if (ctx == null) return;
      final box = ctx.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        final h = box.size.height;
        if (h > 120 && (h - _lockedScopeHeight).abs() > 1.0) {
          setState(() => _lockedScopeHeight = h);
        }
      }
    });
  }

  TxnKind _suggestedKind(AppRepository repo, TxnScope scope) {
    if (_isIncome) {
      if (scope == TxnScope.business &&
          _customer != null &&
          repo.balanceOf(_customer!) > 0.5) {
        return TxnKind.receive;
      }
      return TxnKind.income;
    }
    return TxnKind.expense;
  }

  TxnKind? _categoryKind(TxnKind kind) => switch (kind) {
    TxnKind.income || TxnKind.receive => TxnKind.income,
    TxnKind.expense => TxnKind.expense,
    _ => null,
  };

  String? _suggestedCategoryId(AppRepository repo, TxnScope scope) {
    final kind = _categoryKind(_suggestedKind(repo, scope));
    return kind == null ? null : repo.defaultCategoryId(kind, scope: scope);
  }

  List<TxnKind> _availableKinds(AppRepository repo, TxnScope scope) {
    if (scope == TxnScope.personal) {
      return [_isIncome ? TxnKind.income : TxnKind.expense];
    }
    if (_isIncome) {
      return [
        TxnKind.income,
        if (_customer != null && repo.balanceOf(_customer!) > 0.5)
          TxnKind.receive,
      ];
    }
    return [
      TxnKind.expense,
      if (_customer != null) TxnKind.refund,
      if (_customer != null && repo.balanceOf(_customer!) < -0.5)
        TxnKind.payablePayment,
    ];
  }

  void _changeDirection(AppRepository repo, bool isIncome) {
    if (_isIncome == isIncome) return;
    Haptics.selection();
    setState(() {
      _isIncome = isIncome;
      _kind = _suggestedKind(repo, _scope);
      _categoryId = _suggestedCategoryId(repo, _scope);
    });
  }

  void _applyScopeState(AppRepository repo, TxnScope scope) {
    _scope = scope;
    _customer = scope == TxnScope.business
        ? (_customer ?? widget.initialCustomer)
        : null;
    _kind = _suggestedKind(repo, scope);
    _categoryId = _suggestedCategoryId(repo, scope);
  }

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
    Haptics.selection();
    _pos
        .animateTo(
          targetPos,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        )
        .then((_) {
          if (!mounted) return;
          setState(() {
            _applyScopeState(repo, target);
          });
        });
  }

  void _handleHorizontalDragStart(DragStartDetails details) {
    if (_pos.isAnimating) {
      _pos.stop();
    }
    _scope = _pos.value >= 0.5 ? TxnScope.business : TxnScope.personal;
    _startPos = _scope == TxnScope.business ? 1.0 : 0.0;
    _pos.value = _startPos;
    _dragDx = 0.0;
    _dragDir = 0.0;
    _isDragging = true;
    _gestureConsumed = false;
  }

  void _handleHorizontalDragUpdate(
    AppRepository repo,
    DragUpdateDetails details,
  ) {
    if (_gestureConsumed || !_isDragging) return;
    final width = (context.size?.width ?? 360.0).clamp(240.0, 600.0);
    _dragDx += details.delta.dx;
    if (_dragDir == 0.0) {
      if (_dragDx.abs() < 8.0) {
        _pos.value = _startPos;
        return;
      }
      _dragDir = _dragDx.sign;
      _signedDir = _startPos < 0.5 ? _dragDir : -_dragDir;
    }

    final progress = ((_dragDx * _dragDir) - 8.0).clamp(0.0, width);
    final fraction = (progress / width).clamp(0.0, 1.0);
    // Require dragging ~45% of the sheet before the mid-drag magnet
    // automatically pulls it to the end and locks out the rest of the hold.
    if (fraction >= 0.45) {
      _triggerMagneticSnap(
        repo,
        toBusiness: _startPos < 0.5,
        fromFraction: fraction,
      );
    } else {
      _pos.value = _startPos < 0.5 ? fraction : (1.0 - fraction);
    }
  }

  void _triggerMagneticSnap(
    AppRepository repo, {
    required bool toBusiness,
    required double fromFraction,
  }) {
    _gestureConsumed = true;
    _isDragging = false;
    final target = toBusiness ? TxnScope.business : TxnScope.personal;
    final targetPos = toBusiness ? 1.0 : 0.0;
    Haptics.selection();
    final remaining = (1.0 - fromFraction).clamp(0.15, 1.0);
    final durationMs = (230 * remaining).round().clamp(110, 230);
    _pos
        .animateTo(
          targetPos,
          duration: Duration(milliseconds: durationMs),
          curve: Curves.easeOutCubic,
        )
        .then((_) {
          if (!mounted) return;
          setState(() {
            _applyScopeState(repo, target);
          });
        });
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
    final width = (context.size?.width ?? 360.0).clamp(240.0, 600.0);
    final velocity = details.primaryVelocity ?? 0.0;
    final dir = _dragDir != 0.0
        ? _dragDir
        : (velocity.abs() > 1.0 ? velocity.sign : 0.0);
    if (dir == 0.0) {
      _pos.value = _startPos;
      return;
    }
    _signedDir = _startPos < 0.5 ? dir : -dir;
    final progress = _dragDir != 0.0
        ? ((_dragDx * _dragDir) - 8.0).clamp(0.0, width)
        : 0.0;
    final fraction = (progress / width).clamp(0.0, 1.0);
    final flingInSameDir = (velocity * dir) > 240;
    final shouldSnapToTarget = progress >= width * 0.30 || flingInSameDir;

    if (shouldSnapToTarget) {
      _triggerMagneticSnap(
        repo,
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

  void _onCustomerSelected(AppRepository repo, Customer? c) {
    setState(() {
      _customer = c;
      final available = _availableKinds(repo, _scope);
      if (!available.contains(_kind)) {
        _kind = _suggestedKind(repo, _scope);
        _categoryId = _suggestedCategoryId(repo, _scope);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final sms = widget.sms;
    _measureScopeHeights();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.sheet),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: _handleHorizontalDragStart,
        onHorizontalDragUpdate: (d) => _handleHorizontalDragUpdate(repo, d),
        onHorizontalDragCancel: _handleHorizontalDragCancel,
        onHorizontalDragEnd: (d) => _handleHorizontalDragEnd(repo, d),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SheetHandle(),
              const SizedBox(height: 10),

              // -------- Header with interactive Income / Expense toggle -----
              _header(repo, sms),
              const SizedBox(height: 12),

              // -------- Scope toggle (tap or swipe horizontally) --------
              _scopeRow(repo),
              const SizedBox(height: 10),

              // -------- Amount (single compact field) --------
              AmountField(
                controller: _amount,
                label: 'Amount',
                currency: sms.currency,
                livePreview: false,
                onChanged: () => setState(() {}),
              ),

              // -------- Magnetic 2-page viewport with fixed height --------
              _buildMagneticScopeViewport(repo),

              const SizedBox(height: 14),

              // -------- Action buttons --------
              _actionBar(repo, sms),
            ],
          ),
        ),
      ),
    );
  }

  /// Renders the active scope page (and during a swipe/magnetic snap, both
  /// the outgoing and incoming pages side-by-side) inside a fixed-height
  /// viewport so the sheet height never jumps when switching scopes.
  Widget _buildMagneticScopeViewport(AppRepository repo) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: _lockedScopeHeight),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : MediaQuery.sizeOf(context).width - 32;

          final personalChild = RepaintBoundary(
            child: _buildScopePage(repo, TxnScope.personal),
          );
          final businessChild = RepaintBoundary(
            child: _buildScopePage(
              repo,
              TxnScope.business,
              measureKey: _businessMeasureKey,
            ),
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
      ),
    );
  }

  Widget _buildScopePage(
    AppRepository repo,
    TxnScope pageScope, {
    Key? measureKey,
  }) {
    final isCurrentScope = pageScope == _scope;
    final pageKind = isCurrentScope
        ? _kind
        : _suggestedKind(repo, pageScope);
    final categoryKind = _categoryKind(pageKind);
    final pageCategoryId = isCurrentScope
        ? _categoryId
        : _suggestedCategoryId(repo, pageScope);
    final shortcuts = categoryKind == null
        ? const <Category>[]
        : repo.shortcutCategories(categoryKind, scope: pageScope);
    final availableKinds = _availableKinds(repo, pageScope);

    return Column(
      key: measureKey,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (availableKinds.length > 1) ...[
          const SizedBox(height: 8),
          TxnKindStrip(
            kinds: availableKinds,
            selected: pageKind,
            onSelect: (k) => setState(() {
              _kind = k;
              _categoryId = _suggestedCategoryId(repo, pageScope);
            }),
          ),
        ],

        // -------- «به حساب» / «از حساب» + Inline Search + Shortcuts --------
        if (categoryKind != null) ...[
          const SizedBox(height: 12),
          AccountSelectorSection(
            repo: repo,
            categoryKind: categoryKind,
            scope: pageScope,
            selectedCategoryId: pageCategoryId,
            shortcuts: shortcuts,
            onSelectCategory: (cat) => setState(() => _categoryId = cat.id),
          ),
        ],

        // -------- Contact (Business scope only) --------
        if (pageScope == TxnScope.business) ...[
          const SizedBox(height: 10),
          ContactSelectorSection(
            repo: repo,
            selectedCustomer: _customer,
            onSelectCustomer: (c) => _onCustomerSelected(repo, c),
          ),
        ],
      ],
    );
  }

  Widget _header(AppRepository repo, ParsedSms sms) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _isIncome ? AppTheme.revenue : AppTheme.expense;
    final bank = sms.bankName?.tr ??
        (sms.message.address.isNotEmpty
            ? sms.message.address
            : 'Pasted message'.tr);

    return Row(
      children: [
        AnimatedContainer(
          duration: Motion.adaptive(context, Motion.expand),
          curve: Curves.easeOutCubic,
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            _isIncome
                ? Icons.south_west_rounded
                : Icons.north_east_rounded,
            size: 18,
            color: accent,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Record this SMS transaction'.tr,
                style: const TextStyle(
                  fontSize: FontSizes.body,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                bank,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: FontSizes.caption,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        DirectionToggle(
          isIncome: _isIncome,
          onSelect: (inc) => _changeDirection(repo, inc),
        ),
      ],
    );
  }

  /// Segmented bar whose highlight pill tracks `_personalProgress` continuously
  /// during finger drag and snaps magnetically to the active tab.
  Widget _scopeRow(AppRepository repo) {
    return AnimatedBuilder(
      animation: _pos,
      builder: (context, _) => ScopeMagneticBar(
        personalProgress: _personalProgress,
        onSelectScope: (sc) => _changeScopeByTap(repo, sc),
      ),
    );
  }

  Widget _actionBar(AppRepository repo, ParsedSms sms) {
    final value = parseAmount(_amount.text);
    final ready = value > 0;
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 46,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'.tr),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 46,
            child: FilledButton.icon(
              onPressed: ready
                  ? () async {
                      await repo.approveSms(
                        sms,
                        customer: _customer,
                        kind: _kind,
                        categoryId: _categoryId,
                        amount: value,
                        scope: _scope,
                      );
                      if (mounted) {
                        MoneyCelebration.recorded(context);
                        Navigator.pop(context, true);
                      }
                    }
                  : null,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text('Record transaction'.tr),
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact two-button pill in the header to switch between Income («درآمد»)
/// and Expense («هزینه»).
class DirectionToggle extends StatelessWidget {
  const DirectionToggle({
    super.key,
    required this.isIncome,
    required this.onSelect,
  });

  final bool isIncome;
  final ValueChanged<bool> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: scheme.onSurface.withValues(alpha: 0.09),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _pill(
            context: context,
            label: 'Income'.tr,
            selected: isIncome,
            color: AppTheme.revenue,
            onTap: () => onSelect(true),
          ),
          const SizedBox(width: 2),
          _pill(
            context: context,
            label: 'Expense'.tr,
            selected: !isIncome,
            color: AppTheme.expense,
            onTap: () => onSelect(false),
          ),
        ],
      ),
    );
  }

  Widget _pill({
    required BuildContext context,
    required String label,
    required bool selected,
    required Color color,
    required VoidCallback onTap,
  }) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.adaptive(context, Motion.expand),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.55)
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
            color: selected ? color : onSurface.withValues(alpha: 0.60),
          ),
        ),
      ),
    );
  }
}

/// Magnetic segmented bar for switching between Business (`کسب‌وکار`) and
/// Personal (`شخصی`) scopes with a continuous sliding pill.
class ScopeMagneticBar extends StatelessWidget {
  const ScopeMagneticBar({
    super.key,
    required this.personalProgress,
    required this.onSelectScope,
  });

  final double personalProgress;
  final ValueChanged<TxnScope> onSelectScope;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = personalProgress.clamp(0.0, 1.0);
    // Personal (`شخصی`) is first (-1.0, start side) and Business (`کسب‌وکار`)
    // is second (+1.0, end side).
    final alignX = 1.0 - 2.0 * p;

    return Container(
      key: const ValueKey('txn_scope_switcher'),
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
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
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.42),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
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
                child: _ScopeChip(
                  label: 'Personal'.tr,
                  icon: Icons.person_outline_rounded,
                  selected: p >= 0.5,
                  onTap: () => onSelectScope(TxnScope.personal),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _ScopeChip(
                  label: 'Business'.tr,
                  icon: Icons.business_center_outlined,
                  selected: p < 0.5,
                  onTap: () => onSelectScope(TxnScope.business),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Renders the «به حساب» (for expenses) / «از حساب» (for incomes) button,
/// an inline search bar for directly searching categories & subcategories,
/// and the user's pinned subcategory shortcuts (`میان‌برها`).
class AccountSelectorSection extends StatefulWidget {
  const AccountSelectorSection({
    super.key,
    required this.repo,
    required this.categoryKind,
    required this.scope,
    required this.selectedCategoryId,
    required this.shortcuts,
    required this.onSelectCategory,
  });

  final AppRepository repo;
  final TxnKind categoryKind;
  final TxnScope scope;
  final String? selectedCategoryId;
  final List<Category> shortcuts;
  final ValueChanged<Category> onSelectCategory;

  @override
  State<AccountSelectorSection> createState() => _AccountSelectorSectionState();
}

class _AccountSelectorSectionState extends State<AccountSelectorSection> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _openSheet(BuildContext context) async {
    final picked = await showLedgerSheet<Category>(
      context,
      builder: (_) => AccountCategorySheet(
        kind: widget.categoryKind,
        scope: widget.scope,
        selectedCategoryId: widget.selectedCategoryId,
      ),
    );
    if (!context.mounted || picked == null) return;
    Haptics.selection();
    widget.onSelectCategory(picked);
  }

  List<Category> _matchingCategories(String rawQuery) {
    final q = Fmt.normalizeDigits(rawQuery.trim().toLowerCase());
    if (q.isEmpty) return const <Category>[];
    final all = widget.repo.pickOrderCategories(
      widget.categoryKind,
      scope: widget.scope,
    );
    final byId = {for (final c in all) c.id: c};
    return all.where((c) {
      final ownFa = Fmt.normalizeDigits(c.name.tr.toLowerCase());
      final ownEn = Fmt.normalizeDigits(c.name.toLowerCase());
      if (ownFa.contains(q) || ownEn.contains(q)) return true;
      final parent = c.parentId == null ? null : byId[c.parentId];
      if (parent != null) {
        final parentFa = Fmt.normalizeDigits(parent.name.tr.toLowerCase());
        final parentEn = Fmt.normalizeDigits(parent.name.toLowerCase());
        if (parentFa.contains(q) || parentEn.contains(q)) return true;
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isExpense = widget.categoryKind == TxnKind.expense;
    final buttonLabel = (isExpense ? 'To account' : 'From account').tr;
    final accent = isExpense ? AppTheme.expense : AppTheme.revenue;

    final selectedCat = widget.repo.categoryById(widget.selectedCategoryId);
    final parentCat = selectedCat?.parentId == null
        ? null
        : widget.repo.categoryById(selectedCat!.parentId);
    final selectedText = selectedCat == null
        ? 'Select category'.tr
        : (parentCat == null
              ? selectedCat.name.tr
              : '${parentCat.name.tr} › ${selectedCat.name.tr}');

    final query = _searchCtrl.text.trim();
    final isSearching = query.isNotEmpty;
    final matches = isSearching ? _matchingCategories(query) : const <Category>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Main «به حساب» / «از حساب» button
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openSheet(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: accent.withValues(alpha: 0.28),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isExpense
                            ? Icons.account_balance_wallet_outlined
                            : Icons.savings_outlined,
                        size: 15,
                        color: accent,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        buttonLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    selectedText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface.withValues(alpha: 0.9),
                    ),
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),

        // Inline Category & Subcategory Search Bar
        const SizedBox(height: 8),
        TextField(
          key: ValueKey(
            'inline_category_search_${widget.scope.name}_${widget.categoryKind.name}',
          ),
          controller: _searchCtrl,
          focusNode: _searchFocus,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search category or subcategory...'.tr,
            hintStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: scheme.onSurface.withValues(alpha: 0.50),
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 17,
              color: accent.withValues(alpha: 0.85),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 34,
              minHeight: 34,
            ),
            suffixIcon: !isSearching
                ? null
                : IconButton(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 30,
                      minHeight: 30,
                    ),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() {});
                    },
                  ),
            filled: true,
            fillColor: scheme.onSurface.withValues(alpha: 0.035),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: scheme.onSurface.withValues(alpha: 0.12),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: scheme.onSurface.withValues(alpha: 0.12),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: accent.withValues(alpha: 0.6),
                width: 1.3,
              ),
            ),
          ),
        ),

        // Inline search results OR pinned subcategory/category shortcuts row
        const SizedBox(height: 8),
        if (isSearching)
          matches.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    'No matching category'.tr,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                )
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final c in matches.take(8))
                      _ShortcutCategoryChip(
                        category: c,
                        parentName: c.parentId == null
                            ? null
                            : widget.repo.categoryById(c.parentId)?.name.tr,
                        showParentInLabel: true,
                        selected: c.id == widget.selectedCategoryId,
                        accent: accent,
                        onTap: () {
                          Haptics.selection();
                          widget.onSelectCategory(c);
                          _searchCtrl.clear();
                          _searchFocus.unfocus();
                          setState(() {});
                        },
                      ),
                  ],
                )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final sc in widget.shortcuts)
                _ShortcutCategoryChip(
                  category: sc,
                  parentName: sc.parentId == null
                      ? null
                      : widget.repo.categoryById(sc.parentId)?.name.tr,
                  selected: sc.id == widget.selectedCategoryId,
                  accent: accent,
                  onTap: () {
                    Haptics.selection();
                    widget.onSelectCategory(sc);
                  },
                ),
              InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => _openSheet(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: accent.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.push_pin_outlined,
                        size: 13,
                        color: accent,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        widget.shortcuts.isEmpty
                            ? 'Choose shortcuts'.tr
                            : '+ Shortcut'.tr,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// Pinned shortcut chip for a subcategory or category on the main sheet,
/// color-coded by transaction direction ([accent]).
class _ShortcutCategoryChip extends StatelessWidget {
  const _ShortcutCategoryChip({
    required this.category,
    required this.parentName,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.showParentInLabel = false,
  });

  final Category category;
  final String? parentName;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  final bool showParentInLabel;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final fullLabel = parentName == null
        ? category.name.tr
        : '$parentName › ${category.name.tr}';
    final displayLabel = showParentInLabel ? fullLabel : category.name.tr;
    return Tooltip(
      message: fullLabel,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.adaptive(context, Motion.expand),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5.5),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.14)
                : onSurface.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.65)
                  : onSurface.withValues(alpha: 0.14),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_rounded : Icons.bolt_rounded,
                size: 13.5,
                color: selected
                    ? accent
                    : onSurface.withValues(alpha: 0.55),
              ),
              const SizedBox(width: 4),
              Text(
                displayLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: selected
                      ? accent
                      : onSurface.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Selector button for picking a Contact («مخاطب») in Business scope, styled
/// like the Category («به حساب» / «از حساب») selector button.
///
/// Tapping opens [ContactPickerSheet] where the user can search contacts,
/// pick one, clear the selection, or add a new contact.
class ContactSelectorSection extends StatelessWidget {
  const ContactSelectorSection({
    super.key,
    required this.repo,
    required this.selectedCustomer,
    required this.onSelectCustomer,
  });

  final AppRepository repo;
  final Customer? selectedCustomer;
  final ValueChanged<Customer?> onSelectCustomer;

  Future<void> _openSheet(BuildContext context) async {
    final res = await showLedgerSheet<_ContactPickResult>(
      context,
      builder: (_) => ContactPickerSheet(selectedCustomer: selectedCustomer),
    );
    if (!context.mounted || res == null) return;
    Haptics.selection();
    onSelectCustomer(res.customer);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    final hasContact = selectedCustomer != null;
    final labelText = hasContact
        ? selectedCustomer!.name
        : 'Contact (optional)'.tr;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: const ValueKey('contact_selector_button'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openSheet(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: hasContact ? 0.08 : 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: accent.withValues(alpha: hasContact ? 0.35 : 0.22),
                width: 1.2,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_outline_rounded,
                        size: 15,
                        color: accent,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        'Contact'.tr,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    labelText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: hasContact
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: scheme.onSurface.withValues(
                        alpha: hasContact ? 0.92 : 0.62,
                      ),
                    ),
                  ),
                ),
                if (hasContact)
                  InkWell(
                    key: const ValueKey('clear_contact_button'),
                    borderRadius: BorderRadius.circular(99),
                    onTap: () {
                      Haptics.selection();
                      onSelectCustomer(null);
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.close_rounded,
                        size: 17,
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 20,
                  color: scheme.onSurface.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
        if (hasContact)
          ContactBalanceCard(
            customer: selectedCustomer!,
            balance: repo.balanceOf(selectedCustomer!),
          ),
      ],
    );
  }
}

class _ContactPickResult {
  const _ContactPickResult(this.customer);
  final Customer? customer;
}

/// Bottom sheet opened by [ContactSelectorSection] for searching and selecting
/// a business contact (or creating a new contact on the spot).
class ContactPickerSheet extends StatefulWidget {
  const ContactPickerSheet({super.key, this.selectedCustomer});

  final Customer? selectedCustomer;

  @override
  State<ContactPickerSheet> createState() => _ContactPickerSheetState();
}

class _ContactPickerSheetState extends State<ContactPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _createNewContact() async {
    final created = await Navigator.push<Customer>(
      context,
      MaterialPageRoute(builder: (_) => const ContactEditPage()),
    );
    if (!mounted || created == null) return;
    Navigator.pop(context, _ContactPickResult(created));
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    final balances = repo.balancesMap();

    final q = Fmt.normalizeDigits(_searchCtrl.text.trim().toLowerCase());
    final all = repo.activeCustomers;
    final filtered = q.isEmpty
        ? all
        : all.where((c) {
            final nameMatch = Fmt.normalizeDigits(
              c.name.toLowerCase(),
            ).contains(q);
            final phoneMatch = Fmt.normalizeDigits(
              c.phone.toLowerCase(),
            ).contains(q);
            final tgMatch = Fmt.normalizeDigits(
              c.telegram.toLowerCase(),
            ).contains(q);
            return nameMatch || phoneMatch || tgMatch;
          }).toList();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.78,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.sheet),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHandle(),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.people_alt_outlined,
                  size: 18,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Select contact'.tr,
                      style: const TextStyle(
                        fontSize: FontSizes.title,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Choose a contact or add a new one'.tr,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _createNewContact,
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
                label: Text('New contact'.tr),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SearchField(
            controller: _searchCtrl,
            hint: 'Customer name...'.tr,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          if (widget.selectedCustomer != null && q.isEmpty) ...[
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => Navigator.pop(
                context,
                const _ContactPickResult(null),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: scheme.onSurface.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: scheme.onSurface.withValues(alpha: 0.10),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.person_off_outlined,
                      size: 17,
                      color: scheme.onSurface.withValues(alpha: 0.65),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Without contact'.tr,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Flexible(
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No customers yet'.tr,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final c = filtered[index];
                      final selected = widget.selectedCustomer?.id == c.id;
                      final bal = balances[c.id] ?? 0;
                      final isDebtor = bal > 0.5;
                      final isCreditor = bal < -0.5;
                      final balColor = isDebtor
                          ? AppTheme.expense
                          : (isCreditor
                                ? AppTheme.revenue
                                : scheme.onSurface.withValues(alpha: 0.5));

                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => Navigator.pop(
                          context,
                          _ContactPickResult(c),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: selected
                                ? accent.withValues(alpha: 0.10)
                                : scheme.onSurface.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: selected
                                  ? accent.withValues(alpha: 0.50)
                                  : scheme.onSurface.withValues(alpha: 0.10),
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 16,
                                backgroundColor: accent.withValues(alpha: 0.14),
                                child: Text(
                                  c.initial,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: accent,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: selected
                                            ? FontWeight.w800
                                            : FontWeight.w600,
                                      ),
                                    ),
                                    if (c.phone.isNotEmpty)
                                      Text(
                                        c.phone,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: scheme.onSurface.withValues(
                                            alpha: 0.58,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (isDebtor || isCreditor) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: balColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${(isDebtor ? 'Debtor' : 'Creditor').tr}: ${Money.text(bal.abs(), compact: true)}',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: balColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              if (selected)
                                Icon(
                                  Icons.check_circle_rounded,
                                  size: 19,
                                  color: accent,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// Hierarchical sheet opened by the «به حساب» / «از حساب» button.
///
/// Shows top-level categories; tapping any category expands its subcategories
/// and allows selecting a subcategory, adding a new subcategory, or pinning
/// subcategories as 1-tap shortcuts on the main transaction sheet.
class AccountCategorySheet extends StatefulWidget {
  const AccountCategorySheet({
    super.key,
    required this.kind,
    required this.scope,
    required this.selectedCategoryId,
  });

  final TxnKind kind;
  final TxnScope scope;
  final String? selectedCategoryId;

  @override
  State<AccountCategorySheet> createState() => _AccountCategorySheetState();
}

class _AccountCategorySheetState extends State<AccountCategorySheet> {
  String? _expandedParentId;
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_expandedParentId != null) return;
    final repo = context.read<AppRepository>();
    final selected = repo.categoryById(widget.selectedCategoryId);
    if (selected != null) {
      _expandedParentId = selected.parentId ?? selected.id;
    }
  }

  Future<void> _addSubcategoryDialog(
    AppRepository repo,
    Category parent,
  ) async {
    final ctrl = TextEditingController();
    var pinAsShortcut = true;
    final created = await showDialog<Category>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(
            'New subcategory under "{name}"'.trArgs({'name': parent.name.tr}),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  hintText: 'e.g. Fuel'.tr,
                ),
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                value: pinAsShortcut,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'Pin as shortcut on main sheet'.tr,
                  style: const TextStyle(fontSize: 13),
                ),
                onChanged: (v) =>
                    setDialog(() => pinAsShortcut = v ?? true),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel'.tr),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: ctrl,
              builder: (context, value, _) => FilledButton(
                onPressed: value.text.trim().isEmpty
                    ? null
                    : () async {
                        final sub = await repo.addCategory(
                          value.text.trim(),
                          widget.kind,
                          scope: widget.scope,
                          parentId: parent.id,
                          isShortcut: pinAsShortcut,
                        );
                        if (ctx.mounted) Navigator.pop(ctx, sub);
                      },
                child: Text('Save'.tr),
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted || created == null) return;
    Navigator.pop(context, created);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final scheme = Theme.of(context).colorScheme;
    final isExpense = widget.kind == TxnKind.expense;
    final title = (isExpense ? 'To account' : 'From account').tr;
    final accent = isExpense ? AppTheme.expense : AppTheme.revenue;

    final all = repo.pickOrderCategories(widget.kind, scope: widget.scope);
    final byId = {for (final c in all) c.id: c};
    final parents = <Category>[];
    final childrenOf = <String, List<Category>>{};
    for (final c in all) {
      final parent = c.parentId == null ? null : byId[c.parentId];
      if (parent == null) {
        parents.add(c);
      } else {
        (childrenOf[parent.id] ??= <Category>[]).add(c);
      }
    }

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.78,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.sheet),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHandle(),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isExpense
                      ? Icons.account_balance_wallet_outlined
                      : Icons.savings_outlined,
                  size: 18,
                  color: accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: FontSizes.title,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Tap a category to view its subcategories or pin shortcuts'
                          .tr,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CategoriesPage()),
                ),
                icon: const Icon(Icons.tune_rounded, size: 15),
                label: Text('Manage'.tr),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SearchField(
            controller: _searchCtrl,
            hint: 'Category name...'.tr,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: _searchCtrl.text.trim().isNotEmpty
                ? Builder(
                    builder: (context) {
                      final q = _searchCtrl.text.trim().toLowerCase();
                      final matches = all.where((c) {
                        return c.name.tr.toLowerCase().contains(q) ||
                            c.name.toLowerCase().contains(q);
                      }).toList();
                      return Material(
                        type: MaterialType.transparency,
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: matches.length,
                          itemBuilder: (context, index) {
                            final c = matches[index];
                            final selected = c.id == widget.selectedCategoryId;
                            return ListTile(
                              dense: true,
                              selected: selected,
                              leading: Icon(
                                c.parentId == null
                                    ? Icons.folder_outlined
                                    : Icons.subdirectory_arrow_left_rounded,
                                size: 18,
                                color: selected ? accent : null,
                              ),
                              title: Text(c.name.tr),
                              onTap: () => Navigator.pop(context, c),
                            );
                          },
                        ),
                      );
                    },
                  )
                : ListView.separated(
              shrinkWrap: true,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: parents.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final parent = parents[index];
                final subs = childrenOf[parent.id] ?? const <Category>[];
                final expanded = _expandedParentId == parent.id;
                final parentSelected =
                    widget.selectedCategoryId == parent.id ||
                    subs.any((s) => s.id == widget.selectedCategoryId);

                return AnimatedContainer(
                  duration: Motion.adaptive(context, Motion.expand),
                  curve: Curves.easeOutCubic,
                  decoration: BoxDecoration(
                    color: expanded
                        ? accent.withValues(alpha: 0.05)
                        : scheme.onSurface.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: parentSelected
                          ? accent.withValues(alpha: 0.45)
                          : scheme.onSurface.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          Haptics.selection();
                          setState(() {
                            _expandedParentId = expanded ? null : parent.id;
                          });
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                expanded
                                    ? Icons.folder_open_rounded
                                    : Icons.folder_outlined,
                                size: 18,
                                color: parentSelected
                                    ? accent
                                    : scheme.onSurface.withValues(alpha: 0.65),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  parent.name.tr,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: parentSelected
                                        ? FontWeight.w800
                                        : FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (subs.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: accent.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    '${subs.length}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: accent,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 6),
                              Icon(
                                expanded
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.keyboard_arrow_down_rounded,
                                size: 20,
                                color: scheme.onSurface.withValues(
                                  alpha: 0.55,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (expanded)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Divider(height: 8),
                              // Subcategory items
                              for (final sub in subs)
                                _SubcategoryTile(
                                  category: sub,
                                  accent: accent,
                                  selected:
                                      sub.id == widget.selectedCategoryId,
                                  onSelect: () => Navigator.pop(context, sub),
                                  onToggleShortcut: () {
                                    Haptics.selection();
                                    repo.toggleCategoryShortcut(sub.id);
                                  },
                                ),
                              // Select the parent category directly
                              _SubcategoryTile(
                                category: parent,
                                accent: accent,
                                labelOverride:
                                    'General ({name})'.trArgs({
                                      'name': parent.name.tr,
                                    }),
                                selected:
                                    parent.id == widget.selectedCategoryId,
                                onSelect: () => Navigator.pop(context, parent),
                                onToggleShortcut: () {
                                  Haptics.selection();
                                  repo.toggleCategoryShortcut(parent.id);
                                },
                              ),
                              const SizedBox(height: 4),
                              Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: TextButton.icon(
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    foregroundColor: accent,
                                  ),
                                  onPressed: () => _addSubcategoryDialog(
                                    repo,
                                    parent,
                                  ),
                                  icon: const Icon(
                                    Icons.add_rounded,
                                    size: 16,
                                  ),
                                  label: Text('Add subcategory'.tr),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SubcategoryTile extends StatelessWidget {
  const _SubcategoryTile({
    required this.category,
    required this.accent,
    required this.selected,
    required this.onSelect,
    required this.onToggleShortcut,
    this.labelOverride,
  });

  final Category category;
  final Color accent;
  final String? labelOverride;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onToggleShortcut;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onSelect,
      child: Container(
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.14)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.55)
                : onSurface.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.subdirectory_arrow_left_rounded,
              size: 16,
              color: selected
                  ? accent
                  : onSurface.withValues(alpha: 0.5),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                labelOverride ?? category.name.tr,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? accent : onSurface,
                ),
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: onToggleShortcut,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 4,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      category.isShortcut
                          ? Icons.push_pin_rounded
                          : Icons.push_pin_outlined,
                      size: 15,
                      color: category.isShortcut
                          ? accent
                          : onSurface.withValues(alpha: 0.4),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'Shortcut'.tr,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: category.isShortcut
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: category.isShortcut
                            ? accent
                            : onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tab label inside the magnetic segmented bar.
class _ScopeChip extends StatelessWidget {
  const _ScopeChip({
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
      borderRadius: BorderRadius.circular(9),
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
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? scheme.primary
                    : onSurface.withValues(alpha: 0.72),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
