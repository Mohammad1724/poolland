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
/// - Smooth horizontal swipe between Business (`کسب‌وکار`) and Personal (`شخصی`).
/// - «به حساب» (Expense) / «از حساب» (Income) button that opens a hierarchical
///   category -> subcategory picker window.
/// - One-tap subcategory shortcuts (`میان‌بر`) pinned directly on the sheet,
///   color-coded to match Expense (red) or Income (green).
class SmsReviewSheet extends StatefulWidget {
  const SmsReviewSheet({super.key, required this.sms, this.initialCustomer});

  final ParsedSms sms;
  final Customer? initialCustomer;

  @override
  State<SmsReviewSheet> createState() => _SmsReviewSheetState();
}

class _SmsReviewSheetState extends State<SmsReviewSheet> {
  late TextEditingController _amount;
  Customer? _customer;
  late bool _isIncome;
  TxnKind _kind = TxnKind.income;
  TxnScope _scope = TxnScope.business;
  String? _categoryId;
  bool _presetDone = false;
  double _horizontalDragDx = 0;

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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_presetDone) return;
    _presetDone = true;
    final repo = context.read<AppRepository>();
    _scope = TxnScope.business;
    _customer = widget.initialCustomer;
    _kind = _suggestedKind(repo, _scope);
    _categoryId = _suggestedCategoryId(repo, _scope);
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
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
    final kind = _categoryKind(_kind);
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

  void _changeScope(AppRepository repo, TxnScope scope) {
    if (_scope == scope) {
      if (_horizontalDragDx != 0) setState(() => _horizontalDragDx = 0);
      return;
    }
    Haptics.selection();
    setState(() {
      _horizontalDragDx = 0;
      _scope = scope;
      _customer = scope == TxnScope.business ? widget.initialCustomer : null;
      _kind = _suggestedKind(repo, scope);
      _categoryId = _suggestedCategoryId(repo, scope);
    });
  }

  void _handleHorizontalSwipeUpdate(DragUpdateDetails details) {
    setState(() {
      _horizontalDragDx = (_horizontalDragDx + details.delta.dx).clamp(
        -90.0,
        90.0,
      );
    });
  }

  void _handleHorizontalSwipeEnd(
    AppRepository repo,
    DragEndDetails details,
  ) {
    final velocity = details.primaryVelocity ?? 0;
    final swipedEnough = _horizontalDragDx.abs() > 32 || velocity.abs() > 180;
    if (!swipedEnough) {
      if (_horizontalDragDx != 0) setState(() => _horizontalDragDx = 0);
      return;
    }
    final nextScope = _scope == TxnScope.business
        ? TxnScope.personal
        : TxnScope.business;
    _changeScope(repo, nextScope);
  }

  Future<void> _openAccountCategorySheet(
    AppRepository repo,
    TxnKind categoryKind,
    TxnScope scope,
  ) async {
    final picked = await showLedgerSheet<Category>(
      context,
      builder: (_) => _AccountCategorySheet(
        kind: categoryKind,
        scope: scope,
        selectedCategoryId: _categoryId,
      ),
    );
    if (!mounted || picked == null) return;
    Haptics.selection();
    setState(() => _categoryId = picked.id);
  }

  Widget _contactChip(AppRepository repo, Customer c) {
    final selected = _customer?.id == c.id;
    return PresetChip(
      icon: Icons.person_outline_rounded,
      label: c.name,
      selected: selected,
      onTap: () {
        Haptics.selection();
        setState(() {
          _customer = selected ? null : c;
          final available = _availableKinds(repo, _scope);
          if (!available.contains(_kind)) {
            _kind = _suggestedKind(repo, _scope);
            _categoryId = _suggestedCategoryId(repo, _scope);
          }
        });
      },
    );
  }

  Future<void> _openContactSheet() async {
    final repo = context.read<AppRepository>();
    final res = await showPickSheet<Customer>(
      context,
      title: 'Select contact',
      items: repo.activeCustomers,
      current: _customer,
      labelOf: (c) => c.name,
      subOf: (c) => c.phone,
      clearable: true,
      searchHint: 'Customer name...',
    );
    if (res == null) return;
    setState(() {
      if (res.cleared) {
        _customer = null;
      } else if (res.value != null) {
        _customer = res.value;
      }
      final available = _availableKinds(repo, _scope);
      if (!available.contains(_kind)) {
        _kind = _suggestedKind(repo, _scope);
        _categoryId = _suggestedCategoryId(repo, _scope);
      }
    });
  }

  Future<void> _newContact() async {
    final created = await Navigator.push<Customer>(
      context,
      MaterialPageRoute(builder: (_) => const ContactEditPage()),
    );
    if (!mounted || created == null) return;
    setState(() => _customer = created);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final sms = widget.sms;
    final scope = _scope;
    final categoryKind = _categoryKind(_kind);
    final shortcuts = categoryKind == null
        ? const <Category>[]
        : repo.shortcutCategories(categoryKind, scope: scope);
    final availableKinds = _availableKinds(repo, scope);

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
        onHorizontalDragStart: (_) => _horizontalDragDx = 0,
        onHorizontalDragUpdate: _handleHorizontalSwipeUpdate,
        onHorizontalDragCancel: () {
          if (_horizontalDragDx != 0) setState(() => _horizontalDragDx = 0);
        },
        onHorizontalDragEnd: (d) => _handleHorizontalSwipeEnd(repo, d),
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
              _scopeRow(repo, scope),
              const SizedBox(height: 10),

              // -------- Amount (single compact field) --------
              AmountField(
                controller: _amount,
                label: 'Amount',
                currency: sms.currency,
                livePreview: false,
                onChanged: () => setState(() {}),
              ),

              // -------- Smoothly resized & faded scope section --------
              AnimatedSize(
                duration: Motion.adaptive(
                  context,
                  const Duration(milliseconds: 200),
                ),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: AnimatedContainer(
                  duration: _horizontalDragDx == 0
                      ? const Duration(milliseconds: 180)
                      : Duration.zero,
                  curve: Curves.easeOutCubic,
                  transform: Matrix4.translationValues(
                    _horizontalDragDx * 0.18,
                    0,
                    0,
                  ),
                  child: Column(
                    key: ValueKey<String>('${scope.name}-$_isIncome'),
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (availableKinds.length > 1) ...[
                        const SizedBox(height: 8),
                        TxnKindStrip(
                          kinds: availableKinds,
                          selected: _kind,
                          onSelect: (k) => setState(() {
                            _kind = k;
                            _categoryId = _suggestedCategoryId(repo, scope);
                          }),
                        ),
                      ],

                      // -------- «به حساب» / «از حساب» + Shortcuts --------
                      if (categoryKind != null) ...[
                        const SizedBox(height: 12),
                        _accountSelectorSection(
                          repo: repo,
                          categoryKind: categoryKind,
                          scope: scope,
                          shortcuts: shortcuts,
                        ),
                      ],

                      // -------- Contact (Business scope only) --------
                      if (scope == TxnScope.business) ...[
                        const SizedBox(height: 12),
                        const SectionCaption('Contact (optional)'),
                        const SizedBox(height: 6),
                        ChipStrip(
                          chips: [
                            for (final c in repo.topCustomers(limit: 3))
                              _contactChip(repo, c),
                            PresetChip(
                              icon: Icons.person_search_outlined,
                              label: 'All contacts'.tr,
                              onTap: _openContactSheet,
                            ),
                            PresetChip(
                              icon: Icons.person_add_alt_1_rounded,
                              label: 'New contact'.tr,
                              onTap: _newContact,
                            ),
                          ],
                        ),
                        if (_customer != null)
                          ContactBalanceCard(
                            customer: _customer!,
                            balance: repo.balanceOf(_customer!),
                          ),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              // -------- Action buttons --------
              _actionBar(repo, sms),
            ],
          ),
        ),
      ),
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
        _DirectionToggle(
          isIncome: _isIncome,
          onSelect: (inc) => _changeDirection(repo, inc),
        ),
      ],
    );
  }

  Widget _scopeRow(AppRepository repo, TxnScope scope) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.onSurface.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _ScopeChip(
              label: 'Business'.tr,
              icon: Icons.business_center_outlined,
              selected: scope == TxnScope.business,
              onTap: () => _changeScope(repo, TxnScope.business),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _ScopeChip(
              label: 'Personal'.tr,
              icon: Icons.person_outline_rounded,
              selected: scope == TxnScope.personal,
              onTap: () => _changeScope(repo, TxnScope.personal),
            ),
          ),
        ],
      ),
    );
  }

  /// Renders the «به حساب» (for expenses) / «از حساب» (for incomes) button
  /// alongside the user's pinned subcategory shortcuts (`میان‌برها`).
  Widget _accountSelectorSection({
    required AppRepository repo,
    required TxnKind categoryKind,
    required TxnScope scope,
    required List<Category> shortcuts,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final isExpense = categoryKind == TxnKind.expense;
    final buttonLabel = (isExpense ? 'To account' : 'From account').tr;
    final accent = isExpense ? AppTheme.expense : AppTheme.revenue;

    final selectedCat = repo.categoryById(_categoryId);
    final parentCat = selectedCat?.parentId == null
        ? null
        : repo.categoryById(selectedCat!.parentId);
    final selectedText = selectedCat == null
        ? 'Select category'.tr
        : (parentCat == null
              ? selectedCat.name.tr
              : '${parentCat.name.tr} › ${selectedCat.name.tr}');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Main «به حساب» / «از حساب» button
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openAccountCategorySheet(repo, categoryKind, scope),
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

        // Pinned subcategory/category shortcuts row («میان‌برها»)
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final sc in shortcuts)
              _ShortcutCategoryChip(
                category: sc,
                parentName: sc.parentId == null
                    ? null
                    : repo.categoryById(sc.parentId)?.name.tr,
                selected: sc.id == _categoryId,
                accent: accent,
                onTap: () {
                  Haptics.selection();
                  setState(() => _categoryId = sc.id);
                },
              ),
            InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () => _openAccountCategorySheet(
                repo,
                categoryKind,
                scope,
              ),
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
                      shortcuts.isEmpty
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
class _DirectionToggle extends StatelessWidget {
  const _DirectionToggle({
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

/// Pinned shortcut chip for a subcategory or category on the main sheet,
/// color-coded by transaction direction ([accent]).
class _ShortcutCategoryChip extends StatelessWidget {
  const _ShortcutCategoryChip({
    required this.category,
    required this.parentName,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final Category category;
  final String? parentName;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Tooltip(
      message: parentName == null
          ? category.name.tr
          : '$parentName › ${category.name.tr}',
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
                category.name.tr,
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

/// Hierarchical sheet opened by the «به حساب» / «از حساب» button.
///
/// Shows top-level categories; tapping any category expands its subcategories
/// and allows selecting a subcategory, adding a new subcategory, or pinning
/// subcategories as 1-tap shortcuts on the main transaction sheet.
class _AccountCategorySheet extends StatefulWidget {
  const _AccountCategorySheet({
    required this.kind,
    required this.scope,
    required this.selectedCategoryId,
  });

  final TxnKind kind;
  final TxnScope scope;
  final String? selectedCategoryId;

  @override
  State<_AccountCategorySheet> createState() => _AccountCategorySheetState();
}

class _AccountCategorySheetState extends State<_AccountCategorySheet> {
  String? _expandedParentId;

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
                autofocus: true,
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
          Flexible(
            child: ListView.separated(
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

/// Sleek segmented pill for switching between Business and Personal scope.
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
      child: AnimatedContainer(
        duration: Motion.adaptive(context, Motion.expand),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? Theme.of(context).cardColor : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: 0.40)
                : Colors.transparent,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
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
