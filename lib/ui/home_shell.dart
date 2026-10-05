import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _titles = [
    'Dashboard',
    'Personal',
    'Customers',
    'Subscriptions',
    'Transactions',
    'Reports'
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

  void _goTo(int i) => setState(() => _index = i);

  Future<void> _quickAdd() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: Theme.of(ctx).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                    color: Theme.of(ctx).dividerColor,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('What would you like to do?',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 10),
            _menuTile(ctx, 'Sell a subscription', Icons.vpn_key_rounded, 'sale_sub'),
            _menuTile(ctx, 'Record income (no subscription)', Icons.trending_up_rounded, 'income'),
            _menuTile(ctx, 'Receive from customer', Icons.call_received_rounded, 'receive'),
            _menuTile(ctx, 'Record expense', Icons.trending_down_rounded, 'expense'),
            _menuTile(ctx, 'Personal expense', Icons.person_outline_rounded, 'p_expense'),
            _menuTile(ctx, 'Personal income', Icons.savings_outlined, 'p_income'),
            _menuTile(ctx, 'Payment / refund', Icons.call_made_rounded, 'refund'),
          ],
        ),
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case 'sale_sub':
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SellSubscriptionPage()));
        break;
      case 'income':
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const TransactionEditPage(initialKind: TxnKind.income)));
        break;
      case 'receive':
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const TransactionEditPage(initialKind: TxnKind.receive)));
        break;
      case 'expense':
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const TransactionEditPage(initialKind: TxnKind.expense)));
        break;
      case 'p_expense':
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const TransactionEditPage(
                    initialKind: TxnKind.expense, initialScope: TxnScope.personal)));
        break;
      case 'p_income':
        await Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const TransactionEditPage(
                    initialKind: TxnKind.income, initialScope: TxnScope.personal)));
        break;
      case 'refund':
        await Navigator.push(context,
            MaterialPageRoute(builder: (_) => const TransactionEditPage(initialKind: TxnKind.refund)));
        break;
    }
  }

  Widget _menuTile(BuildContext ctx, String title, IconData icon, String value) => ListTile(
        leading: Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: Theme.of(ctx).colorScheme.primary),
        ),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right_rounded, size: 18),
        onTap: () => Navigator.pop(ctx, value),
      );

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<AppRepository>();

    return PopScope<Object?>(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _index != 0) {
          setState(() => _index = 0);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_titles[_index]),
          actions: [
            if (repo.settings.businessName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Center(
                  child: Text(repo.settings.businessName,
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55))),
                ),
              ),
            IconButton(
              tooltip: 'Settings',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () =>
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage())),
            ),
          ],
        ),
        body: !repo.isReady
            ? const Center(child: CircularProgressIndicator())
            : IndexedStack(
                index: _index,
                children: [
                  DashboardPage(onNavigate: _goTo),
                  const PersonalPage(),
                  const CustomersPage(),
                  const SubscriptionsPage(),
                  const TransactionsPage(),
                  const ReportsPage(),
                ],
              ),
        floatingActionButton: !repo.isReady
            ? null
            : _index == 2
                ? FloatingActionButton.extended(
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const ContactEditPage())),
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('New customer'),
                  )
                : _index == 1
                    ? FloatingActionButton.extended(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const TransactionEditPage(
                                    initialKind: TxnKind.expense,
                                    initialScope: TxnScope.personal))),
                        icon: const Icon(Icons.remove_rounded),
                        label: const Text('Personal expense'),
                      )
                    : FloatingActionButton(
                        onPressed: _quickAdd,
                        tooltip: 'Quick add',
                        child: const Icon(Icons.add_rounded),
                      ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _goTo,
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard_rounded),
                label: 'Dashboard'),
            NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Personal'),
            NavigationDestination(
                icon: Icon(Icons.people_outline_rounded),
                selectedIcon: Icon(Icons.people_rounded),
                label: 'Customers'),
            NavigationDestination(
                icon: Icon(Icons.vpn_key_outlined),
                selectedIcon: Icon(Icons.vpn_key_rounded),
                label: 'Subscriptions'),
            NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long_rounded),
                label: 'Transactions'),
            NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights_rounded),
                label: 'Reports'),
          ],
        ),
      ),
    );
  }
}
