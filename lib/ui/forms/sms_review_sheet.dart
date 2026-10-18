import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format_utils.dart';
import '../../core/haptics.dart';
import '../../core/localization.dart';
import '../../core/money.dart';
import '../../core/sms/sms_models.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../motion_kit.dart';
import 'contact_edit_page.dart';
import 'widgets/quick_buttons.dart';
import 'widgets/widgets.dart';
import '../settings_page.dart';

/// ========================================================================
/// Redesigned SMS review sheet.
///
/// Card-based layout with distinct colour per section, a prominent amount
/// display at the top, and a category grid that makes one-tap selection
/// obvious. The old form-style layout is replaced with this because users
/// reported that tapping a quick button or category gave no feedback and
/// the long form felt slow for the one decision they actually had to make.
/// ========================================================================
class SmsReviewSheet extends StatefulWidget {
  const SmsReviewSheet({super.key, required this.sms, this.initialCustomer});

  final ParsedSms sms;
  final Customer? initialCustomer;

  @override
  State<SmsReviewSheet> createState() => _SmsReviewSheetState();
}

class _SmsReviewSheetState extends State<SmsReviewSheet> {
  late TextEditingController _amount;
  final TextEditingController _note = TextEditingController();
  Customer? _customer;
  TxnKind _kind = TxnKind.income;
  TxnScope _scope = TxnScope.business;
  String? _categoryId;
  bool _presetDone = false;

  // Card accent colours — light pastel backgrounds with a matching darker
  // border/icon. Kept `const` so they do not rebuild on every setState.
  static const _amountAccent = Color(0xFF1976D2);
  static const _amountBg = Color(0xFFE3F2FD);
  static const _categoryAccent = Color(0xFF2E7D32);
  static const _categoryBg = Color(0xFFE8F5E9);
  static const _customerAccent = Color(0xFF6A1B9A);
  static const _customerBg = Color(0xFFF3E5F5);
  static const _noteAccent = Color(0xFFF57F17);
  static const _noteBg = Color(0xFFFFF8E1);

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
    _note.dispose();
    super.dispose();
  }

  // ---- state helpers (kept from the old sheet) ---------------------------

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

  Future<void> _openContactSheet() async {
    final repo = context.read<AppRepository>();
    final res = await showPickSheet<Customer>(
      context,
      title: 'Select contact'.tr,
      items: repo.activeCustomers,
      current: _customer,
      labelOf: (c) => c.name,
      subOf: (c) => c.phone,
      clearable: true,
      searchHint: 'Customer name...'.tr,
    );
    if (res == null) return;
    if (res.cleared) {
      setState(() => _customer = null);
    } else if (res.value != null) {
      setState(() => _customer = res.value);
    }
  }

  Future<void> _newContact() async {
    final created = await Navigator.push<Customer>(
      context,
      MaterialPageRoute(builder: (_) => const ContactEditPage()),
    );
    if (!mounted) return;
    if (created != null) setState(() => _customer = created);
  }

  // ---- build -------------------------------------------------------------

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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHandle(),
            const SizedBox(height: 14),

            // -------- Header --------
            _header(sms),
            const SizedBox(height: 16),

            // -------- Amount card --------
            _amountCard(sms),
            const SizedBox(height: 12),

            // -------- Scope --------
            _scopeRow(repo, scope),
            const SizedBox(height: 12),

            // -------- Category grid --------
            if (categories.isNotEmpty)
              _categoryGrid(categories)
            else
              _emptyCategoryCard(),
            const SizedBox(height: 12),

            // -------- Quick buttons (long-press to edit) --------
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
            const SizedBox(height: 12),

            // -------- Customer card --------
            if (scope == TxnScope.business) ...[
              _customerCard(repo),
              const SizedBox(height: 12),
            ],

            // -------- Notes --------
            _noteCard(),
            const SizedBox(height: 18),

            // -------- Submit --------
            _submitButton(repo, sms),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  // ---- section widgets ---------------------------------------------------

  Widget _header(ParsedSms sms) {
    final bank = sms.bankName?.tr ??
        (sms.message.address.isNotEmpty
            ? sms.message.address
            : 'Pasted message'.tr);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer
                .withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.sms_rounded,
              size: 22, color: Theme.of(context).colorScheme.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Record this SMS transaction'.tr,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                bank,
                style: TextStyle(
                  fontSize: 11.5,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _amountCard(ParsedSms sms) {
    final amountText =
        Money.text(widget.sms.amount, currency: sms.currency);
    return _SectionCard(
      accentColor: _amountAccent,
      backgroundColor: _amountBg,
      icon: Icons.account_balance_wallet_rounded,
      title: 'Transaction amount'.tr,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            amountText,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: _amountAccent,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          TextFormField(
            controller: _amount,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            textDirection: TextDirection.ltr,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: 'Edit amount'.tr,
              prefixIcon:
                  const Icon(Icons.edit_rounded, size: 18),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                    color: _amountAccent.withValues(alpha: 0.35)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    BorderSide(color: _amountAccent, width: 2),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scopeRow(AppRepository repo, TxnScope scope) {
    return Row(
      children: [
        Expanded(
          child: _ScopeChip(
            label: 'Business'.tr,
            icon: Icons.business_center_outlined,
            selected: scope == TxnScope.business,
            onTap: () => _changeScope(repo, TxnScope.business),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ScopeChip(
            label: 'Personal'.tr,
            icon: Icons.person_outline_rounded,
            selected: scope == TxnScope.personal,
            onTap: () => _changeScope(repo, TxnScope.personal),
          ),
        ),
      ],
    );
  }

  Widget _categoryGrid(List<Category> categories) {
    return _SectionCard(
      accentColor: _categoryAccent,
      backgroundColor: _categoryBg,
      icon: Icons.grid_view_rounded,
      title: 'Category'.tr,
      subtitle: 'Please specify the type of transaction'.tr,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 4 columns on normal widths, 3 on narrow.
          final crossCount = constraints.maxWidth > 340 ? 4 : 3;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossCount,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1.1,
            ),
            itemCount: categories.length,
            itemBuilder: (context, i) {
              final c = categories[i];
              final selected = c.id == _categoryId;
              return _CategoryTile(
                category: c,
                selected: selected,
                onTap: () {
                  Haptics.selection();
                  setState(() => _categoryId = c.id);
                },
              );
            },
          );
        },
      ),
    );
  }

  Widget _emptyCategoryCard() {
    return _SectionCard(
      accentColor: _categoryAccent,
      backgroundColor: _categoryBg,
      icon: Icons.category_outlined,
      title: 'Category'.tr,
      subtitle: 'No categories configured yet. Add one from Manage.'.tr,
      child: OutlinedButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CategoriesPage()),
        ),
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text('Manage'.tr),
      ),
    );
  }

  Widget _customerCard(AppRepository repo) {
    final customer = _customer;
    return _SectionCard(
      accentColor: _customerAccent,
      backgroundColor: _customerBg,
      icon: Icons.person_rounded,
      title: 'Contact'.tr,
      subtitle: customer == null ? 'Optional'.tr : null,
      child: customer == null
          ? Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openContactSheet,
                    icon: const Icon(Icons.person_search_rounded, size: 18),
                    label: Text('Select contact'.tr),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'New contact'.tr,
                  onPressed: _newContact,
                  icon: const Icon(Icons.person_add_rounded),
                ),
              ],
            )
          : Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _customerAccent.withValues(alpha: 0.18),
                  ),
                  child: Center(
                    child: Text(
                      customer.name.isNotEmpty
                          ? customer.name[0]
                          : '?',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _customerAccent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        customer.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (customer.phone.isNotEmpty)
                        Text(
                          customer.phone,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.55),
                          ),
                          direction: TextDirection.ltr,
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => setState(() => _customer = null),
                  child: Text('Change'.tr),
                ),
              ],
            ),
    );
  }

  Widget _noteCard() {
    return _SectionCard(
      accentColor: _noteAccent,
      backgroundColor: _noteBg,
      icon: Icons.notes_rounded,
      title: 'Notes (optional)'.tr,
      child: TextField(
        controller: _note,
        maxLines: 2,
        textAlignVertical: TextAlignVertical.top,
        decoration: InputDecoration(
          hintText: 'e.g. Monthly internet payment'.tr,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
                color: _noteAccent.withValues(alpha: 0.35)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _noteAccent, width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        ),
      ),
    );
  }

  Widget _submitButton(AppRepository repo, ParsedSms sms) {
    final value = parseAmount(_amount.text);
    final ready = value > 0;
    return SizedBox(
      height: 52,
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
                if (context.mounted) {
                  MoneyCelebration.recorded(context);
                  Navigator.pop(context, true);
                }
              }
            : null,
        style: FilledButton.styleFrom(
          backgroundColor: _amountAccent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
        ),
        icon: const Icon(Icons.check_rounded, size: 20),
        label: Text(
          'Confirm and record'.tr,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

// ========================================================================
// Private sub-widgets
// ========================================================================

/// A rounded section card with a tinted background, a leading icon, and a
/// title. Used by every card in the redesign so they stay visually
/// consistent even if we tweak the spacing later.
class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.accentColor,
    required this.backgroundColor,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.child,
  });

  final Color accentColor;
  final Color backgroundColor;
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.22),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: accentColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: accentColor,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11,
                          color: accentColor.withValues(alpha: 0.75),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// One cell in the category grid.
class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final Category category;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? _categoryAccent.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _categoryAccent : _categoryAccent
                .withValues(alpha: 0.25),
            width: selected ? 2 : 1,
          ),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.category_outlined,
                  size: 22,
                  color: selected ? _categoryAccent : _categoryAccent
                      .withValues(alpha: 0.75),
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: Text(
                    category.name.tr,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? _categoryAccent
                          : _categoryAccent.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ],
            ),
            if (selected)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: _categoryAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 10,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A small scope chip (Business / Personal) used inside the redesign.
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
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Haptics.selection();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? _categoryAccent.withValues(alpha: 0.15)
              : Theme.of(context).colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? _categoryAccent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18,
                color: selected ? _categoryAccent : null),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? _categoryAccent : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
