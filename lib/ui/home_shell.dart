import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/haptics.dart';
import '../data/models.dart';
import '../data/repository.dart';
import 'customers_page.dart';
import 'dashboard_page.dart';
import 'forms/contact_edit_page.dart';
import 'forms/sell_subscription_page.dart';
import 'forms/transaction_edit_page.dart';
import 'personal_page.dart';
import 'reports_page.dart';
import 'settings_page.dart';
import 'subscriptions_page.dart';
import 'transactions_page.dart';

import '../core/localization.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  // Personal bookkeeping is the first destination because it is the most
  // frequent task; business tools remain one tap away.
  static const _titles = [
    'Personal',
    'Dashboard',
    'Customers',
    'Subscriptions',
    'Transactions',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final repo = context.read<AppRepository>();
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
    });
  }

  void _goTo(int i) {
    Haptics.selection();
    setState(() => _index = i);
  }

  Future<void> _personalAdd() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
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
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
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
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
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
    final repo = context.watch<AppRepository>();
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 840;
    final isExtended = width >= 1120;
    final content = !repo.isReady
        ? const Center(child: CircularProgressIndicator())
        : IndexedStack(
            index: _index,
            children: [
              PersonalPage(onNavigate: _goTo),
              DashboardPage(onNavigate: _goTo),
              const CustomersPage(),
              const SubscriptionsPage(),
              const TransactionsPage(),
            ],
          );

    return PopScope<Object?>(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _index != 0) setState(() => _index = 0);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_titles[_index].tr),
          actions: [
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
        body: isWide
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
        floatingActionButton: !repo.isReady
            ? null
            : _index == 2
            ? FloatingActionButton.extended(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ContactEditPage()),
                ),
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: Text('New customer'.tr),
              )
            : _index == 0
            ? FloatingActionButton.extended(
                onPressed: _personalAdd,
                icon: const Icon(Icons.add_rounded),
                label: Text('Add personal entry'.tr),
              )
            : _index == 3
            ? FloatingActionButton.extended(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SellSubscriptionPage(),
                  ),
                ),
                icon: const Icon(Icons.vpn_key_rounded),
                label: Text('Sell a subscription'.tr),
              )
            : FloatingActionButton(
                onPressed: _quickAdd,
                tooltip: 'Quick add'.tr,
                child: const Icon(Icons.add_rounded),
              ),
        bottomNavigationBar: isWide
            ? null
            : NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: _goTo,
                // Labels stay visible at all times: with five look-alike
                // icons, the text is what users actually scan for.
                labelBehavior:
                    NavigationDestinationLabelBehavior.alwaysShow,
                destinations: [
                  NavigationDestination(
                    icon: const Icon(Icons.person_outline_rounded),
                    selectedIcon: const Icon(Icons.person_rounded),
                    label: 'Personal'.tr,
                    tooltip: 'Personal'.tr,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.dashboard_outlined),
                    selectedIcon: const Icon(Icons.dashboard_rounded),
                    label: 'Dashboard'.tr,
                    tooltip: 'Dashboard'.tr,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.people_outline_rounded),
                    selectedIcon: const Icon(Icons.people_rounded),
                    label: 'Customers'.tr,
                    tooltip: 'Customers'.tr,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.vpn_key_outlined),
                    selectedIcon: const Icon(Icons.vpn_key_rounded),
                    label: 'Subscriptions'.tr,
                    tooltip: 'Subscriptions'.tr,
                  ),
                  NavigationDestination(
                    icon: const Icon(Icons.receipt_long_outlined),
                    selectedIcon: const Icon(Icons.receipt_long_rounded),
                    label: 'Transactions'.tr,
                    tooltip: 'Transactions'.tr,
                  ),
                ],
              ),
      ),
    );
  }
}
