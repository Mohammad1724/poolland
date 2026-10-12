import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/haptics.dart';
import '../core/notifications/notify.dart';
import '../core/sms/sms_models.dart';
import '../core/sms/sms_service.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'customers_page.dart';
import 'widgets/widgets.dart';
import 'gesture_tour.dart';
import 'dashboard_page.dart';
import 'design.dart';
import 'motion_kit.dart';
import 'forms/contact_edit_page.dart';
import 'forms/sell_subscription_page.dart';
import 'forms/transaction_edit_page.dart';
import 'personal_page.dart';
import 'reports_page.dart';
import 'settings_page.dart';
import 'sms_page.dart';
import 'subscriptions_page.dart';
import 'transactions_page.dart';
import 'widgets/ledger_nav_bar.dart';

import '../core/localization.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _index = 0;

  /// Which way the last tab change went, so the incoming page slides in from
  /// the matching side (mirrored in RTL).
  bool _dirForward = true;

  // --- FAB speed dial (long-press) ---
  OverlayEntry? _dialEntry;
  final ValueNotifier<int> _dialHighlight = ValueNotifier<int>(-1);
  List<_DialItem> _dialItems = const [];
  Offset _dialOrigin = Offset.zero;
  Size _dialSize = Size.zero;

  /// Tab indexes that have been opened at least once.
  ///
  /// Building all five pages up front made the first frame do the work of
  /// five screens (lists, charts, and summaries). Only the tabs the user has
  /// actually opened are mounted now.
  final Set<int> _visited = {0};

  /// Whether the floating action button is currently on screen.
  ///
  /// A notifier rather than plain state: scrolling flips it many times a
  /// second, and only the button needs to rebuild, not the whole shell.
  final ValueNotifier<bool> _fabVisible = ValueNotifier<bool>(true);

  /// One controller per tab, created the first time that tab is built.
  ///
  /// They exist for a single gesture: tapping the tab that is already open
  /// scrolls its list back to the top, which is what people expect from a
  /// bottom bar (and saves a lot of flicking to get back to the top of a long
  /// list).
  final Map<int, ScrollController> _scrollControllers = {};

  // Personal bookkeeping is the first destination because it is the most
  // frequent task; business tools remain one tap away.
  static const _titles = [
    'Personal',
    'Dashboard',
    'Customers',
    'Subscriptions',
    'Transactions',
  ];

  /// The repository this shell reports new SMS messages to.
  AppRepository? _repo;

  @override
  void dispose() {
    _closeDial();
    _dialHighlight.dispose();
    WidgetsBinding.instance.removeObserver(this);
    // The repository and the SMS channel outlive this shell, so they must
    // not keep callbacks that hold a dead BuildContext.
    _repo?.onNewSmsSuggestion = null;
    SmsService.onOpenRoute = null;
    _fabVisible.dispose();
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The native SMS receiver stays quiet while the app is visible (the
    // review queue and a snackbar cover that case) and posts a system
    // notification otherwise.
    SmsService.setForeground(state == AppLifecycleState.resumed);
    // Coming back from the system settings or a permission dialog: the
    // granted state may have changed without us asking here.
    if (state == AppLifecycleState.resumed) {
      final repo = _repo;
      if (repo != null && repo.isReady) {
        repo.refreshNotificationPermission();
        if (repo.settings.smsEnabled) repo.refreshSmsPermission();
      }
    }
  }

  /// Returns the controller for a tab, creating it on first use so an unopened
  /// tab never allocates one.
  ScrollController _controllerFor(int index) =>
      _scrollControllers.putIfAbsent(index, ScrollController.new);

  @override
  void initState() {
    super.initState();
    // First run after an update: teach the gestures once, with animation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowGestureTour(context);
    });
    WidgetsBinding.instance.addObserver(this);
    // Set synchronously: a notification tap can arrive over the channel at
    // any moment once the engine is alive.
    SmsService.onOpenRoute = _handleOpenRoute;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final repo = context.read<AppRepository>();
      _repo = repo;
      repo.onNewSmsSuggestion = _onNewSmsSuggestion;
      if (!repo.isReady) await repo.init();

      // Automatically post due recurring transactions (rent, internet, and so on).
      // Errors here must never prevent the app from starting.
      try {
        await repo.postDueRecurring();
      } catch (_) {
        // Ignore the error; the user can try again later.
      }

      // Schedule the daily reminder only when enabled by the user.
      await repo.scheduleDailyReminder();

      // Initialize the SMS receiver and perform the initial sync (Android only).
      repo.initSms();
      await repo.refreshSmsPermission();
      if (repo.smsPermissionGranted &&
          repo.settings.smsEnabled &&
          repo.smsSuggestions.isEmpty) {
        await repo.syncSms();
      }

      // Android 13+ gates notifications behind a runtime permission. Asking
      // again after a denial returns silently, so this is safe every launch.
      // Not gated on the SMS permission: the daily reminder needs this too,
      // and a restored backup may enable notifications on a fresh install.
      if (repo.settings.smsNotify || repo.settings.dailyReminder) {
        await reminder.requestPermission();
        await repo.refreshNotificationPermission();
      }

      // Opened by tapping a bank-SMS arrival notification? Go straight to
      // the review sheet of that exact SMS instead of making the user
      // find it in the queue.
      final pending = await SmsService.consumePendingRoute();
      if (!mounted || pending == null) return;
      await _openSmsReview(pending);
    });
  }

  /// Native push for the warm-start case (engine alive, app brought
  /// forward by a notification tap).
  void _handleOpenRoute(String route, int? date, String? address) {
    if (!mounted || route != 'sms_review') return;
    _openSmsReview({'route': route, 'date': date, 'address': address});
  }

  /// Notification tap: open the record sheet of that exact SMS right here,
  /// over whatever page the user is on — never the review queue. Only when
  /// the message cannot be found at all does the queue open as a fallback.
  Future<void> _openSmsReview(Map<String, Object?> pending) async {
    if (pending['route'] != 'sms_review') return;
    final repo = context.read<AppRepository>();
    final date = (pending['date'] as num?)?.toInt();
    final address = pending['address'] as String?;

    SmsSuggestion? exact() {
      if (date == null) return null;
      final hits = repo.smsSuggestions
          .where(
            (s) =>
                s.message.date.millisecondsSinceEpoch == date &&
                (address == null || s.message.address == address),
          )
          .toList();
      return hits.isEmpty ? null : hits.first;
    }

    SmsSuggestion? bySender() {
      if (address == null) return null;
      final hits = repo.smsSuggestions
          .where((s) => s.message.address == address)
          .toList();
      return hits.isEmpty ? null : hits.first;
    }

    var target = exact() ?? bySender();
    if (target == null &&
        repo.smsPermissionGranted &&
        repo.settings.smsEnabled) {
      // Incremental scan (only messages newer than the last sync), so the
      // sheet appears quickly even when the queue did not have it yet.
      try {
        await repo.syncSms();
      } catch (_) {
        // A failed scan falls through to the queue fallback below.
      }
      if (!mounted) return;
      target = exact() ?? bySender();
    }
    if (!mounted) return;

    if (target == null) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const SmsPage()),
      );
    } else {
      final chosen = target;
      final matched = repo.matchCustomerForSms(chosen);
      final ok = await showLedgerSheet<bool>(
        context,
        builder: (ctx) => SmsReviewSheet(sms: chosen, initialCustomer: matched),
      );
      if (ok == true && mounted) {
        showSnack(context, 'Transaction recorded from SMS');
      }
    }
    // The native side keeps the tap request until it is consumed; consuming
    // here also clears a warm-start request so a later cold start does not
    // reopen an already reviewed message.
    await SmsService.consumePendingRoute();
  }

  /// Foreground counterpart of the native arrival notification: points at
  /// the review queue the moment a new bank SMS lands in it.
  void _onNewSmsSuggestion() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('New bank SMS — review and record it'.tr),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Review SMS'.tr,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SmsPage()),
            ),
          ),
        ),
      );
  }

  void _goTo(int i) {
    Haptics.selection();
    // Tapping the tab that is already open means "take me back to the top".
    if (i == _index) {
      _scrollToTop(i);
      return;
    }
    final forward = i > _index;
    setState(() {
      _index = i;
      _dirForward = forward;
      // Tabs are built the first time they are opened; from then on they stay
      // mounted, so their scroll position and filters survive switching.
      _visited.add(i);
      // A freshly opened tab may be scrolled to the top, so show the action
      // button again.
      _fabVisible.value = true;
    });
  }

  /// Scrolls a tab back to the top, if that tab has a list and is mounted.
  void _scrollToTop(int i) {
    final controller = _scrollControllers[i];
    if (controller == null || !controller.hasClients) {
      // Nothing to scroll: the tab was never opened, or its list is shorter
      // than the screen. Bring the action button back either way.
      _fabVisible.value = true;
      return;
    }
    final duration = Motion.adaptive(context, Motion.quick);
    if (duration == Duration.zero) {
      controller.jumpTo(0);
    } else {
      controller.animateTo(0, duration: duration, curve: Curves.easeOut);
    }
    _fabVisible.value = true;
  }

  /// Hides the floating action button while scrolling down, shows it while
  /// scrolling up. Scroll notifications bubble up from whichever list is
  /// currently visible, so no page has to know about this.
  bool _handleScroll(ScrollNotification notification) {
    // Hiding a persistent action while a screen reader or switch-access user
    // explores the list makes that action difficult to discover and reach.
    if (MediaQuery.maybeOf(context)?.accessibleNavigation ?? false) {
      if (!_fabVisible.value) _fabVisible.value = true;
      return false;
    }
    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      if (delta > 4 && _fabVisible.value) {
        _fabVisible.value = false;
      } else if (delta < -4 && !_fabVisible.value) {
        _fabVisible.value = true;
      }
    }
    // Never absorb the notification: charts and nested lists still need it.
    return false;
  }

  Widget _buildFab() {
    final compact = MediaQuery.sizeOf(context).width < 360;
    if (_index == 2) {
      if (compact) {
        return FloatingActionButton(
          tooltip: 'New customer'.tr,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ContactEditPage()),
          ),
          child: const Icon(Icons.person_add_alt_1_rounded),
        );
      }
      return FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ContactEditPage()),
        ),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: Text('New customer'.tr),
      );
    }
    if (_index == 0) {
      if (compact) {
        return FloatingActionButton(
          tooltip: 'Add personal entry'.tr,
          onPressed: _personalAdd,
          child: const Icon(Icons.add_rounded),
        );
      }
      return FloatingActionButton.extended(
        onPressed: _personalAdd,
        icon: const Icon(Icons.add_rounded),
        label: Text('Add personal entry'.tr),
      );
    }
    if (_index == 3) {
      if (compact) {
        return FloatingActionButton(
          tooltip: 'Sell a subscription'.tr,
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SellSubscriptionPage()),
          ),
          child: const Icon(Icons.vpn_key_rounded),
        );
      }
      return FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SellSubscriptionPage()),
        ),
        icon: const Icon(Icons.vpn_key_rounded),
        label: Text('Sell a subscription'.tr),
      );
    }
    return FloatingActionButton(
      onPressed: _quickAdd,
      tooltip: 'Quick add'.tr,
      child: const Icon(Icons.add_rounded),
    );
  }

  /// Opens the sale form filled in with the last sale's customer and plan, so
  /// selling the same thing again is two taps instead of filling a form.
  Future<void> _repeatLastSale() async {
    final repo = context.read<AppRepository>();
    Subscription? last;
    for (final s in repo.subscriptions) {
      if (last == null || s.createdAt.isAfter(last.createdAt)) last = s;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SellSubscriptionPage(
          contact: last == null ? null : repo.customerById(last.customerId),
          plan: last == null ? null : repo.planById(last.planId),
        ),
      ),
    );
  }

  Future<void> _personalAdd() async {
    final choice = await showLedgerSheet<String>(
      context,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SheetHandle(),
              const SizedBox(height: 16),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  'Add personal entry'.tr,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _menuTile(
                ctx,
                'Personal expense',
                Icons.remove_circle_outline_rounded,
                'p_expense',
              ),
              _menuTile(
                ctx,
                'Personal income',
                Icons.add_circle_outline_rounded,
                'p_income',
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    final kind = choice == 'p_expense' ? TxnKind.expense : TxnKind.income;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionEditPage(
          initialKind: kind,
          initialScope: TxnScope.personal,
        ),
      ),
    );
  }

  Future<void> _quickAdd() async {
    final choice = await showLedgerSheet<String>(
      context,
      builder: (ctx) => SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(ctx).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.82,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SheetHandle(),
                  const SizedBox(height: 16),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'What would you like to do?'.tr,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'VPN business'.tr,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  _menuTile(
                    ctx,
                    'Sell a subscription',
                    Icons.vpn_key_rounded,
                    'sale_sub',
                  ),
                  _menuTile(
                    ctx,
                    'Record income (no subscription)',
                    Icons.trending_up_rounded,
                    'income',
                  ),
                  _menuTile(
                    ctx,
                    'Receive from customer',
                    Icons.call_received_rounded,
                    'receive',
                  ),
                  _menuTile(
                    ctx,
                    'Record expense',
                    Icons.trending_down_rounded,
                    'expense',
                  ),
                  _menuTile(
                    ctx,
                    'Payment / refund',
                    Icons.call_made_rounded,
                    'refund',
                  ),
                  const Divider(height: 16),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      'Personal'.tr,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  _menuTile(
                    ctx,
                    'Personal expense',
                    Icons.person_outline_rounded,
                    'p_expense',
                  ),
                  _menuTile(
                    ctx,
                    'Personal income',
                    Icons.savings_outlined,
                    'p_income',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!mounted || choice == null) return;
    await _runChoice(choice);
  }

  /// Shared destination for the quick-add sheet and the FAB speed dial:
  /// every choice opens the matching form.
  Future<void> _runChoice(String choice) async {
    switch (choice) {
      case 'sale_sub':
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SellSubscriptionPage()),
        );
        break;
      case 'income':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const TransactionEditPage(initialKind: TxnKind.income),
          ),
        );
        break;
      case 'receive':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const TransactionEditPage(initialKind: TxnKind.receive),
          ),
        );
        break;
      case 'expense':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const TransactionEditPage(initialKind: TxnKind.expense),
          ),
        );
        break;
      case 'p_expense':
      case 'p_income':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TransactionEditPage(
              initialKind: choice == 'p_expense'
                  ? TxnKind.expense
                  : TxnKind.income,
              initialScope: TxnScope.personal,
            ),
          ),
        );
        break;
      case 'new_customer':
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ContactEditPage()),
        );
        break;
      case 'refund':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                const TransactionEditPage(initialKind: TxnKind.refund),
          ),
        );
        break;
    }
  }

  // ---------------- FAB speed dial ----------------

  List<_DialItem> _dialItemsFor() => switch (_index) {
    0 => const [
      _DialItem(
        'p_expense',
        Icons.person_outline_rounded,
        'Personal expense',
        Color(0xFFE11D48),
      ),
      _DialItem(
        'p_income',
        Icons.savings_outlined,
        'Personal income',
        Color(0xFF16A34A),
      ),
    ],
    2 => const [
      _DialItem(
        'new_customer',
        Icons.person_add_alt_1_rounded,
        'New customer',
        Color(0xFF2563EB),
      ),
      _DialItem(
        'receive',
        Icons.call_received_rounded,
        'Receive from customer',
        Color(0xFF0F766E),
      ),
      _DialItem(
        'expense',
        Icons.trending_down_rounded,
        'Record expense',
        Color(0xFFE11D48),
      ),
    ],
    3 => const [
      _DialItem(
        'sale_sub',
        Icons.vpn_key_rounded,
        'Sell a subscription',
        Color(0xFF7C3AED),
      ),
      _DialItem(
        'receive',
        Icons.call_received_rounded,
        'Receive from customer',
        Color(0xFF0F766E),
      ),
      _DialItem(
        'expense',
        Icons.trending_down_rounded,
        'Record expense',
        Color(0xFFE11D48),
      ),
    ],
    _ => const [
      _DialItem(
        'income',
        Icons.trending_up_rounded,
        'Record income (no subscription)',
        Color(0xFF16A34A),
      ),
      _DialItem(
        'receive',
        Icons.call_received_rounded,
        'Receive from customer',
        Color(0xFF0F766E),
      ),
      _DialItem(
        'expense',
        Icons.trending_down_rounded,
        'Record expense',
        Color(0xFFE11D48),
      ),
      _DialItem(
        'refund',
        Icons.call_made_rounded,
        'Payment / refund',
        Color(0xFFD97706),
      ),
      _DialItem(
        'sale_sub',
        Icons.vpn_key_rounded,
        'Sell a subscription',
        Color(0xFF7C3AED),
      ),
    ],
  };

  void _onFabLongPressStart(LongPressStartDetails d) {
    final items = _dialItemsFor();
    if (items.isEmpty) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    Haptics.confirm();
    _dialItems = items;
    _dialOrigin = d.globalPosition;
    _dialSize = MediaQuery.sizeOf(context);
    _dialHighlight.value = -1;
    _dialEntry = OverlayEntry(
      builder: (_) => _SpeedDialLayer(
        origin: _dialOrigin,
        size: _dialSize,
        items: _dialItems,
        highlight: _dialHighlight,
        onBarrier: _closeDial,
        onPick: (i) {
          final value = _dialItems[i].value;
          _closeDial();
          if (mounted) _runChoice(value);
        },
      ),
    );
    overlay.insert(_dialEntry!);
  }

  void _onFabLongPressMove(LongPressMoveUpdateDetails d) {
    if (_dialEntry == null) return;
    var hit = -1;
    for (var i = 0; i < _dialItems.length; i++) {
      final slot = _dialSlot(i, _dialItems.length, _dialOrigin, _dialSize);
      if ((slot - d.globalPosition).distance < 58) {
        hit = i;
        break;
      }
    }
    if (hit != _dialHighlight.value) {
      _dialHighlight.value = hit;
      if (hit >= 0) Haptics.selection();
    }
  }

  void _onFabLongPressEnd(LongPressEndDetails d) {
    final hi = _dialHighlight.value;
    final items = _dialItems;
    _closeDial();
    if (hi >= 0 && hi < items.length && mounted) {
      _runChoice(items[hi].value);
    }
  }

  void _closeDial() {
    _dialEntry?.remove();
    _dialEntry = null;
    _dialHighlight.value = -1;
  }

  Widget _menuTile(
    BuildContext ctx,
    String title,
    IconData icon,
    String value,
  ) => Material(
    color: Colors.transparent,
    child: ListTile(
      leading: Container(
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 18, color: Theme.of(ctx).colorScheme.primary),
      ),
      title: Text(title.tr),
      trailing: const Icon(Icons.chevron_right_rounded, size: 18),
      onTap: () => Navigator.pop(ctx, value),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // Only readiness is needed here; watching the whole repository would
    // rebuild the shell (and therefore every open tab) on each data change.
    final isReady = context.select<AppRepository, bool>((r) => r.isReady);
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 840;
    final isExtended = width >= 1120;
    final pages = <Widget>[
      PersonalPage(onNavigate: _goTo, controller: _controllerFor(0)),
      DashboardPage(onNavigate: _goTo, controller: _controllerFor(1)),
      CustomersPage(controller: _controllerFor(2)),
      SubscriptionsPage(controller: _controllerFor(3)),
      TransactionsPage(controller: _controllerFor(4)),
    ];
    final content = !isReady
        ? const Center(child: CircularProgressIndicator())
        : IndexedStack(
            index: _index,
            children: [
              for (var i = 0; i < pages.length; i++)
                if (_visited.contains(i))
                  _TabPane(
                    active: _index == i,
                    forward: _dirForward,
                    child: pages[i],
                  )
                else
                  const SizedBox.shrink(),
            ],
          );

    return PopScope<Object?>(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _index != 0) {
          setState(() {
            _index = 0;
            _dirForward = false;
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_titles[_index].tr),
          actions: [
            // Only where it applies: repeating a sale is the one shortcut that
            // matters on the subscriptions tab, and it needs no new screen.
            if (_index == 3)
              IconButton(
                tooltip: 'Repeat last sale'.tr,
                icon: const Icon(Icons.replay_rounded),
                onPressed: _repeatLastSale,
              ),
            IconButton(
              tooltip: 'Reports'.tr,
              icon: const Icon(Icons.insights_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: Text('Reports'.tr)),
                    body: const ReportsPage(),
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Settings'.tr,
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              ),
            ),
          ],
        ),
        body: NotificationListener<ScrollNotification>(
          onNotification: _handleScroll,
          child: isWide
              ? Row(
                children: [
                  NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: _goTo,
                    labelType: isExtended ? null : NavigationRailLabelType.all,
                    extended: isExtended,
                    destinations: [
                      NavigationRailDestination(
                        icon: const Icon(Icons.person_outline_rounded),
                        selectedIcon: const Icon(Icons.person_rounded),
                        label: Text('Personal'.tr),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.dashboard_outlined),
                        selectedIcon: const Icon(Icons.dashboard_rounded),
                        label: Text('Dashboard'.tr),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.people_outline_rounded),
                        selectedIcon: const Icon(Icons.people_rounded),
                        label: Text('Customers'.tr),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.vpn_key_outlined),
                        selectedIcon: const Icon(Icons.vpn_key_rounded),
                        label: Text('Subscriptions'.tr),
                      ),
                      NavigationRailDestination(
                        icon: const Icon(Icons.receipt_long_outlined),
                        selectedIcon: const Icon(Icons.receipt_long_rounded),
                        label: Text('Transactions'.tr),
                      ),
                    ],
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1180),
                        child: content,
                      ),
                    ),
                  ),
                ],
              )
              : content,
        ),
        floatingActionButton: !isReady
            ? null
            // Slides out of the way while the user scrolls down a list and
            // comes back on the first upward scroll or a tab change, so it
            // stops covering the last rows of long pages.
            : ValueListenableBuilder<bool>(
                valueListenable: _fabVisible,
                builder: (context, visible, _) {
                  final accessibleNavigation =
                      MediaQuery.maybeOf(context)?.accessibleNavigation ??
                      false;
                  return AnimatedSlide(
                    offset: visible || accessibleNavigation
                        ? Offset.zero
                        : const Offset(0, 4),
                    duration: Motion.adaptive(context, Motion.quick),
                    curve: Curves.easeOut,
                    // It collects itself into a smaller circle on the way out
                    // instead of just leaving the screen.
                    child: AnimatedScale(
                      scale: visible || accessibleNavigation ? 1 : 0.62,
                      duration: Motion.adaptive(context, Motion.quick),
                      curve: Curves.easeOut,
                      // Long-press fans out the speed dial: drag to an item
                      // and release to pick it, or tap an item directly.
                      child: GestureDetector(
                        onLongPressStart: _onFabLongPressStart,
                        onLongPressMoveUpdate: _onFabLongPressMove,
                        onLongPressEnd: _onFabLongPressEnd,
                        child: _buildFab(),
                      ),
                    ),
                  );
                },
              ),
        bottomNavigationBar: isWide
            ? null
            // The elastic-pill bar: same geometry and theme colors as the
            // Material NavigationBar, but the indicator stretches between
            // destinations and the chosen icon bounces once. Labels shrink
            // instead of hiding at very narrow widths.
            : LedgerNavBar(
                index: _index,
                onDestinationSelected: _goTo,
                destinations: [
                  LedgerNavDestination(
                    icon: Icons.person_outline_rounded,
                    selectedIcon: Icons.person_rounded,
                    label: 'Personal'.tr,
                  ),
                  LedgerNavDestination(
                    icon: Icons.dashboard_outlined,
                    selectedIcon: Icons.dashboard_rounded,
                    label: 'Dashboard'.tr,
                  ),
                  LedgerNavDestination(
                    icon: Icons.people_outline_rounded,
                    selectedIcon: Icons.people_rounded,
                    label: 'Customers'.tr,
                  ),
                  LedgerNavDestination(
                    icon: Icons.vpn_key_outlined,
                    selectedIcon: Icons.vpn_key_rounded,
                    label: 'Subscriptions'.tr,
                  ),
                  LedgerNavDestination(
                    icon: Icons.receipt_long_outlined,
                    selectedIcon: Icons.receipt_long_rounded,
                    label: 'Transactions'.tr,
                  ),
                ],
              ),
      ),
    );
  }
}

/// Direction-aware entrance for tab content.
///
/// When a tab becomes active its page slides in ~10 logical pixels from the
/// side the selection moved from (mirrored in RTL) and fades up. The first
/// tab shows instantly — the cold start never animates. Inactive panes are
/// left alone; the IndexedStack does not paint them anyway.
class _TabPane extends StatefulWidget {
  const _TabPane({
    required this.active,
    required this.forward,
    required this.child,
  });

  final bool active;
  final bool forward;
  final Widget child;

  @override
  State<_TabPane> createState() => _TabPaneState();
}

class _TabPaneState extends State<_TabPane>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: widget.active ? 1 : 0,
  );

  @override
  void didUpdateWidget(_TabPane old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _c.forward(from: 0);
    if (!widget.active) _c.value = 0;
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!Motion.motionEnabled ||
        (MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
      return widget.child;
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final dir = (widget.forward ? 1 : -1) * (rtl ? -1 : 1);
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = Curves.easeOutCubic.transform(_c.value);
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(10 * dir * (1 - t), 0),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// Where the i-th speed-dial item sits: a fan of arcs opening upward,
/// tilted toward the middle of the screen, clamped inside the viewport.
Offset _dialSlot(int i, int n, Offset origin, Size size) {
  const r = 122.0;
  final spread = n <= 1 ? 0.5 : i / (n - 1);
  final a = math.pi / 2 + spread * 1.12; // 90 degrees -> ~154 degrees
  final dx = origin.dx > size.width / 2
      ? math.cos(a) * r
      : -math.cos(a) * r;
  final p = Offset(origin.dx + dx, origin.dy - math.sin(a) * r);
  return Offset(
    p.dx.clamp(34.0, size.width - 34.0),
    p.dy.clamp(34.0, size.height - 34.0),
  );
}

class _DialItem {
  const _DialItem(this.value, this.icon, this.label, this.color);

  /// The same choice values the quick-add sheet returns.
  final String value;
  final IconData icon;

  /// Localization key.
  final String label;
  final Color color;
}

class _SpeedDialLayer extends StatefulWidget {
  const _SpeedDialLayer({
    required this.origin,
    required this.size,
    required this.items,
    required this.highlight,
    required this.onBarrier,
    required this.onPick,
  });

  final Offset origin;
  final Size size;
  final List<_DialItem> items;
  final ValueNotifier<int> highlight;
  final VoidCallback onBarrier;
  final ValueChanged<int> onPick;

  @override
  State<_SpeedDialLayer> createState() => _SpeedDialLayerState();
}

class _SpeedDialLayerState extends State<_SpeedDialLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fan = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  )..forward();

  @override
  void dispose() {
    _fan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onBarrier,
      child: AnimatedBuilder(
        animation: _fan,
        builder: (context, _) {
          final t = Curves.easeOutCubic.transform(_fan.value);
          return Stack(
            children: [
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.34 * t),
                ),
              ),
              Positioned.fill(
                child: ValueListenableBuilder<int>(
                  valueListenable: widget.highlight,
                  builder: (context, hi, _) => Stack(
                    children: [
                      for (var i = 0; i < widget.items.length; i++)
                        _item(context, i, t, hi == i),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _item(BuildContext context, int i, double t, bool hot) {
    final item = widget.items[i];
    final slot = _dialSlot(i, widget.items.length, widget.origin, widget.size);
    final appear = Curves.easeOutBack.transform(
      ((t - i * 0.05) / 0.7).clamp(0.0, 1.0),
    );
    return Positioned(
      left: slot.dx - 27,
      top: slot.dy - 27,
      child: Opacity(
        opacity: appear.clamp(0.0, 1.0),
        child: Transform.scale(
          scale: appear,
          child: GestureDetector(
            onTap: () => widget.onPick(i),
            child: AnimatedScale(
              scale: hot ? 1.28 : 1,
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hot
                          ? item.color
                          : item.color.withValues(alpha: 0.16),
                      border: Border.all(color: item.color, width: 1.6),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Icon(
                      item.icon,
                      size: 24,
                      color: hot ? Colors.white : item.color,
                    ),
                  ),
                  if (hot)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.inverseSurface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          child: Text(
                            item.label.tr,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
