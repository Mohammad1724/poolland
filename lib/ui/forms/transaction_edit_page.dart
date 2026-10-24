import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/format_utils.dart';
import '../../core/haptics.dart';
import '../../core/jalali_utils.dart';
import '../../core/localization.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../design.dart';
import '../motion_kit.dart';
import '../widgets/date_picker.dart';
import '../widgets/widgets.dart';
import 'sms_review_sheet.dart';

/// Record or edit a transaction (income, expense, receipt, refund, or payment).
///
/// Unified with the SMS transaction recording sheet:
/// - Interactive `درآمد` (`Income`) / `هزینه` (`Expense`) direction toggle in
///   Personal scope, or the full business kind strip in Business scope.
/// - 1:1 finger-tracking horizontal drag + magnetic snap between `شخصی`
///   (`Personal`, first) and `کسب‌وکار` (`Business`, second).
/// - «به حساب» (Expense) / «از حساب» (Income) button opening the hierarchical
///   Category -> Subcategory picker window (`AccountCategorySheet`), plus
///   an inline search bar and color-coded 1-tap pinned subcategory shortcuts
///   (`میان‌بر`).
/// - Contact («مخاطب») selector button in Business scope that opens
///   `ContactPickerSheet`.
class TransactionEditPage extends StatefulWidget {
  const TransactionEditPage({
    super.key,
    this.existing,
    this.initialKind = TxnKind.income,
    this.initialScope = TxnScope.business,
    this.customer,
    this.categoryId,
    this.autofocusAmount = false,
    this.duplicateOf,
  });

  final Txn? existing;
  final Txn? duplicateOf;
  final TxnKind initialKind;
  final TxnScope initialScope;
  final Customer? customer;
  final String? categoryId;
  final bool autofocusAmount;

  @override
  State<TransactionEditPage> createState() => _TransactionEditPageState();
}

class _TransactionEditPageState extends State<TransactionEditPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _settled = TextEditingController();
  final _note = TextEditingController();

  final GlobalKey _payModeAnchor = GlobalKey();

  late TxnKind _kind;
  late TxnScope _scope;
  late String _currency;
  late String _settleCurrency;
  late DateTime _date;
  Customer? _customer;
  Subscription? _subscription;
  Subscription? _renewSub;
  Plan? _newPlan;
  Category? _category;
  bool _credit = false;
  bool _subActionManuallyCleared = false;

  bool _autofocusDone = false;

  // Magnetic horizontal scope transition state
  late final AnimationController _scopeAnim;
  TxnScope _fromScope = TxnScope.business;
  TxnScope _toScope = TxnScope.personal;
  bool _isDragging = false;
  bool _magnetTriggered = false;
  bool _gestureConsumed = false;
  double _dragDx = 0;
  double _dragDir = 0;
  double _slideDir = 1.0;

  bool get isEdit => widget.existing != null;

  String get _pageTitle => isEdit
      ? 'Edit transaction'
      : widget.duplicateOf != null
      ? 'Duplicate transaction'
      : 'New transaction';

  String _presetLabel(Txn t, AppRepository repo) {
    final name = t.note.isNotEmpty
        ? t.note
        : repo.categoryById(t.categoryId)?.name ?? t.kind.shortLabel;
    return '${name.tr} · '
        '${Fmt.number(t.amount, decimals: Money.decimals(t.currency))}';
  }

  bool get _needsCategory =>
      _kind == TxnKind.income || _kind == TxnKind.expense;

  TxnKind? get _categoryKind => switch (_kind) {
    TxnKind.income || TxnKind.receive => TxnKind.income,
    TxnKind.expense => TxnKind.expense,
    _ => null,
  };

  bool get _isTransitioning =>
      _isDragging || _magnetTriggered || _scopeAnim.isAnimating;

  double get _personalProgress {
    if (!_isTransitioning) {
      return _scope == TxnScope.personal ? 1.0 : 0.0;
    }
    final t = _scopeAnim.value.clamp(0.0, 1.0);
    return _fromScope == TxnScope.business ? t : 1.0 - t;
  }

  void _revealPayModeSection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _payModeAnchor.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: 0.35,
      );
    });
  }

  void _syncCategory(AppRepository repo) {
    final kindForCats = _categoryKind;
    if (kindForCats == null) {
      _category = null;
      return;
    }
    final list = repo.categoriesOf(kindForCats, scope: _scope);
    if (_category != null && list.any((c) => c.id == _category!.id)) return;
    _category = repo.categoryById(
      repo.defaultCategoryId(kindForCats, scope: _scope),
    );
  }

  void _syncSubscriptionSelection(AppRepository repo) {
    if (isEdit ||
        _scope != TxnScope.business ||
        _kind != TxnKind.income ||
        _customer == null) {
      _renewSub = null;
      _newPlan = null;
      return;
    }
    if (_subActionManuallyCleared) return;
    if (!isSubscriptionRelatedCategory(repo, _category?.id)) {
      _renewSub = null;
      _newPlan = null;
      return;
    }
    final amt = parseAmount(_amount.text);
    if (amt <= 0) {
      _renewSub = null;
      _newPlan = null;
      return;
    }
    final subs = repo.activeSubsOfCustomer(_customer!.id);
    for (final s in subs) {
      if ((s.amount - amt).abs() < 1.0) {
        _renewSub = s;
        _newPlan = null;
        return;
      }
    }
    for (final p in repo.activePlans) {
      if ((p.price - amt).abs() < 1.0) {
        _renewSub = null;
        _newPlan = p;
        return;
      }
    }
    _renewSub = null;
    _newPlan = null;
  }

  void _copyTransactionDetails(AppRepository repo) {
    final t = widget.existing;
    if (t == null) return;
    final lines = <String>[
      '${t.kind.label}: ${Money.text(t.amount, currency: t.currency)}',
      '${'Date'.tr}: ${J.d(t.date)} · ${Fmt.clock(t.date)}',
      if (t.categoryId != null)
        '${'Category'.tr}: ${repo.categoryName(t.categoryId)}',
      if (t.customerId != null)
        '${'Contact'.tr}: ${repo.customerName(t.customerId)}',
      if (t.note.trim().isNotEmpty) '${'Description'.tr}: ${t.note.tr}',
    ];
    Clipboard.setData(ClipboardData(text: lines.join('\n')));
    showSnack(context, 'Transaction details copied');
  }

  @override
  void initState() {
    super.initState();
    final repo = context.read<AppRepository>();
    final t = widget.existing;
    final copy = widget.duplicateOf;
    _currency = repo.settings.baseCurrency;
    _settleCurrency = repo.settings.baseCurrency;
    _date = DateTime.now();
    _kind = widget.initialKind;
    _scope = widget.initialScope;

    if (t != null) {
      _kind = t.kind;
      _amount.text = groupedNumber(
        t.amount,
        decimals: Money.decimals(t.currency),
      );
      _currency = t.currency;
      _settleCurrency = t.currency;
      _date = t.date;
      _note.text = t.note;
      _customer = repo.customerById(t.customerId);
      _subscription = repo.subscriptionById(t.subscriptionId);
      _category = repo.categoryById(t.categoryId);
      _credit = t.credit;
      _scope = t.scope;
    } else if (copy != null) {
      _kind = copy.kind;
      _amount.text = groupedNumber(
        copy.amount,
        decimals: Money.decimals(copy.currency),
      );
      _currency = copy.currency;
      _settleCurrency = copy.currency;
      _note.text = copy.note;
      _customer = repo.customerById(copy.customerId);
      _category = repo.categoryById(copy.categoryId);
      _credit = copy.credit;
      _scope = copy.scope;
    } else {
      _customer = widget.customer;
      _category =
          repo.categoryById(widget.categoryId) ??
          (widget.initialKind == TxnKind.expense
              ? repo.categoryById(
                  repo.defaultCategoryId(TxnKind.expense, scope: _scope),
                )
              : repo.categoryById(
                  repo.defaultCategoryId(TxnKind.income, scope: _scope),
                ));
    }

    _fromScope = _scope;
    _toScope = _scope == TxnScope.business
        ? TxnScope.personal
        : TxnScope.business;
    _scopeAnim = AnimationController(
      vsync: this,
      value: 0.0,
      duration: const Duration(milliseconds: 240),
    );

    if (widget.autofocusAmount && !isEdit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _autofocusDone = true;
      });
    }
  }

  @override
  void dispose() {
    _scopeAnim.dispose();
    _amount.dispose();
    _settled.dispose();
    _note.dispose();
    super.dispose();
  }

  void _applyScope(AppRepository repo, TxnScope sc) {
    _scope = sc;
    if (_scope == TxnScope.personal) {
      _customer = null;
      _subscription = null;
      _renewSub = null;
      _newPlan = null;
      _credit = false;
      if (_kind != TxnKind.income && _kind != TxnKind.expense) {
        _kind = _kind == TxnKind.receive ? TxnKind.income : TxnKind.expense;
      }
    }
    _syncCategory(repo);
    _syncSubscriptionSelection(repo);
  }

  void _changeScopeByTap(AppRepository repo, TxnScope target) {
    if (_scope == target && !_isTransitioning) return;
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final dirForTarget = target == TxnScope.business
        ? (isRtl ? 1.0 : -1.0)
        : (isRtl ? -1.0 : 1.0);
    Haptics.selection();
    setState(() {
      _fromScope = _scope;
      _toScope = target;
      _slideDir = dirForTarget;
      _isDragging = false;
      _magnetTriggered = true;
      _gestureConsumed = true;
      _scopeAnim.value = 0.0;
    });
    _scopeAnim
        .animateTo(
          1.0,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        )
        .then((_) {
          if (!mounted) return;
          setState(() {
            _applyScope(repo, target);
            _fromScope = _scope;
            _toScope = _scope == TxnScope.business
                ? TxnScope.personal
                : TxnScope.business;
            _magnetTriggered = false;
            _scopeAnim.value = 0.0;
          });
        });
  }

  void _handleHorizontalDragStart(DragStartDetails details) {
    if (_scopeAnim.isAnimating) {
      _scopeAnim.stop();
    }
    _dragDx = 0;
    _dragDir = 0;
    _magnetTriggered = false;
    _gestureConsumed = false;
    _scopeAnim.value = 0.0;
    _fromScope = _scope;
    _toScope = _scope == TxnScope.business
        ? TxnScope.personal
        : TxnScope.business;
  }

  void _handleHorizontalDragUpdate(
    AppRepository repo,
    DragUpdateDetails details,
  ) {
    if (_gestureConsumed || _magnetTriggered) return;
    final width = (context.size?.width ?? 360.0).clamp(240.0, 680.0);
    _dragDx += details.delta.dx;
    if (_dragDir == 0.0) {
      if (_dragDx.abs() < 8.0) {
        _scopeAnim.value = 0.0;
        return;
      }
      _dragDir = _dragDx.sign;
      _slideDir = _dragDir;
      if (!_isDragging) {
        setState(() => _isDragging = true);
      }
    }

    final progress = ((_dragDx * _dragDir) - 8.0).clamp(0.0, width);
    final fraction = (progress / width).clamp(0.0, 1.0);
    // Require dragging nearly half the screen (~45%) before the mid-drag
    // magnet automatically pulls the page to the end.
    final magnetThreshold = width * 0.45;
    if (progress >= magnetThreshold) {
      _triggerMagneticSnap(repo, fromFraction: fraction);
    } else {
      _scopeAnim.value = fraction;
    }
  }

  void _triggerMagneticSnap(
    AppRepository repo, {
    required double fromFraction,
  }) {
    _gestureConsumed = true;
    _magnetTriggered = true;
    _isDragging = false;
    _scopeAnim.value = fromFraction;
    Haptics.selection();
    final remaining = (1.0 - fromFraction).clamp(0.15, 1.0);
    final durationMs = (240 * remaining).round().clamp(120, 240);
    _scopeAnim
        .animateTo(
          1.0,
          duration: Duration(milliseconds: durationMs),
          curve: Curves.easeOutCubic,
        )
        .then((_) {
          if (!mounted) return;
          setState(() {
            _applyScope(repo, _toScope);
            _fromScope = _scope;
            _toScope = _scope == TxnScope.business
                ? TxnScope.personal
                : TxnScope.business;
            _magnetTriggered = false;
            _scopeAnim.value = 0.0;
          });
        });
  }

  void _handleHorizontalDragEnd(
    AppRepository repo,
    DragEndDetails details,
  ) {
    if (_gestureConsumed || _magnetTriggered) {
      _isDragging = false;
      return;
    }
    _gestureConsumed = true;
    final width = (context.size?.width ?? 360.0).clamp(240.0, 680.0);
    final velocity = details.primaryVelocity ?? 0;
    final dir = _dragDir != 0.0
        ? _dragDir
        : (velocity.abs() > 1.0 ? velocity.sign : 0.0);
    if (dir == 0.0) {
      if (_isDragging) setState(() => _isDragging = false);
      return;
    }
    _slideDir = dir;
    final progress = _dragDir != 0.0
        ? ((_dragDx * _dragDir) - 8.0).clamp(0.0, width)
        : 0.0;
    final fraction = (progress / width).clamp(0.0, 1.0);
    final flingInSameDir = (velocity * dir) > 240;
    final shouldSnapToTarget = progress >= width * 0.30 || flingInSameDir;

    if (shouldSnapToTarget) {
      if (!_isDragging) setState(() {});
      _triggerMagneticSnap(repo, fromFraction: fraction);
    } else {
      _isDragging = false;
      _scopeAnim
          .animateTo(
            0.0,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          )
          .then((_) {
            if (!mounted) return;
            setState(() {
              _fromScope = _scope;
              _magnetTriggered = false;
              _scopeAnim.value = 0.0;
            });
          });
    }
  }

  void _handleHorizontalDragCancel() {
    if (_gestureConsumed || _magnetTriggered) {
      _isDragging = false;
      return;
    }
    _isDragging = false;
    _gestureConsumed = true;
    _scopeAnim
        .animateTo(
          0.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
        )
        .then((_) {
          if (!mounted) return;
          setState(() {
            _fromScope = _scope;
            _scopeAnim.value = 0.0;
          });
        });
  }

  void _applyRecent(Txn t, AppRepository repo) {
    Haptics.selection();
    setState(() {
      _kind = t.kind;
      _scope = t.scope;
      _fromScope = _scope;
      _amount.text = groupedNumber(
        t.amount,
        decimals: Money.decimals(t.currency),
      );
      _currency = t.currency;
      _settleCurrency = t.currency;
      _note.text = t.note;
      _settled.clear();
      _date = DateTime.now();
      _customer = t.customerId == null ? null : repo.customerById(t.customerId);
      _category = repo.categoryById(t.categoryId);
      _subscription = null;
      _renewSub = null;
      _newPlan = null;
      _subActionManuallyCleared = false;
      _credit = t.credit;
      if (_scope == TxnScope.personal) {
        _customer = null;
        _credit = false;
      }
      _syncCategory(repo);
      _syncSubscriptionSelection(repo);
    });
  }

  Future<void> _save() async {
    final repo = context.read<AppRepository>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final route = ModalRoute.of(context);
    if (_formKey.currentState?.validate() != true) return;
    if ((_kind == TxnKind.payablePayment ||
            _kind == TxnKind.receive ||
            _kind == TxnKind.refund) &&
        _customer == null) {
      showSnack(context, 'Select a contact for this payment', error: true);
      return;
    }
    final amount = parseAmount(_amount.text);
    final settled = parseAmount(_settled.text);

    if (isEdit) {
      final t = widget.existing!;
      await repo.updateTxn(
        t.copyWith(
          kind: _kind,
          amount: amount,
          currency: _currency,
          rateToBase: _currency == t.currency
              ? t.rateToBase
              : repo.settings.currency(_currency).rateToBase,
          date: _date,
          categoryId: _categoryKind != null ? _category?.id : null,
          clearCategory: _categoryKind == null || _category == null,
          customerId: _customer?.id,
          clearCustomer: _customer == null,
          subscriptionId: _subscription?.id,
          clearSubscription: _subscription == null,
          credit: _credit,
          note: _note.text.trim(),
          scope: _scope,
        ),
      );
    } else if (_scope == TxnScope.business &&
        _customer != null &&
        _kind == TxnKind.income &&
        ((_renewSub != null && _renewSub!.customerId == _customer!.id) ||
            _newPlan != null)) {
      final receivedNow = _credit ? settled : amount;
      if (_renewSub != null && _renewSub!.customerId == _customer!.id) {
        await repo.renewSubscription(
          _renewSub!,
          price: amount,
          received: receivedNow,
          currencyCode: _currency,
          categoryId: _category?.id,
          note: _note.text.trim(),
        );
      } else {
        final plan = _newPlan!;
        final startDate = J.dateOnly(_date);
        final endDate = plan.endFrom(startDate);
        await repo.sellSubscription(
          customer: _customer!,
          plan: plan,
          title: plan.name,
          price: amount,
          currencyCode: _currency,
          start: startDate,
          end: endDate,
          received: receivedNow,
          receiveCurrency: _settleCurrency,
          note: _note.text.trim(),
          categoryId: _category?.id,
        );
      }
    } else {
      final base = repo.buildTxn(
        kind: _kind,
        amount: amount,
        currency: _currency,
        date: _date,
        categoryId: _categoryKind != null ? _category?.id : null,
        customerId: _customer?.id,
        subscriptionId: _subscription?.id,
        credit: _needsCategory && _customer != null ? _credit : false,
        note: _note.text.trim(),
        scope: _scope,
      );
      await repo.addTxn(base);

      if (_needsCategory && _customer != null && _credit && settled > 0) {
        await repo.addTxn(
          repo.buildTxn(
            kind: _kind == TxnKind.income
                ? TxnKind.receive
                : TxnKind.payablePayment,
            amount: settled,
            currency: _settleCurrency,
            date: _date,
            categoryId: _kind == TxnKind.income ? _category?.id : null,
            customerId: _customer!.id,
            subscriptionId: _subscription?.id,
            note: _kind == TxnKind.income ? 'Cash received' : 'Cash paid',
            scope: _scope,
          ),
        );
      }
    }
    if (!mounted) return;
    showMessengerSnack(
      messenger,
      isEdit ? 'Transaction updated' : 'Transaction recorded',
    );
    if (route != null && !route.isCurrent) return;
    if (!isEdit) {
      MoneyCelebration.recorded(context);
    }
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final currencies = repo.settings.currencies;
    final baseCode = repo.settings.baseCurrency;
    final showSettle =
        !isEdit && _needsCategory && _customer != null && _credit;
    final recents = isEdit ? const <Txn>[] : repo.recentDistinctTxns(4);

    return Scaffold(
      appBar: AppBar(
        title: Text(_pageTitle.tr),
        actions: [
          if (_scope == TxnScope.personal)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: Center(
                child: DirectionToggle(
                  isIncome: _kind == TxnKind.income,
                  onSelect: (inc) => setState(() {
                    _kind = inc ? TxnKind.income : TxnKind.expense;
                    _syncCategory(repo);
                  }),
                ),
              ),
            ),
          if (isEdit) ...[
            IconButton(
              tooltip: 'Copy transaction details'.tr,
              icon: const Icon(Icons.copy_rounded),
              onPressed: () => _copyTransactionDetails(repo),
            ),
            IconButton(
              tooltip: 'Delete'.tr,
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                final route = ModalRoute.of(context);
                final ok = await confirmDialog(
                  context,
                  title: 'Delete transaction'.tr,
                  message: 'Delete this transaction?'.tr,
                  danger: true,
                  okLabel: 'Delete'.tr,
                );
                if (!ok) return;
                await repo.deleteTxn(widget.existing!.id);
                if (!mounted) return;
                showMessengerSnack(messenger, 'Transaction deleted');
                if (route != null && !route.isCurrent) return;
                navigator.pop();
              },
            ),
          ],
        ],
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: _amount,
        builder: (context, _) {
          final amt = parseAmount(_amount.text);
          return FormActionBar(
            label: isEdit
                ? 'Save changes'.tr
                : amt > 0
                ? 'Record {amount}'.trArgs({
                    'amount': Money.text(amt, currency: _currency),
                  })
                : 'Record'.tr,
            hint: amt > 0
                ? null
                : (isEdit ? 'Enter an amount' : 'Enter an amount to record')
                      .tr,
            onPressed: amt > 0 ? _save : null,
          );
        },
      ),
      body: Form(
        key: _formKey,
        child: FormPageContent(
          maxWidth: 760,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: _handleHorizontalDragStart,
            onHorizontalDragUpdate: (d) =>
                _handleHorizontalDragUpdate(repo, d),
            onHorizontalDragCancel: _handleHorizontalDragCancel,
            onHorizontalDragEnd: (d) => _handleHorizontalDragEnd(repo, d),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
              children: [
                // -------- 1. Magnetic Scope Switcher (Business / Personal) --------
                AnimatedBuilder(
                  animation: _scopeAnim,
                  builder: (context, _) => ScopeMagneticBar(
                    personalProgress: _personalProgress,
                    onSelectScope: (sc) => _changeScopeByTap(repo, sc),
                  ),
                ),

                // -------- 2. Business Kind Strip (when in Business scope) --------
                if (_scope == TxnScope.business) ...[
                  const SizedBox(height: 10),
                  TxnKindStrip(
                    kinds: TxnKind.values,
                    selected: _kind,
                    onSelect: (k) => setState(() {
                      _kind = k;
                      if (k != TxnKind.income) {
                        _renewSub = null;
                        _newPlan = null;
                      }
                      _syncCategory(repo);
                      _syncSubscriptionSelection(repo);
                    }),
                  ),
                ],

                // -------- 3. Amount & Date/Currency --------
                const SizedBox(height: 12),
                AmountField(
                  controller: _amount,
                  label: 'Amount'.tr,
                  currency: _currency,
                  autofocus:
                      widget.autofocusAmount && !isEdit && !_autofocusDone,
                  textInputAction: TextInputAction.next,
                  onChanged: () {
                    if (!isEdit &&
                        _scope == TxnScope.business &&
                        _customer != null &&
                        _kind == TxnKind.income) {
                      setState(() => _syncSubscriptionSelection(repo));
                    }
                  },
                ),
                ListenableBuilder(
                  listenable: _amount,
                  builder: (context, _) {
                    final amt = parseAmount(_amount.text);
                    if (_currency == baseCode || amt <= 0) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Base-currency equivalent at {rate} = {amount}'.trArgs({
                          'rate': Money.text(
                            repo.settings.currency(_currency).rateToBase,
                          ),
                          'amount': Money.text(
                            amt * repo.settings.currency(_currency).rateToBase,
                          ),
                        }),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    );
                  },
                ),

                // -------- 4. Date & Currency --------
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _datePill(context)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 96,
                      child: SelectField<String>(
                        label: 'Currency'.tr,
                        value: _currency,
                        items: currencies.map((c) => c.code).toList(),
                        labelOf: (c) => Money.symbol(c),
                        onChanged: (c) => setState(() {
                          _currency = c ?? _currency;
                          _settleCurrency = _currency;
                        }),
                      ),
                    ),
                  ],
                ),

                // -------- 5. Repeat Recent Entries (compact strip) --------
                if (!isEdit && recents.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const SectionCaption('Recent'),
                  const SizedBox(height: 6),
                  ChipStrip(
                    chips: [
                      for (final t in recents)
                        PresetChip(
                          icon: t.kind.icon,
                          label: _presetLabel(t, repo),
                          onTap: () => _applyRecent(t, repo),
                        ),
                    ],
                  ),
                ],

                // -------- 6. Magnetic 2-Page Scope Details («به حساب» / «از حساب», Shortcuts, Contact) --------
                if (!_isTransitioning)
                  ..._buildScopeChildren(
                    repo: repo,
                    pageScope: _scope,
                    showSettle: showSettle,
                    currencies: currencies,
                    onSurface: onSurface,
                  )
                else
                  _buildMagneticScopeSection(
                    repo: repo,
                    showSettle: showSettle,
                    currencies: currencies,
                    onSurface: onSurface,
                  ),

                // -------- 7. Description --------
                const SizedBox(height: 12),
                AppTextField(
                  controller: _note,
                  label: 'Description'.tr,
                  icon: Icons.notes_rounded,
                  maxLines: 2,
                ),
                if (isEdit &&
                    repo.smsHistoryForTxn(widget.existing!.id) != null) ...[
                  const SizedBox(height: 12),
                  _buildLinkedSmsCard(
                    context,
                    repo.smsHistoryForTxn(widget.existing!.id)!,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLinkedSmsCard(BuildContext context, dynamic smsEntry) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final String bankName =
        (smsEntry.bankName as String?)?.isNotEmpty == true
        ? (smsEntry.bankName as String).tr
        : (smsEntry.message.address as String).isNotEmpty
        ? (smsEntry.message.address as String)
        : 'Linked bank SMS'.tr;
    final String body = smsEntry.message.body as String;
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.sms_outlined,
                size: 17,
                color: Color(0xFF0F766E),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${'Linked bank SMS'.tr} · $bankName',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Copy'.tr,
                icon: const Icon(Icons.copy_rounded, size: 16),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: body));
                  showSnack(context, 'Copied');
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.55,
              color: onSurface.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMagneticScopeSection({
    required AppRepository repo,
    required bool showSettle,
    required List<CurrencyDef> currencies,
    required Color onSurface,
  }) {
    if (!_isTransitioning) {
      return _buildScopeDetails(
        repo: repo,
        pageScope: _scope,
        showSettle: showSettle,
        currencies: currencies,
        onSurface: onSurface,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width - 32;
        final fromChild = RepaintBoundary(
          child: IgnorePointer(
            child: _buildScopeDetails(
              repo: repo,
              pageScope: _fromScope,
              showSettle: showSettle,
              currencies: currencies,
              onSurface: onSurface,
            ),
          ),
        );
        final toChild = RepaintBoundary(
          child: IgnorePointer(
            child: _buildScopeDetails(
              repo: repo,
              pageScope: _toScope,
              showSettle: showSettle,
              currencies: currencies,
              onSurface: onSurface,
            ),
          ),
        );

        return ClipRect(
          child: AnimatedBuilder(
            animation: _scopeAnim,
            builder: (context, _) {
              final t = _scopeAnim.value.clamp(0.0, 1.0);
              final fromDx = _slideDir * width * t;
              final toDx = fromDx - _slideDir * width;

              return Stack(
                alignment: Alignment.topCenter,
                children: [
                  Transform.translate(
                    offset: Offset(fromDx, 0),
                    child: fromChild,
                  ),
                  Transform.translate(
                    offset: Offset(toDx, 0),
                    child: toChild,
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildScopeDetails({
    required AppRepository repo,
    required TxnScope pageScope,
    required bool showSettle,
    required List<CurrencyDef> currencies,
    required Color onSurface,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: _buildScopeChildren(
        repo: repo,
        pageScope: pageScope,
        showSettle: showSettle,
        currencies: currencies,
        onSurface: onSurface,
      ),
    );
  }

  List<Widget> _buildScopeChildren({
    required AppRepository repo,
    required TxnScope pageScope,
    required bool showSettle,
    required List<CurrencyDef> currencies,
    required Color onSurface,
  }) {
    final categoryKind = _categoryKind;
    final isCurrentScope = pageScope == _scope;
    final selectedCatId = isCurrentScope
        ? _category?.id
        : (categoryKind == null
              ? null
              : repo.defaultCategoryId(categoryKind, scope: pageScope));
    final shortcuts = categoryKind == null
        ? const <Category>[]
        : repo.shortcutCategories(categoryKind, scope: pageScope);

    return <Widget>[
        // -------- «به حساب» / «از حساب» + Inline Search + Shortcuts --------
        if (categoryKind != null) ...[
          const SizedBox(height: 12),
          AccountSelectorSection(
            repo: repo,
            categoryKind: categoryKind,
            scope: pageScope,
            selectedCategoryId: selectedCatId,
            shortcuts: shortcuts,
            onSelectCategory: (cat) => setState(() {
              _category = cat;
              _subActionManuallyCleared = false;
              _syncSubscriptionSelection(repo);
            }),
          ),
        ],

        // -------- Business Contact & Cash/Credit --------
        if (pageScope == TxnScope.business) ...[
          const SizedBox(height: 10),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _amount,
            builder: (context, _, _) => ContactSelectorSection(
              repo: repo,
              selectedCustomer: _customer,
              referenceAmount: parseAmount(_amount.text),
              isDeposit: _kind == TxnKind.income || _kind == TxnKind.receive,
              onSelectCustomer: (c) {
                final selecting = c != null;
                setState(() {
                  _customer = c;
                  _subActionManuallyCleared = false;
                  _syncSubscriptionSelection(repo);
                });
                if (selecting) _revealPayModeSection();
              },
            ),
          ),
          if (!isEdit && _customer != null && _kind == TxnKind.income) ...[
            const SizedBox(height: 8),
            SubscriptionActionSelector(
              repo: repo,
              customer: _customer!,
              renewSub: _renewSub,
              newPlan: _newPlan,
              onSelect: (res) => setState(() {
                _renewSub = res.renewSub;
                _newPlan = res.newPlan;
                _subActionManuallyCleared =
                    res.renewSub == null && res.newPlan == null;
              }),
            ),
          ],
          if (_needsCategory && _customer != null) ...[
            SizedBox(key: _payModeAnchor, height: 14),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 18,
                  ),
                  label: Text('Cash'.tr),
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(
                    Icons.receipt_long_outlined,
                    size: 18,
                  ),
                  label: Text('Credit'.tr),
                ),
              ],
              selected: {_credit},
              onSelectionChanged: (s) {
                Haptics.selection();
                setState(() => _credit = s.first);
                _revealPayModeSection();
              },
              style: SegmentedButton.styleFrom(
                minimumSize: const Size(0, Taps.minHeight),
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 6),
            ListenableBuilder(
              listenable: Listenable.merge([_amount, _settled]),
              builder: (context, _) => Text(
                _payModeHint,
                style: TextStyle(
                  fontSize: 11.5,
                  color: onSurface.withValues(alpha: 0.65),
                ),
              ),
            ),
            if (showSettle) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AmountField(
                      controller: _settled,
                      label: _kind == TxnKind.income
                          ? 'Cash received now'
                          : 'Cash paid now',
                      currency: _settleCurrency,
                      textInputAction: TextInputAction.next,
                      validator: (_) => null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 96,
                    child: SelectField<String>(
                      label: 'Currency'.tr,
                      value: _settleCurrency,
                      items: currencies.map((c) => c.code).toList(),
                      labelOf: (c) => Money.symbol(c),
                      onChanged: (c) => setState(
                        () => _settleCurrency = c ?? _settleCurrency,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ];
  }

  Widget _datePill(BuildContext context) {
    final isToday = J.sameDay(_date, J.today);
    return Semantics(
      button: true,
      label: 'Date'.tr,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          final res = await showJalaliPicker(context, initial: _date);
          if (!mounted) return;
          if (res != null) setState(() => _date = res);
        },
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Date'.tr,
            prefixIcon: const Icon(Icons.calendar_month_rounded, size: 19),
          ),
          child: Text(
            isToday ? 'Today'.tr : J.d(_date),
            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  String get _payModeHint {
    final amount = parseAmount(_amount.text);
    final isIncome = _kind == TxnKind.income;
    if (!_credit) {
      return (isIncome ? 'Cash goes into the box.' : 'Cash leaves the box.')
          .tr;
    }
    if (amount <= 0) {
      return (isIncome
              ? 'Credit is added to this customer\'s balance.'
              : 'Credit is recorded as our debt to this contact.')
          .tr;
    }
    final rest = amount - parseAmount(_settled.text);
    if (rest <= 0) return 'Paid in full'.tr;
    if (isIncome) {
      return 'The remaining balance will be recorded as customer debt: {amount}'
          .trArgs({'amount': Money.text(rest, currency: _currency)});
    }
    return 'The rest will be recorded as our debt to this contact: {amount}'
        .trArgs({'amount': Money.text(rest, currency: _currency)});
  }
}
