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
import '../personal_page.dart';
import '../settings_page.dart';
import '../theme.dart';
import '../widgets/quick_buttons.dart';
import '../widgets/widgets.dart';
import 'contact_edit_page.dart';

/// Compact, one-screen sheet for reviewing and approving a bank SMS.
///
/// Designed around the app's shared visual tokens ([Insets], [FontSizes],
/// [Radii], [AppTheme]) so the entire review flow — scope, amount, category,
/// contact, and action buttons — fits comfortably on a single screen without
/// scrolling or oversized cards.
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
  TxnKind _kind = TxnKind.income;
  TxnScope _scope = TxnScope.business;
  String? _categoryId;
  bool _presetDone = false;

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
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: groupedNumber(
        widget.sms.amount,
        decimals: Money.decimals(widget.sms.currency),
      ),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  TxnKind _suggestedKind(AppRepository repo, TxnScope scope) {
    if (widget.sms.direction == SmsDirection.deposit) {
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
      return [
        widget.sms.direction == SmsDirection.deposit
            ? TxnKind.income
            : TxnKind.expense,
      ];
    }
    if (widget.sms.direction == SmsDirection.deposit) {
      return [
        TxnKind.income,
        if (_customer != null && repo.balanceOf(_customer!) > 0.5)
          TxnKind.receive,
      ];
    }
    if (widget.sms.direction == SmsDirection.withdraw) {
      return [
        TxnKind.expense,
        if (_customer != null) TxnKind.refund,
        if (_customer != null && repo.balanceOf(_customer!) < -0.5)
          TxnKind.payablePayment,
      ];
    }
    return [TxnKind.income, TxnKind.expense];
  }

  void _changeScope(AppRepository repo, TxnScope scope) {
    if (_scope == scope) return;
    setState(() {
      _scope = scope;
      _customer = scope == TxnScope.business ? widget.initialCustomer : null;
      _kind = _suggestedKind(repo, scope);
      _categoryId = _suggestedCategoryId(repo, scope);
    });
  }

  Future<void> _openQuickEdit(TxnScope scope, [QuickExpense? q]) async {
    await showLedgerSheet<void>(
      context,
      builder: (_) => QuickEditSheet(
        initial: q,
        presetScope: scope,
        presetKind: widget.sms.direction == SmsDirection.deposit
            ? TxnKind.income
            : TxnKind.expense,
      ),
    );
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
    final categories = categoryKind == null
        ? const <Category>[]
        : repo.pickOrderCategories(categoryKind, scope: scope);
    final availableKinds = _availableKinds(repo, scope);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(Radii.sheet),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetHandle(),
            const SizedBox(height: 10),

            // -------- Header --------
            _header(sms),
            const SizedBox(height: 12),

            // -------- Scope toggle --------
            _scopeRow(repo, scope),
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
            const SizedBox(height: 10),

            // -------- Amount (single compact field, no duplicate display) ----
            AmountField(
              controller: _amount,
              label: 'Amount',
              currency: sms.currency,
              livePreview: false,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 12),

            // -------- Quick buttons (hidden when empty) --------
            QuickButtonsRow(
              scopeFilter: scope,
              incomeFilter: sms.direction == SmsDirection.deposit,
              hideWhenEmpty: true,
              selectedCategoryId: _categoryId,
              onTap: (q) => setState(() {
                if (availableKinds.contains(q.kind)) _kind = q.kind;
                if (q.categoryId != null) _categoryId = q.categoryId;
              }),
              onLongPress: (q) => _openQuickEdit(scope, q),
            ),

            // -------- Compact Category Chips --------
            if (categoryKind != null) ...[
              const SizedBox(height: 10),
              _categorySection(categories),
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

            const SizedBox(height: 14),

            // -------- Action buttons --------
            _actionBar(repo, sms),
          ],
        ),
      ),
    );
  }

  Widget _header(ParsedSms sms) {
    final scheme = Theme.of(context).colorScheme;
    final isDeposit = sms.direction == SmsDirection.deposit;
    final accent = isDeposit ? AppTheme.revenue : AppTheme.expense;
    final bank = sms.bankName?.tr ??
        (sms.message.address.isNotEmpty
            ? sms.message.address
            : 'Pasted message'.tr);

    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            isDeposit
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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            (isDeposit ? 'Income' : 'Expense').tr,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
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

  Widget _categorySection(List<Category> categories) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: SectionCaption('Category')),
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CategoriesPage()),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.tune_rounded,
                      size: 13,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'Manage'.tr,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (categories.isEmpty)
          OutlinedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CategoriesPage()),
            ),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: Text('Manage'.tr),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in categories)
                _CategoryChip(
                  category: c,
                  selected: c.id == _categoryId,
                  onTap: () {
                    Haptics.selection();
                    setState(() => _categoryId = c.id);
                  },
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

/// Compact pill for selecting a category in one tap.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: AnimatedContainer(
        duration: Motion.adaptive(context, Motion.expand),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.14)
              : onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: 0.65)
                : onSurface.withValues(alpha: 0.13),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              Icon(
                Icons.check_rounded,
                size: 14,
                color: scheme.primary,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              category.name.tr,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected
                    ? scheme.primary
                    : onSurface.withValues(alpha: 0.82),
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
      onTap: () {
        Haptics.selection();
        onTap();
      },
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
