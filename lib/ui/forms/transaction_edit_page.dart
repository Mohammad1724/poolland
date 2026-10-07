import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format_utils.dart';
import '../design.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../widgets/widgets.dart';
import 'contact_edit_page.dart';

import '../../core/localization.dart';

/// Record or edit a transaction (income, expense, receipt, or payment)
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

  bool get _needsCategory =>
      _kind == TxnKind.income || _kind == TxnKind.expense;

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

  Future<void> _save() async {
    final repo = context.read<AppRepository>();
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
    showSnack(context, isEdit ? 'Transaction updated' : 'Transaction recorded');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final currencies = repo.settings.currencies;
    final showSettle =
        !isEdit && _needsCategory && _customer != null && _credit;

    return Scaffold(
      appBar: AppBar(
        title: Text(_pageTitle.tr),
        actions: [
          if (isEdit)
            IconButton(
              tooltip: 'Delete'.tr,
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final ok = await confirmDialog(
                  context,
                  title: 'Delete transaction'.tr,
                  message: 'Delete this transaction?'.tr,
                  danger: true,
                  okLabel: 'Delete'.tr,
                );
                if (!ok) return;
                await repo.deleteTxn(widget.existing!.id);
                if (!context.mounted) return;
                Navigator.pop(context);
                showSnack(context, 'Transaction deleted');
              },
            ),
        ],
      ),
      bottomNavigationBar: FormActionBar(
        label: isEdit ? 'Save changes' : 'Record',
        onPressed: _save,
      ),
      body: Form(
        key: _formKey,
        child: FormPageContent(
          maxWidth: 760,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            children: [
              // Transaction type
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in TxnKind.values)
                    ChoiceChip(
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                      avatar: Icon(k.icon, size: 16),
                      label: Text(k.label),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              // Scope: business or personal
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
                  final list = repo.categoriesOf(_kind, scope: _scope);
                  if (_category != null &&
                      !list.any((c) => c.id == _category!.id)) {
                    _category =
                        repo.defaultCategoryId(_kind, scope: _scope) == null
                        ? null
                        : repo.categoryById(
                            repo.defaultCategoryId(_kind, scope: _scope),
                          );
                  }
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
                  color: Theme.of(context).colorScheme.onSurface
                      .withValues(alpha: 0.55),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: AmountField(
                      controller: _amount,
                      label: 'Amount'.tr,
                      currency: _currency,
                      autofocus: widget.autofocusAmount && !isEdit,
                      textInputAction: TextInputAction.next,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 112,
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
              if (_currency != 'IRT')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Base-currency equivalent at {rate} = {amount}'.trArgs({
                      'rate': Money.text(
                        repo.settings.currency(_currency).rateToBase,
                      ),
                      'amount': Money.text(
                        parseAmount(_amount.text) *
                            repo.settings.currency(_currency).rateToBase,
                      ),
                    }),
                    style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.onSurface
                          .withValues(alpha: 0.6),
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              JalaliDateField(
                label: 'Date'.tr,
                value: _date,
                onChanged: (d) => setState(() => _date = d),
              ),
              const SizedBox(height: 14),

              // Business contact. Personal spending is kept out of customer accounts.
              if (_scope == TxnScope.business)
                Row(
                  children: [
                    Expanded(
                      child: SelectField<Customer>(
                        label: 'Contact (optional)'.tr,
                        icon: Icons.person_outline_rounded,
                        value: _customer,
                        items: repo.activeCustomers,
                        clearable: true,
                        labelOf: (c) => c.name,
                        subOf: (c) => c.phone,
                        searchHint: 'Customer name...'.tr,
                        sheetTitle: 'Select contact'.tr,
                        onChanged: (c) => setState(() => _customer = c),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'New contact'.tr,
                      onPressed: () async {
                        final created = await Navigator.push<Customer>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const ContactEditPage(),
                          ),
                        );
                        if (created != null) {
                          setState(() => _customer = created);
                        }
                      },
                      icon: const Icon(
                        Icons.person_add_alt_1_rounded,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              if (_needsCategory) ...[
                const SizedBox(height: 14),
                SelectField<Category>(
                  label: 'Category'.tr,
                  icon: Icons.category_outlined,
                  value: _category,
                  items: repo.categoriesOf(_kind, scope: _scope),
                  labelOf: (c) => c.name,
                  onChanged: (c) => setState(() => _category = c),
                ),
                if (_customer != null) ...[
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _credit,
                    onChanged: (v) => setState(() => _credit = v),
                    title: Text(
                      _kind == TxnKind.income
                          ? 'Credit (customer balance)'
                          : 'Credit (our payable)',
                      style: const TextStyle(fontSize: 13.5),
                    ),
                    subtitle: Text(
                      'When on, record the charge first and enter any amount already settled below.'
                          .tr,
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
              ],
              if (showSettle) ...[
                const SizedBox(height: 6),
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
                      width: 112,
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
              const SizedBox(height: 14),
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
}
