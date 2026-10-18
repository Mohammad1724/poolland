import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/format_utils.dart';
import '../core/haptics.dart';
import '../core/jalali_utils.dart';
import '../core/money.dart';
import '../core/platform_info.dart';
import '../core/sms/sms_models.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../data/store.dart';
import 'design.dart';
import 'motion_kit.dart';
import 'forms/contact_edit_page.dart';
import 'forms/transaction_edit_page.dart';
import 'settings_page.dart';
import 'sms_rules_page.dart';
import 'widgets/widgets.dart';

import '../core/localization.dart';
import 'personal_page.dart';
import 'widgets/quick_buttons.dart';

/// ============================================================
///  Bank SMS — review and approval queue
///
///  The app declares no SMS permission (Google Play Protect blocks the
///  install of any APK that does), so a message is added by pasting its
///  text here. It is parsed, but until the user approves it, no transaction
///  is recorded in the ledger.
/// ============================================================
class SmsPage extends StatefulWidget {
  const SmsPage({super.key});

  @override
  State<SmsPage> createState() => _SmsPageState();
}

enum _SmsFilter { all, deposit, withdraw }
enum _HistoryFilter { all, recorded, rejected }

class _SmsPageState extends State<SmsPage> {
  _SmsFilter _filter = _SmsFilter.all;
  _HistoryFilter _historyFilter = _HistoryFilter.all;

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final onSurface = Theme.of(context).colorScheme.onSurface;

    if (!isAndroidPlatform) {
      return Scaffold(
        appBar: AppBar(title: Text('Bank SMS'.tr)),
        body: const EmptyState(
          icon: Icons.sms_outlined,
          title: 'Android only',
          text: 'SMS access is not available on web or desktop. Try this feature on an Android phone.',
        ),
      );
    }

    final all = repo.smsSuggestions;
    final list = switch (_filter) {
      _SmsFilter.all => all,
      _SmsFilter.deposit =>
        all.where((s) => s.direction == SmsDirection.deposit).toList(),
      _SmsFilter.withdraw =>
        all.where((s) => s.direction == SmsDirection.withdraw).toList(),
    };

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Bank SMS'.tr),
          actions: [
            IconButton(
              tooltip: 'Manage recognition rules'.tr,
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SmsRulesPage()),
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                switch (v) {
                  case 'reject_all':
                    final ok = await confirmDialog(
                      context,
                      title: 'Reject all'.tr,
                      message: 'Reject all suggestions? (They will no longer appear, but no transactions will be deleted.)'
                          .tr,
                      okLabel: 'Reject'.tr,
                      danger: true,
                    );
                    if (!ok || !context.mounted) break;
                    final messenger = ScaffoldMessenger.of(context);
                    await repo.rejectAllSms();
                    // The queue empties itself, which can look like a glitch
                    // unless the app says what happened.
                    showMessengerSnack(messenger, 'All suggestions rejected');
                    break;
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'reject_all', child: Text('Reject all'.tr)),
              ],
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(
                text: 'Unregistered ({count})'.trArgs({
                  'count': all.length,
                }),
              ),
              Tab(
                text: 'Review history ({count})'.trArgs({
                  'count': repo.smsHistory.length,
                }),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _pendingTab(context, repo, all, list, onSurface),
            _historyTab(context, repo),
          ],
        ),
      ),
    );
  }

  Widget _pendingTab(
    BuildContext context,
    AppRepository repo,
    List<ParsedSms> all,
    List<ParsedSms> list,
    Color onSurface,
  ) => ListView(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
    children: [
      _summaryCard(context, all.length),
      const SizedBox(height: 10),
      // The only way in: the app has no SMS permission, so a bank message
      // is added by pasting its text.
      SizedBox(
        width: double.infinity,
        child: FilledButton.tonalIcon(
          onPressed: () => _importSms(context, repo),
          icon: const Icon(Icons.content_paste_rounded, size: 18),
          label: Text('Add from SMS text'.tr),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          _chip('All', _SmsFilter.all, all.length),
          const SizedBox(width: 8),
          _chip(
            'Deposit',
            _SmsFilter.deposit,
            all.where((s) => s.direction == SmsDirection.deposit).length,
          ),
          const SizedBox(width: 8),
          _chip(
            'Withdrawal',
            _SmsFilter.withdraw,
            all.where((s) => s.direction == SmsDirection.withdraw).length,
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (list.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 40),
          child: const EmptyState(
            icon: Icons.sms_outlined,
            title: 'No items found',
            text: 'No messages yet. Paste a bank SMS above to review it.',
          ),
        )
      else
        for (final (i, sms) in list.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SlipIn(index: i, child: _SmsCard(sms: sms, onSurface: onSurface)),
          ),
    ],
  );

  /// Asks for a pasted bank message and queues it for review.
  ///
  /// Every outcome gets its own message: a queued card is visible, but a
  /// duplicate or a non-transaction paste must say why nothing appeared.
  Future<void> _importSms(BuildContext context, AppRepository repo) async {
    final text = await showLedgerSheet<String>(
      context,
      builder: (_) => const _ImportSmsSheet(),
    );
    if (text == null || !context.mounted) return;
    final result = repo.importSmsText(text);
    if (!context.mounted) return;
    switch (result) {
      case SmsImportResult.added:
        showSnack(context, 'SMS added to review');
        break;
      case SmsImportResult.duplicate:
        showSnack(
          context,
          'This message is already in the review queue',
          error: true,
        );
        break;
      case SmsImportResult.notRecognized:
        showSnack(
          context,
          'No transaction found in this text',
          error: true,
        );
        break;
    }
  }

  Widget _historyTab(BuildContext context, AppRepository repo) {
    final history = repo.smsHistory;
    final visible = switch (_historyFilter) {
      _HistoryFilter.all => history,
      _HistoryFilter.recorded => history.where((e) => e.wasRecorded).toList(),
      _HistoryFilter.rejected => history.where((e) => e.wasRejected).toList(),
    };

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
      children: [
        CardBox(
          child: Text(
            'Reviewed SMS history is kept in this app’s storage and omitted from its export/restore files. Recorded entries can be opened from here; rejected messages do not create transactions. Older status-only records may not be displayable.'
                .tr,
            style: TextStyle(
              fontSize: 12,
              height: 1.6,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.68),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _historyChip('All', _HistoryFilter.all, history.length),
            _historyChip(
              'Recorded',
              _HistoryFilter.recorded,
              history.where((e) => e.wasRecorded).length,
            ),
            _historyChip(
              'Rejected',
              _HistoryFilter.rejected,
              history.where((e) => e.wasRejected).length,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 35),
            child: EmptyState(
              icon: Icons.history_rounded,
              title: 'No review history yet',
              text: 'Approved or rejected SMS messages will appear here.',
            ),
          )
        else
          for (final entry in visible)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SmsHistoryCard(entry: entry),
            ),
      ],
    );
  }

  Widget _historyChip(String label, _HistoryFilter filter, int count) =>
      ChoiceChip(
        label: Text('${label.tr} ($count)'),
        showCheckmark: false,
        selected: _historyFilter == filter,
        onSelected: (_) => setState(() => _historyFilter = filter),
      );

  Widget _chip(String label, _SmsFilter f, int count) => ChoiceChip(
    label: Text(count > 0 ? '${label.tr} ($count)' : label.tr),
    showCheckmark: false,
    selected: _filter == f,
    onSelected: (_) => setState(() => _filter = f),
  );

  Widget _summaryCard(BuildContext context, int count) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final subtitle =
        'Poolland never reads your SMS. Paste a bank SMS to review it.'.tr;
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.sms_rounded, size: 18),
              const SizedBox(width: 8),
              Text(
                count > 0
                    ? '{count} transactions awaiting review'.trArgs({
                        'count': count,
                      })
                    : 'Nothing awaiting review'.tr,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11.5,
              color: onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

}

/// ---------------- SMS card ----------------
class _SmsCard extends StatelessWidget {
  const _SmsCard({required this.sms, required this.onSurface});

  final ParsedSms sms;
  final Color onSurface;

  Color get _color => switch (sms.direction) {
    SmsDirection.deposit => const Color(0xFF16A34A),
    SmsDirection.withdraw => const Color(0xFFE11D48),
    SmsDirection.unknown => const Color(0xFFF59E0B),
  };

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();
    final matched = repo.matchCustomerForSms(sms);

    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  sms.direction == SmsDirection.deposit
                      ? Icons.call_received_rounded
                      : Icons.call_made_rounded,
                  size: 18,
                  color: _color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (sms.bankName ??
                              (sms.manual ? 'Pasted message' : 'Unknown bank'))
                          .tr,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${J.d(sms.message.date)} · ${Fmt.clock(sms.message.date)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${sms.direction == SmsDirection.deposit ? '+' : '−'}'
                    '${Money.text(sms.amount, currency: sms.currency)}',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: _color,
                    ),
                  ),
                  const SizedBox(height: 3),
                  TagChip(sms.direction.label, color: _color, dense: true),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (sms.cardMask != null)
                TagChip(
                  'Card {card}'.trArgs({'card': sms.cardMask}),
                  color: const Color(0xFF7C3AED),
                  dense: true,
                ),
              if (sms.reference != null)
                TagChip(
                  'Reference {reference}'.trArgs({'reference': sms.reference}),
                  color: const Color(0xFF0F766E),
                  dense: true,
                ),
              if (sms.balance != null)
                TagChip(
                  'Balance {balance}'.trArgs({
                    'balance': Money.text(sms.balance!, compact: true),
                  }),
                  color: const Color(0xFF2563EB),
                  dense: true,
                ),
            ],
          ),
          if (matched != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.person_outline_rounded, size: 15),
                const SizedBox(width: 5),
                Text(
                  matched.name,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '(Auto-matched)'.tr,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Text(
            sms.message.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.6,
              color: onSurface.withValues(alpha: 0.6),
            ),
          ),
          if (sms.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              sms.note,
              style: const TextStyle(fontSize: 10.5, color: Color(0xFFB45309)),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  // Rejecting removes the card from the queue, so without a
                  // word it looks like the card vanished. Say so.
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await repo.rejectSms(sms);
                    showMessengerSnack(messenger, 'SMS rejected');
                  },
                  icon: const Icon(Icons.close_rounded, size: 17),
                  label: Text('Reject'.tr),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () => _openReview(context, sms, matched),
                  icon: const Icon(Icons.check_rounded, size: 17),
                  label: Text(
                    (matched == null ? 'Review and record' : 'Confirm').tr,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openReview(
    BuildContext context,
    ParsedSms sms,
    Customer? matched,
  ) async {
    final ok = await showLedgerSheet<bool>(
      context,
      builder: (ctx) => SmsReviewSheet(sms: sms, initialCustomer: matched),
    );
    if (ok == true && context.mounted) {
      showSnack(context, 'Transaction recorded from SMS');
    }
  }
}

class _SmsHistoryCard extends StatelessWidget {
  const _SmsHistoryCard({required this.entry});

  final SmsHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final recorded = entry.wasRecorded;
    final statusColor = recorded
        ? const Color(0xFF16A34A)
        : const Color(0xFF64748B);
    final directionColor = entry.direction == SmsDirection.deposit
        ? const Color(0xFF16A34A)
        : const Color(0xFFE11D48);
    final title = entry.bankName?.isNotEmpty == true
        ? entry.bankName!.tr
        : entry.message.address.isNotEmpty
        ? entry.message.address
        : 'Pasted message'.tr;
    Txn? transaction;
    if (entry.transactionId != null) {
      for (final item in context.read<AppRepository>().transactions) {
        if (item.id == entry.transactionId) {
          transaction = item;
          break;
        }
      }
    }
    final transactionToOpen = transaction;

    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                recorded ? Icons.check_circle_outline : Icons.block_outlined,
                color: statusColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty ? 'Unknown sender'.tr : title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Received {received} · reviewed {reviewed}'.trArgs({
                        'received': '${J.d(entry.message.date)} · ${Fmt.clock(entry.message.date)}',
                        'reviewed': '${J.d(entry.reviewedAt)} · ${Fmt.clock(entry.reviewedAt)}',
                      }),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              if (entry.amount > 0)
                Text(
                  '${entry.direction == SmsDirection.deposit ? '+' : '−'}'
                  '${Money.text(entry.amount, currency: entry.currency)}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: directionColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              TagChip(
                recorded ? 'Recorded'.tr : 'Rejected'.tr,
                color: statusColor,
                dense: true,
              ),
              if (entry.direction != SmsDirection.unknown)
                TagChip(entry.direction.label, color: directionColor, dense: true),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            entry.message.body,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.55,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.68),
            ),
          ),
          if (entry.transactionId != null) ...[
            const SizedBox(height: 6),
            if (transactionToOpen != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TransactionEditPage(
                        existing: transactionToOpen,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text('Open transaction'.tr),
                ),
              )
            else
              Row(
                children: [
                  const Icon(Icons.receipt_long_outlined, size: 15),
                  const SizedBox(width: 5),
                  Text(
                    'Transaction recorded'.tr,
                    style: const TextStyle(fontSize: 10.5),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

/// ---------------- Review or edit before recording ----------------
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

  /// The sheet opens ready to save: the section is business, and kind +
  /// category follow the section, so the record button is enabled immediately.
  ///
  /// Business is a fixed default, not a guess. This used to fall back to
  /// `repo.transactions.first.scope` — the scope of whichever entry happened
  /// to be newest — and since the personal page is the app's landing tab with
  /// one-tap quick buttons, that newest entry is very often personal. The
  /// sheet would then open a *bank deposit* on «personal» with no contact,
  /// still one tap from being recorded, and business income would quietly
  /// leave the profit report. A predictable default the user can see and flip
  /// (the [ScopeSegment] sits right under the kind tiles) beats a plausible
  /// one they have no reason to check.
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
    _customer = widget.initialCustomer;
    _amount = TextEditingController(
      text: groupedNumber(
        widget.sms.amount,
        decimals: Money.decimals(widget.sms.currency),
      ),
    );
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

  void _changeScope(AppRepository repo, TxnScope scope) {
    if (_scope == scope) return;
    setState(() {
      _scope = scope;
      _customer = scope == TxnScope.business ? widget.initialCustomer : null;
      _kind = _suggestedKind(repo, scope);
      _categoryId = _suggestedCategoryId(repo, scope);
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  /// Same one-tap selection as the main entry form: the contact chip is
  /// the frequent regular, a second tap clears it.
  Widget _contactChip(Customer c) {
    final selected = _customer?.id == c.id;
    return PresetChip(
      icon: Icons.person_outline_rounded,
      label: c.name,
      selected: selected,
      onTap: () {
        Haptics.selection();
        setState(() => _customer = selected ? null : c);
      },
    );
  }

  /// The full, searchable contact sheet behind the "all contacts" chip.
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

  /// Create the contact inline and select it, like the main entry form.
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

  /// "+ quick button" means pinning one of the existing categories: the
  /// choice happens in the same searchable list, no name typing.
  Future<void> _addQuickFromCategory(TxnScope scope) async {
    final repo = context.read<AppRepository>();
    final categoryKind = _categoryKind(_kind);
    if (categoryKind == null) {
      await _openQuickEdit(scope);
      return;
    }
    final all = repo.categoriesOf(categoryKind, scope: scope);
    if (all.isEmpty) {
      await _openQuickEdit(scope);
      return;
    }
    final res = await showPickSheet<Category>(
      context,
      title: 'Choose a category for the button',
      items: repo.pickOrderCategories(categoryKind, scope: scope),
      current: null,
      labelOf: (c) => c.name,
      searchHint: 'Category name...',
      isChild: (c) => c.parentId != null,
    );
    if (res == null || res.value == null) return;
    final c = res.value!;
    if (!mounted) return;
    if (repo.quickExpenses.any((q) => q.categoryId == c.id)) {
      // A rejection, not a confirmation: it says the tap did nothing, so it
      // has to look like a warning rather than a green tick.
      showSnack(
        context,
        'This category is already a quick button',
        error: true,
      );
      return;
    }
    Haptics.selection();
    await repo.addQuickButton(QuickExpense(
      id: LocalStore.newId(),
      label: c.name,
      kind: c.kind,
      scope: scope,
      categoryId: c.id,
      iconCodePoint: 0,
      sortOrder: repo.quickExpenses.isEmpty
          ? 0
          : repo.quickExpenses.last.sortOrder + 1,
    ));
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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      // The ledger-sheet route keeps the sheet clear of the soft keyboard.
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SheetHandle(),
            const SizedBox(height: 14),
            Text(
              'Record this SMS transaction'.tr,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              sms.bankName?.tr ??
                  (sms.message.address.isNotEmpty
                      ? sms.message.address
                      : 'Pasted message'.tr),
              style: TextStyle(
                fontSize: 11.5,
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 16),
            // The same intent zone as the main entry form: the color-coded
            // kind tiles (restricted to what this SMS can become), then the
            // business/personal segment.
            TxnKindStrip(
              kinds: availableKinds,
              selected: _kind,
              onSelect: (k) => setState(() {
                _kind = k;
                _categoryId = _suggestedCategoryId(repo, scope);
              }),
            ),
            const SizedBox(height: 10),
            ScopeSegment(
              selected: scope,
              onSelect: (s) => _changeScope(repo, s),
            ),
            const SizedBox(height: 14),
            // Quick-entry buttons for this section and direction: one tap
            // sets the type/category here, the chip adds a new button.
            QuickButtonsRow(
              scopeFilter: scope,
              incomeFilter: sms.direction == SmsDirection.deposit,
              hideWhenEmpty: true,
              onTap: (q) => setState(() {
                if (availableKinds.contains(q.kind)) _kind = q.kind;
                if (q.categoryId != null) _categoryId = q.categoryId;
              }),
              onLongPress: (q) => _openQuickEdit(scope, q),
              trailing: ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 16),
                label: Text('Quick button'.tr),
                onPressed: () => _addQuickFromCategory(scope),
              ),
            ),
            const SizedBox(height: 14),
            AmountField(
              controller: _amount,
              label: 'Amount'.tr,
              currency: sms.currency,
            ),
            if (scope == TxnScope.business) ...[
              const SizedBox(height: 16),
              SectionCaption('Contact (optional)'),
              const SizedBox(height: 6),
              ChipStrip(chips: [
                for (final c in repo.topCustomers(limit: 3)) _contactChip(c),
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
              ]),
              if (_customer != null)
                ContactBalanceCard(
                  customer: _customer!,
                  balance: repo.balanceOf(_customer!),
                ),
            ],
            if (categoryKind != null) ...[
              const SizedBox(height: 16),
              // Every category lives in one searchable list — frequent ones
              // lead, so a long catalog is never a scrolling hunt.
              SelectField<Category>(
                label: 'Category',
                icon: Icons.category_outlined,
                value:
                    categories.where((c) => c.id == _categoryId).firstOrNull,
                items: categories,
                labelOf: (c) => c.name,
                searchHint: 'Category name...',
                sheetTitle: 'Select category',
                isChild: (c) => c.parentId != null,
                extraActionLabel: 'Manage',
                onExtraAction: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CategoriesPage(),
                  ),
                ),
                onChanged: (c) {
                  Haptics.selection();
                  setState(() => _categoryId = c?.id);
                },
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel'.tr),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: () async {
                      final value = parseAmount(_amount.text);
                      if (value <= 0) {
                        showSnack(
                          context,
                          'Enter an amount',
                          error: true,
                        );
                        return;
                      }
                      await repo.approveSms(
                        sms,
                        customer: _customer,
                        kind: _kind,
                        categoryId: _categoryId,
                        amount: value,
                        scope: scope,
                      );
                      if (context.mounted) {
                        // Coin + stamp: the money-landed moment.
                        MoneyCelebration.recorded(context);
                        Navigator.pop(context, true);
                      }
                    },
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: Text('Record transaction'.tr),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Sheet for handing a bank message to the parser without SMS permission.
///
/// Both builds get it: the safe build has no other way in, and the full build
/// gives a user who denied the permission (or is reading one message right
/// now) a way to record it without changing system settings.
class _ImportSmsSheet extends StatefulWidget {
  const _ImportSmsSheet();

  @override
  State<_ImportSmsSheet> createState() => _ImportSmsSheetState();
}

class _ImportSmsSheetState extends State<_ImportSmsSheet> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty || !mounted) return;
    setState(() {
      _text.text = text;
      _text.selection = TextSelection.collapsed(offset: text.length);
    });
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final canAdd = _text.text.trim().isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SheetHandle(),
            const SizedBox(height: 16),
            Text(
              'Add from SMS text'.tr,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Copy a bank SMS and paste it here. It is parsed on this device and only added to the review queue.'
                  .tr,
              style: TextStyle(
                fontSize: 12,
                height: 1.7,
                color: onSurface.withValues(alpha: 0.65),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              autofocus: true,
              minLines: 4,
              maxLines: 8,
              textAlignVertical: TextAlignVertical.top,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Bank SMS text'.tr,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _paste,
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: Text('Paste'.tr),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: canAdd
                      ? () => Navigator.pop(context, _text.text.trim())
                      : null,
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: Text('Add to review'.tr),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
