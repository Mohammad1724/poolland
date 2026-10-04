import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/format_utils.dart';
import '../../core/money.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../widgets/widgets.dart';
import 'contact_edit_page.dart';

/// ثبت یا ویرایش یک تراکنش (درآمد، هزینه، دریافت، پرداخت)
class TransactionEditPage extends StatefulWidget {
  const TransactionEditPage({
    super.key,
    this.existing,
    this.initialKind = TxnKind.income,
    this.initialScope = TxnScope.business,
    this.customer,
    this.categoryId,
  });

  final Txn? existing;
  final TxnKind initialKind;
  final TxnScope initialScope;
  final Customer? customer;
  final String? categoryId;

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

  bool get _needsCategory => _kind == TxnKind.income || _kind == TxnKind.expense;

  @override
  void initState() {
    super.initState();
    final repo = context.read<AppRepository>();
    final t = widget.existing;
    _currency = repo.settings.baseCurrency;
    _settleCurrency = repo.settings.baseCurrency;
    _date = DateTime.now();
    _kind = widget.initialKind;
    _scope = widget.initialScope;

    if (t != null) {
      _kind = t.kind;
      _amount.text = groupedNumber(t.amount, decimals: Money.decimals(t.currency));
      _currency = t.currency;
      _settleCurrency = t.currency;
      _date = t.date;
      _note.text = t.note;
      _customer = repo.customerById(t.customerId);
      _subscription = repo.subscriptionById(t.subscriptionId);
      _category = repo.categoryById(t.categoryId);
      _credit = t.credit;
      _scope = t.scope;
    } else {
      _customer = widget.customer;
      _category = repo.categoryById(widget.categoryId) ??
          (widget.initialKind == TxnKind.expense
              ? repo.categoryById(
                  repo.defaultCategoryId(TxnKind.expense, scope: _scope))
              : repo.categoryById(
                  repo.defaultCategoryId(TxnKind.income, scope: _scope)));
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
    final amount = parseAmount(_amount.text);
    final settled = parseAmount(_settled.text);

    if (isEdit) {
      final t = widget.existing!;
      await repo.updateTxn(t.copyWith(
        kind: _kind,
        amount: amount,
        currency: _currency,
        rateToBase: repo.settings.currency(_currency).rateToBase,
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
      ));
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

      // اگر بخشی نقدی پرداخت/دریافت شد، جداگانه ثبت می‌شود
      if (_needsCategory && _customer != null && settled > 0) {
        await repo.addTxn(repo.buildTxn(
          kind: _kind == TxnKind.income ? TxnKind.receive : TxnKind.refund,
          amount: settled,
          currency: _settleCurrency,
          date: _date,
          customerId: _customer!.id,
          subscriptionId: _subscription?.id,
          note: _kind == TxnKind.income ? 'دریافت نقدی' : 'پرداخت نقدی',
          scope: _scope,
        ));
      }
    }
    if (!mounted) return;
    showSnack(context, isEdit ? 'تراکنش ویرایش شد' : 'تراکنش ثبت شد');
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final currencies = repo.settings.currencies;
    final showSettle = !isEdit && _needsCategory && _customer != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'ویرایش تراکنش' : 'ثبت تراکنش'),
        actions: [
          if (isEdit)
            IconButton(
              tooltip: 'حذف',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final ok = await confirmDialog(context,
                    title: 'حذف تراکنش', message: 'این تراکنش حذف شود؟', danger: true, okLabel: 'حذف');
                if (!ok) return;
                await repo.deleteTxn(widget.existing!.id);
                if (!context.mounted) return;
                Navigator.pop(context);
                showSnack(context, 'تراکنش حذف شد');
              },
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            // نوع تراکنش
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
            // حوزه: کسب‌وکار یا شخصی
            SegmentedButton<TxnScope>(
              segments: [
                for (final sc in TxnScope.values)
                  ButtonSegment(value: sc, label: Text(sc.label)),
              ],
              selected: {_scope},
              onSelectionChanged: (s) => setState(() {
                _scope = s.first;
                final list = repo.categoriesOf(_kind, scope: _scope);
                if (_category != null &&
                    !list.any((c) => c.id == _category!.id)) {
                  _category =
                      repo.defaultCategoryId(_kind, scope: _scope) == null
                          ? null
                          : repo.categoryById(
                              repo.defaultCategoryId(_kind, scope: _scope));
                }
              }),
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _scope.hint,
              style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.55)),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: AmountField(controller: _amount, label: 'مبلغ', currency: _currency),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 112,
                  child: SelectField<String>(
                    label: 'ارز',
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
                  'معادل با نرخ ${Money.text(repo.settings.currency(_currency).rateToBase)} '
                  '= ${Money.text(parseAmount(_amount.text) * repo.settings.currency(_currency).rateToBase)}',
                  style: TextStyle(
                      fontSize: 11.5,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
              ),
            const SizedBox(height: 14),
            JalaliDateField(label: 'تاریخ', value: _date, onChanged: (d) => setState(() => _date = d)),
            const SizedBox(height: 14),

            // طرف حساب
            Row(
              children: [
                Expanded(
                  child: SelectField<Customer>(
                    label: 'طرف حساب (اختیاری)',
                    icon: Icons.person_outline_rounded,
                    value: _customer,
                    items: repo.activeCustomers,
                    clearable: true,
                    labelOf: (c) => c.name,
                    subOf: (c) => c.phone,
                    searchHint: 'نام مشتری…',
                    sheetTitle: 'انتخاب طرف حساب',
                    onChanged: (c) => setState(() => _customer = c),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'طرف حساب جدید',
                  onPressed: () async {
                    final created = await Navigator.push<Customer>(
                      context,
                      MaterialPageRoute(builder: (_) => const ContactEditPage()),
                    );
                    if (created != null) setState(() => _customer = created);
                  },
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 20),
                ),
              ],
            ),
            if (_needsCategory) ...[
              const SizedBox(height: 14),
              SelectField<Category>(
                label: 'دسته‌بندی',
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
                  title: Text(_kind == TxnKind.income ? 'نسیه (روی حساب مشتری)' : 'نسیه (بدهی ما)',
                      style: const TextStyle(fontSize: 13.5)),
                  subtitle: const Text('اگر خاموش باشد یعنی نقدی پرداخت/دریافت شده است',
                      style: TextStyle(fontSize: 11.5)),
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
                      label: _kind == TxnKind.income ? 'دریافت نقدی همراه' : 'پرداخت نقدی همراه',
                      currency: _settleCurrency,
                      validator: (_) => null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 112,
                    child: SelectField<String>(
                      label: 'ارز',
                      value: _settleCurrency,
                      items: currencies.map((c) => c.code).toList(),
                      labelOf: (c) => Money.symbol(c),
                      onChanged: (c) => setState(() => _settleCurrency = c ?? _settleCurrency),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            AppTextField(controller: _note, label: 'توضیح', icon: Icons.notes_rounded, maxLines: 2),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check_rounded),
              label: Text(isEdit ? 'ذخیره تغییرات' : 'ثبت'),
            ),
          ],
        ),
      ),
    );
  }
}
