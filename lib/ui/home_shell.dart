import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/haptics.dart';
import '../core/notifications/notify.dart';
import '../core/sms/sms_access.dart';
import '../core/sms/sms_models.dart';
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

  /// Lets the dial fan out of the button's centre instead of the finger's,
  /// which on the wide extended FAB can sit ~30 px away from it.
  final GlobalKey _fabKey = GlobalKey();

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

  /// The repository this shell keeps a handle on, so lifecycle callbacks and
  /// notification taps can be handled without rebuilding the whole shell.
  AppRepository? _repo;
  late final StreamSubscription<SmsMessage> _smsNotificationSubscription;
  final Set<String> _handledSmsNotificationKeys = {};
  final List<SmsMessage> _deferredSmsNotificationTaps = [];

  @override
  void dispose() {
    _closeDial();
    _dialHighlight.dispose();
    unawaited(_smsNotificationSubscription.cancel());
    WidgetsBinding.instance.removeObserver(this);
    _fabVisible.dispose();
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the system settings or a permission dialog: the
    // granted state may have changed without us asking here.
    if (state == AppLifecycleState.resumed) {
      final repo = _repo;
      if (repo != null && repo.isReady) {
        unawaited(repo.refreshNotificationPermission().then<void>((_) {}));
      }
      unawaited(_consumeSmsNotificationTaps());
    }
  }

  /// Returns the controller for a tab, creating it on first use so an unopened
  /// tab never allocates one.
  ScrollController _controllerFor(int index) =>
      _scrollControllers.putIfAbsent(index, ScrollController.new);

  @override
  void initState() {
    super.initState();
    _repo = context.read<AppRepository>();
    _smsNotificationSubscription = smsAccess.notificationTaps.listen(
      (message) => unawaited(_handleSmsNotificationTap(message)),
    );
    // First run after an update: teach the gestures once, with animation.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) maybeShowGestureTour(context);
    });
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final repo = context.read<AppRepository>();
      _repo = repo;
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

      // Android 13+ gates notifications behind a runtime permission. Asking
      // again after a denial returns silently, so this is safe every launch.
      if (repo.settings.dailyReminder) {
        await reminder.requestPermission();
        await repo.refreshNotificationPermission();
      }

      // The Android receiver uses the same active bank rules as inbox sync.
      await smsAccess.syncArrivalRules(
        senderHints: repo.activeSmsRules
            .expand((rule) => rule.senderHints)
            .toList(),
        bodyHints: repo.activeSmsRules
            .expand((rule) => rule.bodyHints)
            .toList(),
      );
      if (!mounted) return;
      unawaited(_consumeSmsNotificationTaps());
    });
  }

  Future<void> _consumeSmsNotificationTaps() async {
    if (!mounted) return;
    final deferred = List<SmsMessage>.of(_deferredSmsNotificationTaps);
    _deferredSmsNotificationTaps.clear();
    final buffered = smsAccess.takeBufferedNotificationTaps();
    for (final message in [...deferred, ...buffered]) {
      if (!mounted) return;
      await _handleSmsNotificationTap(message);
    }

    final launchMessage = await smsAccess.takePendingNotification();
    if (mounted && launchMessage != null) {
      await _handleSmsNotificationTap(launchMessage);
    }
  }

  Future<void> _handleSmsNotificationTap(SmsMessage message) async {
    if (!mounted) return;
    final repo = _repo;
    if (repo == null || !repo.isReady) {
      if (!_deferredSmsNotificationTaps.any(
        (item) => item.key == message.key,
      )) {
        _deferredSmsNotificationTaps.add(message);
      }
      return;
    }
    if (!_handledSmsNotificationKeys.add(message.key)) return;

    var suggestion = repo.smsSuggestions
        .where((sms) => sms.key == message.key)
        .firstOrNull;
    if (suggestion == null) {
      repo.importInboxSms([message]);
      suggestion = repo.smsSuggestions
          .where((sms) => sms.key == message.key)
          .firstOrNull;
    }
    if (suggestion == null) {
      showSnack(
        context,
        'No matching bank transaction was found for this SMS.',
      );
      return;
    }

    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SmsPage(openReviewKey: suggestion!.key),
      ),
    );
  }

  void _goTo(int i) {
    Haptics.selection();
    // Never switch tabs from under an open speed dial.
    _closeDial();
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
      // Only vertical list scrolling hides the button; dragging a
      // horizontal chip row or a chart sideways must not touch it.
      if (notification.metrics.axis != Axis.vertical) return false;
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

  /// How close the finger has to be to a dial slot to light it up.
  static const double _dialPickRadius = 58;

  void _onFabLongPressStart(LongPressStartDetails d) {
    final items = _dialItemsFor();
    if (items.isEmpty) return;
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    // A second long press (a second finger, or one that never released) must
    // not stack a new entry on top of the open one: `_dialEntry` would be
    // overwritten and the previous entry could never be removed again.
    _closeDial();
    Haptics.confirm();
    _dialItems = items;
    _dialOrigin = _fabCenter() ?? d.globalPosition;
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

  /// The action button's centre in global coordinates, or null before it has
  /// been laid out (the caller then falls back to the finger position).
  Offset? _fabCenter() {
    final box = _fabKey.currentContext?.findRenderObject();
    if (box is RenderBox && box.hasSize) {
      return box.localToGlobal(box.size.center(Offset.zero));
    }
    return null;
  }

  void _onFabLongPressMove(LongPressMoveUpdateDetails d) {
    if (_dialEntry == null) return;
    // The *nearest* slot inside the radius wins. Taking the first match used to
    // stick on the wrong item once the screen got small enough for two slots to
    // overlap the radius, because the old fan clamped its slots to the screen
    // edges.
    final layout = _DialLayout.of(
      origin: _dialOrigin,
      size: _dialSize,
      count: _dialItems.length,
    );
    var hit = -1;
    var best = _dialPickRadius;
    for (var i = 0; i < _dialItems.length; i++) {
      final slot = layout.slot(i, _dialItems.length);
      final distance = (slot - d.globalPosition).distance;
      if (distance < best) {
        best = distance;
        hit = i;
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
                      // Long-press fans out the speed dial: hold, drag to an
                      // item, release to run it. The dial swallows every other
                      // touch while it is up (a second finger can tap an item
                      // or the dim backdrop directly), and the finger that
                      // opened it is the one that picks.
                      child: IgnorePointer(
                        ignoring: !(visible || accessibleNavigation),
                        child: GestureDetector(
                          key: _fabKey,
                          onLongPressStart: _onFabLongPressStart,
                          onLongPressMoveUpdate: _onFabLongPressMove,
                          onLongPressEnd: _onFabLongPressEnd,
                          child: _buildFab(),
                        ),
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

/// The geometry of the speed-dial fan.
///
/// Two things have to hold at the same time, and the old fixed radius could
/// not hold both:
///
///  * the buttons must not overlap — every slot is a [itemSize] circle, so
///    neighbouring slots have to stay at least [itemSize] + [gap] apart;
///  * the fan must stay inside the screen — a slot that is clamped to the
///    edge lands on top of its neighbour, and that is exactly what turned
///    the five-button fan of the dashboard into a pile of overlapping
///    circles (the old radius put them 34 pixels apart with 54 pixel
///    buttons).
///
/// So the radius is derived from the number of buttons: the more of them
/// there are, the further out they have to sit to keep the same distance.
/// The fan always opens towards the middle of the screen, and it is never
/// allowed to reach past the edges.
class _DialLayout {
  const _DialLayout({
    required this.origin,
    required this.radius,
    required this.sweep,
    required this.direction,
  });

  /// The diameter of one dial button.
  static const double itemSize = 54;

  /// The clear space kept between two neighbouring buttons.
  static const double gap = 12;

  /// How wide the fan opens, in radians (about 64 degrees). Kept below a
  /// quarter turn so the last button never drops below the button it
  /// belongs to.
  static const double maxSweep = 1.12;

  /// How close a button may come to the edge of the screen.
  static const double edge = 34;

  /// The radius the fan uses when it has room to breathe.
  static const double preferredRadius = 122;

  /// The centre of the button the fan grew out of.
  final Offset origin;

  /// The distance from [origin] to every button.
  final double radius;

  /// The angle the fan covers, in radians.
  final double sweep;

  /// Which way the fan opens: towards the middle of the screen.
  final double direction;

  factory _DialLayout.of({
    required Offset origin,
    required Size size,
    required int count,
  }) {
    // The fan opens towards the middle of the screen, so it never reaches
    // for the edge the button is anchored to.
    final direction = origin.dx > size.width / 2 ? -1.0 : 1.0;
    if (count <= 1) {
      return _DialLayout(
        origin: origin,
        radius: preferredRadius,
        sweep: 0,
        direction: direction,
      );
    }
    final spacing = itemSize + gap;
    final sweep = maxSweep;
    // The room the fan has: above the button, and towards the side it
    // opens to.
    final topRoom = origin.dy - edge;
    final sideRoom = math.max(
      1.0,
      direction > 0 ? size.width - edge - origin.dx : origin.dx - edge,
    );
    final maxRadius = math.min(topRoom, sideRoom / math.sin(sweep));
    // The radius the spacing asks for. When the screen is too small for it,
    // the buttons sit a little closer instead of being pushed on top of
    // each other.
    final wanted = math.max(
      spacing / (2 * math.sin(sweep / (2 * (count - 1)))),
      preferredRadius,
    );
    return _DialLayout(
      origin: origin,
      radius: math.min(wanted, maxRadius),
      sweep: sweep,
      direction: direction,
    );
  }

  /// The centre of the i-th button.
  Offset slot(int i, int count) {
    final spread = count <= 1 ? 0.5 : i / (count - 1);
    final a = math.pi / 2 + spread * sweep;
    return Offset(
      origin.dx + direction * -math.cos(a) * radius,
      origin.dy - math.sin(a) * radius,
    );
  }
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
  );
  bool _fanStarted = false;

  /// The fan's geometry. Computed once: the layout only depends on where
  /// the button is and how many items there are, and both are fixed for as
  /// long as the dial is open.
  late final _DialLayout _layout = _DialLayout.of(
    origin: widget.origin,
    size: widget.size,
    count: widget.items.length,
  );

  @override
  void dispose() {
    _fan.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Started here rather than in `initState` so the reduced-motion preference
    // can be read: `MediaQuery` lookups are not allowed before the first
    // `didChangeDependencies`. Under reduced motion the dial is simply there,
    // already fanned out, instead of animating for 280 ms.
    if (_fanStarted) return;
    _fanStarted = true;
    if (Motion.reduced(context)) {
      _fan.value = 1;
    } else {
      _fan.forward();
    }
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
    final slot = _layout.slot(i, widget.items.length);
    final appear = Curves.easeOutBack.transform(
      ((t - i * 0.05) / 0.7).clamp(0.0, 1.0),
    );
    final half = _DialLayout.itemSize / 2;
    return Positioned(
      left: slot.dx - half,
      top: slot.dy - half,
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
