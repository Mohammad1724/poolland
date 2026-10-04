import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:poolland/data/models.dart';
import 'package:poolland/data/repository.dart';
import 'package:poolland/data/store.dart';
import 'package:poolland/ui/customer_detail_page.dart';
import 'package:poolland/ui/customers_page.dart';
import 'package:poolland/ui/dashboard_page.dart';
import 'package:poolland/ui/forms/contact_edit_page.dart';
import 'package:poolland/ui/forms/plan_edit_page.dart';
import 'package:poolland/ui/forms/sell_subscription_page.dart';
import 'package:poolland/ui/forms/transaction_edit_page.dart';
import 'package:poolland/ui/home_shell.dart';
import 'package:poolland/ui/onboarding.dart';
import 'package:poolland/ui/personal_page.dart';
import 'package:poolland/ui/reports_page.dart';
import 'package:poolland/ui/settings_page.dart';
import 'package:poolland/ui/sms_page.dart';
import 'package:poolland/ui/subscriptions_page.dart';
import 'package:poolland/ui/theme.dart';
import 'package:poolland/ui/transactions_page.dart';

/// تست دود: همه‌ی صفحه‌ها باید بدون خطا رندر شوند
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late LocalStore store;
  late AppRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('vpnledger_ui');
    store = await LocalStore.openAt(tmp.path);
    repo = AppRepository(store: store);
    await repo.loadDemoData();
  });

  tearDown(() async {
    await store.close();
    await tmp.delete(recursive: true);
  });

  Widget wrap(Widget child) => ChangeNotifierProvider<AppRepository>.value(
        value: repo,
        child: MaterialApp(
          locale: const Locale('fa', 'IR'),
          supportedLocales: const [Locale('fa', 'IR'), Locale('en')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: AppTheme.light(),
          builder: (context, c) =>
              Directionality(textDirection: TextDirection.rtl, child: c ?? const SizedBox()),
          home: Scaffold(body: child),
        ),
      );

  testWidgets('داشبورد با داده‌ی نمونه رندر می‌شود', (tester) async {
    await tester.pumpWidget(wrap(DashboardPage(onNavigate: (_) {})));
    await tester.pumpAndSettle();

    expect(find.text('خلاصه‌ی این ماه'), findsOneWidget);
    expect(find.text('طلب شما از مشتری‌ها'), findsOneWidget);
    expect(find.text('موجودی صندوق'), findsOneWidget);
  });

  testWidgets('پوسته‌ی اصلی: جابه‌جایی بین تب‌ها', (tester) async {
    await tester.pumpWidget(wrap(const HomeShell()));
    // کارهای راه‌اندازی (ثبتِ خودکارِ تراکنش‌های تکرارشونده) شامل IO واقعی
    // است؛ در تست‌های ویجتی باید با runAsync به آن‌ها فرصتِ اجرا بدهیم.
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);

    for (final tab in [
      'شخصی',
      'مشتری‌ها',
      'اشتراک‌ها',
      'تراکنش‌ها',
      'گزارش‌ها',
      'داشبورد'
    ]) {
      await tester.tap(find.text(tab).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: 'تب $tab خطا داد');
    }
  });

  testWidgets('فهرست مشتری‌ها و جزئیات مشتری', (tester) async {
    await tester.pumpWidget(wrap(const CustomersPage()));
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsWidgets);
    expect(tester.takeException(), isNull);

    final customer = repo.customers.first;
    await tester.pumpWidget(wrap(CustomerDetailPage(customer: customer)));
    await tester.pumpAndSettle();

    expect(find.text(customer.name), findsWidgets);
    expect(find.text('سرویس‌ها (${_fa('${repo.subsOfCustomer(customer.id).length}')})'),
        findsOneWidget);
  });

  testWidgets('صفحه‌های اشتراک و تراکنش و گزارش', (tester) async {
    for (final page in [
      const PersonalPage(),
      const SubscriptionsPage(),
      const TransactionsPage(),
      const ReportsPage()
    ]) {
      await tester.pumpWidget(wrap(page));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: '${page.runtimeType} خطا داد');
    }
  });

  testWidgets('تنظیمات و زیرصفحه‌ها', (tester) async {
    for (final page in [
      const SettingsPage(),
      const PlansPage(),
      const CategoriesPage(),
      const RatesPage(),
    ]) {
      await tester.pumpWidget(wrap(page));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull, reason: '${page.runtimeType} خطا داد');
    }
  });

  testWidgets('فرم فروش اشتراک', (tester) async {
    await tester.pumpWidget(wrap(SellSubscriptionPage(contact: repo.customers.first)));
    await tester.pumpAndSettle();
    expect(find.text('عنوان سرویس'), findsOneWidget);
    expect(find.text('مدت:'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('فرم تراکنش و فرم مشتری جدید', (tester) async {
    await tester.pumpWidget(wrap(const TransactionEditPage(initialKind: TxnKind.expense)));
    await tester.pumpAndSettle();
    expect(find.text('دسته‌بندی'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(wrap(const ContactEditPage()));
    await tester.pumpAndSettle();
    expect(find.text('بدهی/طلب قبلی'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('صفحه‌ی پیامک‌های بانکی', (tester) async {
    await tester.pumpWidget(wrap(const SmsPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('صفحه‌ی خوش‌آمدگویی', (tester) async {
    await tester.pumpWidget(wrap(const OnboardingPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('دفتر وی‌پی‌ان'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

String _fa(String s) {
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  final sb = StringBuffer();
  for (final ch in s.split('')) {
    final i = '0123456789'.indexOf(ch);
    sb.write(i >= 0 ? fa[i] : ch);
  }
  return sb.toString();
}
