import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format_utils.dart';
import '../../core/haptics.dart';
import '../../core/jalali_utils.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../design.dart';
import '../motion_kit.dart';
import '../personal_page.dart';
import '../settings_page.dart';
import '../widgets/date_picker.dart';
import '../widgets/quick_buttons.dart';
import '../widgets/widgets.dart';
import 'contact_edit_page.dart';

import '../../core/localization.dart';

/// Record or edit a transaction (income, expense, receipt, or payment).
///
/// The form is organized in three zones, in the order a person states a
/// transaction out loud:
///
/// 1. **Intent** — the kind tiles (color-coded exactly like the ledger
///    rows) and the business/personal scope, plus one-tap quick-fill strips:
///    recent entries to repeat and the saved quick buttons.
/// 2. **The numbers** — the amount, auto-focused and full width, then one
///    compact row with the date (it reads "Today" until changed) and the
///    currency. With the keyboard open, the user still sees the kind
///    selection above the field they are typing in.
/// 3. **Details** — the contact as chips with a live balance, the category
///    as chips, the cash/credit mode with its consequence spelled out, and
///    the description.
///
/// The record button mirrors the amount, so the entered value stays visible
/// without scrolling back to the top.
class TransactionEditPage extends StatefulWidget {
  const TransactionEditPage({
    super.key,
    this.existing,
    this.initialKind = TxnKind.income,
    this.initialScope = TxnScope.business,
    this.customer,
    this.categoryId,
    this.autofocusAmount = true,
    this.duplicateOf,
  });

  final Txn? existing;

  /// Prefills this form from an existing entry **without** editing it, so
  /// saving records a second, separate transaction ("same as last time").
  ///
  /// Everything is copied except the parts that would make it the same entry:
  /// the date becomes today, the received/prepaid amount is left empty, and no
  /// subscription is linked (a duplicate must not silently count as another
  /// sale of the same subscription).
  final Txn? duplicateOf;
  final TxnKind initialKind;
  final TxnScope initialScope;
  final Customer? customer;
  final String? categoryId;

  /// Opens the keyboard on the amount field right away, so a new entry can be
  /// typed without a tap. Ignored while editing (and turned off by flows such
  /// as SMS review, where the details are being checked first).
  final bool autofocusAmount;

  @override
  State<TransactionEditPage> createState() => _TransactionEditPageState();
}

class _TransactionEditPageState extends State<TransactionEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _settled = TextEditingController();
  final _note = TextEditingController();

  late TxnKind _kind;
  late TxnScope _scope;
  late String _currency;
  late String _settleCurrency;
  late DateTime _date;
  Customer? _customer;
  Subscription? _subscription;
  Category? _category;
  bool _credit = false;

  bool get isEdit => widget.existing != null;

  /// A duplicate is a new entry, but the title says so, so it is obvious that
  /// the original is not being changed.
  String get _pageTitle => isEdit
      ? 'Edit transaction'
      : widget.duplicateOf != null
      ? 'Duplicate transaction'
      : 'New transaction';

  /// Chip text for "repeat this recent entry": the note when there is one,
  /// otherwise the category or a safe kind name, plus the plain amount.
  String _presetLabel(Txn t, AppRepository repo) {
    final name = t.note.isNotEmpty
        ? t.note
        : repo.categoryById(t.categoryId)?.name ?? t.kind.shortLabel;
    return '${name.tr} · '
        '${Fmt.number(t.amount, decimals: Money.decimals(t.currency))}';
  }

  bool get _needsCategory =>
      _kind == TxnKind.income || _kind == TxnKind.expense;

  /// Re-validates the selected category after the kind or the section
  /// changes. Without this the form silently saves a category that belongs
  /// to the *other* kind or scope (an income category on an expense, a
  /// personal one on a business entry), which corrupts the per-category
  /// reports. Falls back to the default category of the new list.
  void _syncCategory(AppRepository repo) {
    final kindForCats = switch (_kind) {
      TxnKind.income || TxnKind.receive => TxnKind.income,
      TxnKind.expense => TxnKind.expense,
      _ => null,
    };
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
      // Same as last time: everything is filled in, but the date is today and
      // the entry stays separate from the one it was copied from.
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
  }

  @override
  void dispose() {
    _amount.dispose();
    _settled.dispose();
    _note.dispose();
    super.dispose();
  }

  /// Prefill the form from a quick-entry button; everything stays editable.
  void _applyQuick(QuickExpense q) {
    final repo = context.read<AppRepository>();
    Haptics.selection();
    setState(() {
      _scope = q.scope;
      _kind = q.kind == TxnKind.income ? TxnKind.income : TxnKind.expense;
      if (q.scope == TxnScope.personal) {
        _customer = null;
        _subscription = null;
        _credit = false;
      }
      if (q.categoryId != null) {
        _category = repo.categoryById(q.categoryId);
      }
      // The button may have moved the form to another section or direction;
      // the category must belong to the new combination.
      _syncCategory(repo);
      if (q.hasFixedAmount) {
        _amount.text = groupedNumber(
          q.amount,
          decimals: Money.decimals(_currency),
        );
      }
    });
  }

  /// One-tap repeat of a recent entry: the whole combination (kind, section,
  /// amount, currency, contact, category, note) comes across, but the date is
  /// today and no settled amount is carried over — a repeat is a fresh entry,
  /// exactly like the duplicate action.
  void _applyRecent(Txn t, AppRepository repo) {
    Haptics.selection();
    setState(() {
      _kind = t.kind;
      _scope = t.scope;
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
      _credit = t.credit;
      if (_scope == TxnScope.personal) {
        _customer = null;
        _credit = false;
      }
      _syncCategory(repo);
    });
  }

  Future<void> _openQuickEdit([QuickExpense? q]) async {
    await showLedgerSheet<void>(
      context,
      builder: (_) => QuickEditSheet(
        initial: q,
        presetScope: _scope,
        presetKind: _kind == TxnKind.income || _kind == TxnKind.receive
            ? TxnKind.income
            : TxnKind.expense,
      ),
    );
  }

  Widget _addQuickChip() => ActionChip(
    avatar: const Icon(Icons.add_rounded, size: 16),
    label: Text('Quick button'.tr),
    onPressed: () => _openQuickEdit(),
  );

  /// Opens the contact form and selects the saved result in the form.
  Future<void> _newContact() async {
    final created = await Navigator.push<Customer>(
      context,
      MaterialPageRoute(builder: (_) => const ContactEditPage()),
    );
    if (!mounted) return;
    if (created != null) {
      setState(() => _customer = created);
    }
  }

  /// The full, searchable contact sheet behind the "all contacts" chip, for
  /// customers who are not among the frequent ones.
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
    if (res.cleared) {
      setState(() => _customer = null);
    } else if (res.value != null) {
      setState(() => _customer = res.value);
    }
  }

  Future<void> _save() async {
    final repo = context.read<AppRepository>();
    // Resolved before the first await. Writing an entry takes real time, and
    // the page can be closed while it is in flight (back button, predictive
    // back, a system gesture). Popping again after that would not pop *this*
    // page — it is already on its way out — it would take the page underneath
    // it with it, and `mounted` stays true for the whole exit transition.
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final route = ModalRoute.of(context);
    if (_formKey.currentState?.validate() != true) return;
    if (_kind == TxnKind.payablePayment && _customer == null) {
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
          categoryId: _category?.id,
          clearCategory: _category == null,
          customerId: _customer?.id,
          clearCustomer: _customer == null,
          subscriptionId: _subscription?.id,
          clearSubscription: _subscription == null,
          credit: _credit,
          note: _note.text.trim(),
          scope: _scope,
        ),
      );
    } else {
      final base = repo.buildTxn(
        kind: _kind,
        amount: amount,
        currency: _currency,
        date: _date,
        categoryId: _needsCategory ? _category?.id : null,
        customerId: _customer?.id,
        subscriptionId: _subscription?.id,
        credit: _needsCategory && _customer != null ? _credit : false,
        note: _note.text.trim(),
        scope: _scope,
      );
      await repo.addTxn(base);

      // Any amount paid or received immediately is recorded separately.
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
    // The entry is written either way, and the messenger belongs to the app
    // rather than to this page, so the confirmation is shown even when the
    // page is already leaving.
    showMessengerSnack(
      messenger,
      isEdit ? 'Transaction updated' : 'Transaction recorded',
    );
    if (route != null && !route.isCurrent) return;
    if (!isEdit) {
      // A new record gets the coin + stamp moment; edits stay quiet.
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
    final amount = parseAmount(_amount.text);
    final showSettle =
        !isEdit && _needsCategory && _customer != null && _credit;
    final recents = isEdit ? const <Txn>[] : repo.recentDistinctTxns(4);
    final categories = _needsCategory
        ? repo.categoriesOf(_kind, scope: _scope)
        : const <Category>[];
    final topContacts = repo.topCustomers(limit: 4);
    final contactChips = topContacts.isNotEmpty
        ? topContacts
        : repo.activeCustomers.take(4).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_pageTitle.tr),
        actions: [
          if (isEdit)
            IconButton(
              tooltip: 'Delete'.tr,
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                // Resolved before the first await, for the same reason as in
                // _save: this handler awaits twice (the confirmation dialog
                // and the write), and either window is long enough for the
                // page to be closed from under it.
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
      ),
      bottomNavigationBar: AnimatedBuilder(
        animation: _amount,
        builder: (context, _) {
          final amt = parseAmount(_amount.text);
          return FormActionBar(
            // The button mirrors the amount: while the field is scrolled
            // away or covered, the value about to be recorded stays visible.
            label: isEdit
                ? 'Save changes'.tr
                : amt > 0
                    ? 'Record {amount}'.trArgs({
                        'amount': Money.text(amt, currency: _currency),
                      })
                    : 'Record'.tr,
            // Disabled until there is an amount. `validate()` refuses the very
            // same empty amount, but its message renders next to a field that
            // is usually scrolled out of view by then — so the tap looked
            // ignored and the page just refused to close, with nothing on
            // screen to say why.
            onPressed: amt > 0 ? _save : null,
          );
        },
      ),
      body: Form(
        key: _formKey,
        child: FormPageContent(
          maxWidth: 760,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            children: [
              // ---------------- 1. Intent ----------------
              // Kind tiles: one line, color-coded like the ledger rows, so
              // the selection is confirmed at a glance while the keyboard is
              // open on the amount.
              _kindRow(context),
              const SizedBox(height: 10),
              SegmentedButton<TxnScope>(
                segments: [
                  for (final sc in TxnScope.values)
                    ButtonSegment(value: sc, label: Text(sc.label)),
                ],
                selected: {_scope},
                onSelectionChanged: (s) => setState(() {
                  _scope = s.first;
                  if (_scope == TxnScope.personal) {
                    _customer = null;
                    _subscription = null;
                    _credit = false;
                  }
                  _syncCategory(repo);
                }),
                style: SegmentedButton.styleFrom(
                  // Compact density would shave this down to ~32dp, which is
                  // too small to hit reliably; ask for a real 44dp instead.
                  minimumSize: const Size(0, Taps.minHeight),
                  textStyle: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _scope.hint,
                style: TextStyle(
                  fontSize: 11,
                  color: onSurface.withValues(alpha: 0.55),
                ),
              ),
              if (!isEdit) ...[
                // Presets from the ledger's own habits: repeat a recent
                // entry with one tap, right at the top of the form.
                if (recents.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _sectionCaption('Recent'),
                  const SizedBox(height: 6),
                  _chipRow([
                    for (final t in recents)
                      _PresetChip(
                        icon: t.kind.icon,
                        label: _presetLabel(t, repo),
                        onTap: () => _applyRecent(t, repo),
                      ),
                  ]),
                ],
                // Quick-entry buttons matching the current section and
                // direction; tapping one prefills this form (still
                // editable), long-press edits it, the trailing chip adds a
                // new button for exactly this case.
                Padding(
                  padding: EdgeInsets.only(top: recents.isNotEmpty ? 8 : 14),
                  child: QuickButtonsRow(
                    scopeFilter: _scope,
                    incomeFilter: _kind == TxnKind.income ||
                        _kind == TxnKind.receive,
                    hideWhenEmpty: true,
                    onTap: _applyQuick,
                    onLongPress: (q) => _openQuickEdit(q),
                    trailing: _addQuickChip(),
                  ),
                ),
              ],
              // ---------------- 2. The numbers ----------------
              const SizedBox(height: 16),
              AmountField(
                controller: _amount,
                label: 'Amount'.tr,
                currency: _currency,
                autofocus: widget.autofocusAmount && !isEdit,
                textInputAction: TextInputAction.next,
              ),
              if (_currency != baseCode && amount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Base-currency equivalent at {rate} = {amount}'.trArgs({
                      'rate': Money.text(
                        repo.settings.currency(_currency).rateToBase,
                      ),
                      'amount': Money.text(
                        amount *
                            repo.settings.currency(_currency).rateToBase,
                      ),
                    }),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
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
              // ---------------- 3. Details ----------------
              // Business contact. Personal spending is kept out of customer
              // accounts. The frequent ones are one tap away as chips; the
              // rest live in the searchable sheet behind "all contacts".
              if (_scope == TxnScope.business) ...[
                const SizedBox(height: 16),
                _sectionCaption('Contact (optional)'),
                const SizedBox(height: 6),
                _chipRow([
                  for (final c in contactChips) _contactChip(c),
                  _PresetChip(
                    icon: Icons.person_search_outlined,
                    label: 'All contacts'.tr,
                    onTap: _openContactSheet,
                  ),
                  _PresetChip(
                    icon: Icons.person_add_alt_1_rounded,
                    label: 'New contact'.tr,
                    onTap: _newContact,
                  ),
                ]),
                if (_customer != null) _balanceCard(context, repo),
              ],
              if (_needsCategory) ...[
                const SizedBox(height: 16),
                _sectionCaption('Category'),
                const SizedBox(height: 6),
                _chipRow([
                  for (final c in categories)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 190),
                      child: ChoiceChip(
                        label: Text(
                          c.name.tr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        selected: _category?.id == c.id,
                        showCheckmark: false,
                        onSelected: (_) {
                          Haptics.selection();
                          setState(() => _category = c);
                        },
                      ),
                    ),
                  _PresetChip(
                    icon: Icons.tune_rounded,
                    label: 'Manage'.tr,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const CategoriesPage(),
                      ),
                    ),
                  ),
                ]),
              ],
              if (_needsCategory && _customer != null) ...[
                const SizedBox(height: 16),
                // Cash or credit: the one choice that changes where the money
                // lands, so it is a labeled two-state control with the
                // consequence spelled out right below it.
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
                  },
                  style: SegmentedButton.styleFrom(
                    minimumSize: const Size(0, Taps.minHeight),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _payModeHint,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: onSurface.withValues(alpha: 0.65),
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
              const SizedBox(height: 16),
              AppTextField(
                controller: _note,
                label: 'Description'.tr,
                icon: Icons.notes_rounded,
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------- Layout helpers ----------------

  /// One line of kind tiles (single row, scrollable on narrow screens).
  Widget _kindRow(BuildContext context) {
    return SizedBox(
      height: 50,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          for (final k in TxnKind.values)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: _kindTile(context, k),
            ),
        ],
      ),
    );
  }

  Widget _kindTile(BuildContext context, TxnKind k) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final color = k.color;
    final selected = _kind == k;
    return Semantics(
      button: true,
      selected: selected,
      label: k.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: () {
          Haptics.selection();
          final repo = context.read<AppRepository>();
          setState(() {
            _kind = k;
            _syncCategory(repo);
          });
        },
        child: AnimatedContainer(
          duration: Motion.adaptive(context, Motion.quick),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: selected ? color.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? color.withValues(alpha: 0.5)
                  : theme.dividerColor,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                k.icon,
                size: 17,
                color: selected ? color : onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(height: 2),
              Text(
                k.shortLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? color : onSurface.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A small section caption; [key] is a localization key, translated here.
  Widget _sectionCaption(String key) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        key.tr,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurface
              .withValues(alpha: 0.7),
        ),
      ),
    );
  }

  /// One horizontal strip of chips. A fixed height keeps the form from
  /// jumping when a strip appears or disappears.
  Widget _chipRow(List<Widget> chips) {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          for (final chip in chips)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 8),
              child: chip,
            ),
        ],
      ),
    );
  }

  /// Contact chip: one tap selects the customer, a second tap clears the
  /// selection — faster than a sheet for the regulars.
  Widget _contactChip(Customer c) {
    final selected = _customer?.id == c.id;
    return _PresetChip(
      icon: Icons.person_outline_rounded,
      label: c.name,
      selected: selected,
      onTap: () {
        Haptics.selection();
        setState(() => _customer = selected ? null : c);
      },
    );
  }

  /// Live balance of the selected contact, so "how much do they owe" is
  /// answered without leaving the form.
  Widget _balanceCard(BuildContext context, AppRepository repo) {
    final c = _customer!;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.account_balance_wallet_outlined,
            size: 16,
            color: scheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          MoneyText(
            repo.balanceOf(c),
            signed: true,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  /// The date as a compact field that reads "Today" until it is changed, so
  /// the common case never opens a calendar at all.
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

  /// One line of consequence under the cash/credit control: what saving will
  /// actually do to the box and to the contact's account.
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

/// A tappable preset chip: recent-entry repeats, contacts, and the "see
/// all" / "add" openers. Long labels ellipsize inside a fixed width so a
/// strip always stays exactly one line.
class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;

  /// Plain display text: already translated for keys, or user data (a contact
  /// name) that must not be translated.
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onSurface = scheme.onSurface;
    final accent = selected
        ? scheme.primary
        : onSurface.withValues(alpha: 0.6);
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.adaptive(context, Motion.quick),
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: 0.12)
                : onSurface.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.45)
                  : onSurface.withValues(alpha: 0.14),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: accent),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? scheme.primary
                        : onSurface.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
