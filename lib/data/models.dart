import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../core/format_utils.dart';

/// ============================================================
///  Data models for the VPN ledger.
///  All models are stored as Maps (compatible with Hive and JSON).
/// ============================================================

/// ----- Currency -----
class CurrencyDef {
  final String code; // IRT, USD, USDT, EUR ...
  final String name; // Toman, US dollars, etc.
  final String symbol; // Toman, $, etc.
  final double rateToBase; // Base-currency value of one unit of this currency.
  final int decimals;

  const CurrencyDef({
    required this.code,
    required this.name,
    required this.symbol,
    required this.rateToBase,
    this.decimals = 0,
  });

  bool get isBase => rateToBase == 1;

  CurrencyDef copyWith({String? name, String? symbol, double? rateToBase, int? decimals}) =>
      CurrencyDef(
        code: code,
        name: name ?? this.name,
        symbol: symbol ?? this.symbol,
        rateToBase: rateToBase ?? this.rateToBase,
        decimals: decimals ?? this.decimals,
      );

  Map<String, dynamic> toMap() => {
        'code': code,
        'name': name,
        'symbol': symbol,
        'rateToBase': rateToBase,
        'decimals': decimals,
      };

  factory CurrencyDef.fromMap(Map map) => CurrencyDef(
        code: '${map['code']}',
        name: '${map['name'] ?? map['code']}',
        symbol: '${map['symbol'] ?? map['code']}',
        rateToBase: (map['rateToBase'] as num?)?.toDouble() ?? 1,
        decimals: (map['decimals'] as num?)?.toInt() ?? 0,
      );
}

/// ----- App settings -----
class AppSettings {
  final String businessName;
  final String baseCurrency; // Base currency code (default: IRT = Toman).
  final List<CurrencyDef> currencies;
  final bool persianDigits;
  final int reminderDays; // Days before expiry to send a reminder.
  final String? pinHash; // Optional app lock.
  final String themeMode; // system | light | dark
  final double openingCash; // Initial cash/bank balance.
  final bool setupDone; // Whether initial setup is complete.

  // ---- Bank SMS ----
  final bool smsEnabled; // Whether SMS reading is enabled.
  final int smsSyncDays; // Number of past days to scan.
  final bool smsAutoApprove; // Whether high-confidence matches are recorded automatically.
  final int smsLastSyncAt; // Last sync timestamp (for incremental updates).

  // ---- Daily expense reminder ----
  final bool dailyReminder; // Whether the daily reminder is enabled.
  final int reminderHour; // Reminder hour (0–23).
  final int reminderMinute; // Reminder minute.

  const AppSettings({
    this.businessName = 'My VPN Business',
    this.baseCurrency = 'IRT',
    this.currencies = defaultCurrencies,
    this.persianDigits = false,
    this.reminderDays = 3,
    this.pinHash,
    this.themeMode = 'system',
    this.openingCash = 0,
    this.setupDone = false,
    this.smsEnabled = false,
    this.smsSyncDays = 90,
    this.smsAutoApprove = false,
    this.smsLastSyncAt = 0,
    this.dailyReminder = false,
    this.reminderHour = 21,
    this.reminderMinute = 0,
  });

  /// Default currencies: Toman (base) plus currencies commonly used by VPN sellers.
  static const defaultCurrencies = <CurrencyDef>[
    CurrencyDef(code: 'IRT', name: 'Toman', symbol: 'Toman', rateToBase: 1, decimals: 0),
    CurrencyDef(code: 'USD', name: 'US Dollar', symbol: r'$', rateToBase: 130000, decimals: 2),
    CurrencyDef(code: 'USDT', name: 'Tether', symbol: 'USDT', rateToBase: 130000, decimals: 2),
    CurrencyDef(code: 'EUR', name: 'Euro', symbol: '€', rateToBase: 140000, decimals: 2),
  ];

  CurrencyDef currency(String code) => currencies.firstWhere(
        (c) => c.code == code,
        orElse: () => currencies.isNotEmpty
            ? currencies.first
            : const CurrencyDef(code: 'IRT', name: 'Toman', symbol: 'Toman', rateToBase: 1),
      );

  CurrencyDef get base => currency(baseCurrency);

  String symbolOf(String code) => currency(code).symbol;

  AppSettings copyWith({
    String? businessName,
    String? baseCurrency,
    List<CurrencyDef>? currencies,
    bool? persianDigits,
    int? reminderDays,
    String? pinHash,
    bool clearPin = false,
    String? themeMode,
    double? openingCash,
    bool? setupDone,
    bool? smsEnabled,
    int? smsSyncDays,
    bool? smsAutoApprove,
    int? smsLastSyncAt,
    bool? dailyReminder,
    int? reminderHour,
    int? reminderMinute,
  }) =>
      AppSettings(
        businessName: businessName ?? this.businessName,
        baseCurrency: baseCurrency ?? this.baseCurrency,
        currencies: currencies ?? this.currencies,
        persianDigits: persianDigits ?? this.persianDigits,
        reminderDays: reminderDays ?? this.reminderDays,
        pinHash: clearPin ? null : (pinHash ?? this.pinHash),
        themeMode: themeMode ?? this.themeMode,
        openingCash: openingCash ?? this.openingCash,
        setupDone: setupDone ?? this.setupDone,
        smsEnabled: smsEnabled ?? this.smsEnabled,
        smsSyncDays: smsSyncDays ?? this.smsSyncDays,
        smsAutoApprove: smsAutoApprove ?? this.smsAutoApprove,
        smsLastSyncAt: smsLastSyncAt ?? this.smsLastSyncAt,
        dailyReminder: dailyReminder ?? this.dailyReminder,
        reminderHour: reminderHour ?? this.reminderHour,
        reminderMinute: reminderMinute ?? this.reminderMinute,
      );

  Map<String, dynamic> toMap() => {
        'businessName': businessName,
        'baseCurrency': baseCurrency,
        'currencies': currencies.map((e) => e.toMap()).toList(),
        'persianDigits': persianDigits,
        'reminderDays': reminderDays,
        'pinHash': pinHash,
        'themeMode': themeMode,
        'openingCash': openingCash,
        'setupDone': setupDone,
        'smsEnabled': smsEnabled,
        'smsSyncDays': smsSyncDays,
        'smsAutoApprove': smsAutoApprove,
        'smsLastSyncAt': smsLastSyncAt,
        'dailyReminder': dailyReminder,
        'reminderHour': reminderHour,
        'reminderMinute': reminderMinute,
      };

  factory AppSettings.fromMap(Map map) => AppSettings(
        businessName: '${map['businessName'] ?? 'My VPN Business'}',
        baseCurrency: '${map['baseCurrency'] ?? 'IRT'}',
        currencies: (map['currencies'] as List?)
                ?.map((e) => CurrencyDef.fromMap(Map.from(e as Map)))
                .toList() ??
            defaultCurrencies,
        persianDigits: map['persianDigits'] as bool? ?? false,
        reminderDays: (map['reminderDays'] as num?)?.toInt() ?? 3,
        pinHash: map['pinHash'] as String?,
        themeMode: '${map['themeMode'] ?? 'system'}',
        openingCash: (map['openingCash'] as num?)?.toDouble() ?? 0,
        setupDone: map['setupDone'] as bool? ?? false,
        smsEnabled: map['smsEnabled'] as bool? ?? false,
        smsSyncDays: (map['smsSyncDays'] as num?)?.toInt() ?? 90,
        smsAutoApprove: map['smsAutoApprove'] as bool? ?? false,
        smsLastSyncAt: (map['smsLastSyncAt'] as num?)?.toInt() ?? 0,
        dailyReminder: map['dailyReminder'] as bool? ?? false,
        reminderHour: (map['reminderHour'] as num?)?.toInt() ?? 21,
        reminderMinute: (map['reminderMinute'] as num?)?.toInt() ?? 0,
      );
}

/// ----- Transaction scope: business or personal -----
enum TxnScope {
  business, // Belongs to the business (VPN sales).
  personal; // Belongs to personal finances.

  String get label => switch (this) {
        TxnScope.business => 'Business',
        TxnScope.personal => 'Personal',
      };

  /// Display hint used in forms.
  String get hint => switch (this) {
        TxnScope.business => 'Included in business profit and loss',
        TxnScope.personal => 'Excluded from business profit and loss',
      };
}

/// ----- Income and expense category -----
class Category {
  final String id;
  final String name;
  final TxnKind kind; // Only income and expense are valid here.
  final int sortOrder;
  final TxnScope scope; // Whether this category is for business or personal use.

  const Category({
    required this.id,
    required this.name,
    required this.kind,
    this.sortOrder = 0,
    this.scope = TxnScope.business,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        'sortOrder': sortOrder,
        'scope': scope.name,
      };

  factory Category.fromMap(Map map) => Category(
        id: '${map['id']}',
        name: '${map['name']}',
        kind: TxnKind.values.firstWhere((k) => k.name == map['kind'],
            orElse: () => TxnKind.expense),
        sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
        scope: TxnScope.values.firstWhere((v) => v.name == map['scope'],
            orElse: () => TxnScope.business),
      );
}

/// ----- Contact (customer or supplier) -----
class Customer {
  final String id;
  final String name;
  final String phone;
  final String telegram;
  final String note;
  final double openingBalance; // Positive means they already owed us; negative means we owed them.
  final DateTime createdAt;
  final bool archived;

  /// Customer bank identifiers used for automatic SMS matching.
  /// (For example, the last four digits or the full card number.)
  final List<String> bankIdentifiers;

  const Customer({
    required this.id,
    required this.name,
    this.phone = '',
    this.telegram = '',
    this.note = '',
    this.openingBalance = 0,
    required this.createdAt,
    this.archived = false,
    this.bankIdentifiers = const [],
  });

  Customer copyWith({
    String? name,
    String? phone,
    String? telegram,
    String? note,
    double? openingBalance,
    bool? archived,
    List<String>? bankIdentifiers,
  }) =>
      Customer(
        id: id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        telegram: telegram ?? this.telegram,
        note: note ?? this.note,
        openingBalance: openingBalance ?? this.openingBalance,
        createdAt: createdAt,
        archived: archived ?? this.archived,
        bankIdentifiers: bankIdentifiers ?? this.bankIdentifiers,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'telegram': telegram,
        'note': note,
        'openingBalance': openingBalance,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'archived': archived,
        'bankIdentifiers': bankIdentifiers,
      };

  factory Customer.fromMap(Map map) => Customer(
        id: '${map['id']}',
        name: '${map['name']}',
        phone: '${map['phone'] ?? ''}',
        telegram: '${map['telegram'] ?? ''}',
        note: '${map['note'] ?? ''}',
        openingBalance: (map['openingBalance'] as num?)?.toDouble() ?? 0,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (map['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch),
        archived: map['archived'] as bool? ?? false,
        bankIdentifiers: (map['bankIdentifiers'] as List? ?? const [])
            .map((e) => '$e')
            .where((e) => e.trim().isNotEmpty)
            .toList(),
      );
}

/// ----- Subscription -----
class Subscription {
  final String id;
  final String customerId;
  final String? planId; // Selected plan (optional).
  final String planName; // For example: 1 month, 50 GB, 2 devices.
  final DateTime startDate;
  final DateTime endDate;
  final double amount; // Sale amount.
  final String currency; // Currency code.
  final int deviceCount;
  final String note;
  final bool autoRenew;
  final DateTime createdAt;

  const Subscription({
    required this.id,
    required this.customerId,
    this.planId,
    required this.planName,
    required this.startDate,
    required this.endDate,
    this.amount = 0,
    this.currency = 'IRT',
    this.deviceCount = 1,
    this.note = '',
    this.autoRenew = false,
    required this.createdAt,
  });

  int get durationDays => endDate.difference(startDate).inDays + 1;

  Subscription copyWith({
    String? customerId,
    String? planId,
    String? planName,
    DateTime? startDate,
    DateTime? endDate,
    double? amount,
    String? currency,
    int? deviceCount,
    String? note,
    bool? autoRenew,
  }) =>
      Subscription(
        id: id,
        customerId: customerId ?? this.customerId,
        planId: planId ?? this.planId,
        planName: planName ?? this.planName,
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
        amount: amount ?? this.amount,
        currency: currency ?? this.currency,
        deviceCount: deviceCount ?? this.deviceCount,
        note: note ?? this.note,
        autoRenew: autoRenew ?? this.autoRenew,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'customerId': customerId,
        'planId': planId,
        'planName': planName,
        'startDate': startDate.millisecondsSinceEpoch,
        'endDate': endDate.millisecondsSinceEpoch,
        'amount': amount,
        'currency': currency,
        'deviceCount': deviceCount,
        'note': note,
        'autoRenew': autoRenew,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory Subscription.fromMap(Map map) => Subscription(
        id: '${map['id']}',
        customerId: '${map['customerId']}',
        planId: map['planId'] as String?,
        planName: '${map['planName'] ?? ''}',
        startDate: DateTime.fromMillisecondsSinceEpoch((map['startDate'] as num).toInt()),
        endDate: DateTime.fromMillisecondsSinceEpoch((map['endDate'] as num).toInt()),
        amount: (map['amount'] as num?)?.toDouble() ?? 0,
        currency: '${map['currency'] ?? 'IRT'}',
        deviceCount: (map['deviceCount'] as num?)?.toInt() ?? 1,
        note: '${map['note'] ?? ''}',
        autoRenew: map['autoRenew'] as bool? ?? false,
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (map['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch),
      );
}

/// ----- Saved plan (sales template) -----
enum PlanDurationUnit { day, month }

class Plan {
  final String id;
  final String name; // For example: 1 month, 50 GB.
  final double price;
  final String currency;
  final int durationValue;
  final PlanDurationUnit durationUnit;
  final String note;
  final bool archived;

  const Plan({
    required this.id,
    required this.name,
    this.price = 0,
    this.currency = 'IRT',
    this.durationValue = 1,
    this.durationUnit = PlanDurationUnit.month,
    this.note = '',
    this.archived = false,
  });

  int get durationDays => durationUnit == PlanDurationUnit.day ? durationValue : durationValue * 30;

  String get durationLabel =>
      '$durationValue ${durationUnit == PlanDurationUnit.month ? (durationValue == 1 ? 'month' : 'months') : (durationValue == 1 ? 'day' : 'days')}';

  /// Calculate the end date from the start date (months follow the Jalali calendar).
  DateTime endFrom(DateTime start) {
    final s = DateTime(start.year, start.month, start.day);
    if (durationUnit == PlanDurationUnit.day) {
      final end = s.add(Duration(days: durationValue - 1));
      return DateTime(end.year, end.month, end.day, 23, 59);
    }
    final j = Jalali.fromDateTime(s);
    final e = j.addMonths(durationValue).addDays(-1).toDateTime();
    return DateTime(e.year, e.month, e.day, 23, 59);
  }

  Plan copyWith({
    String? name,
    double? price,
    String? currency,
    int? durationValue,
    PlanDurationUnit? durationUnit,
    String? note,
    bool? archived,
  }) =>
      Plan(
        id: id,
        name: name ?? this.name,
        price: price ?? this.price,
        currency: currency ?? this.currency,
        durationValue: durationValue ?? this.durationValue,
        durationUnit: durationUnit ?? this.durationUnit,
        note: note ?? this.note,
        archived: archived ?? this.archived,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'price': price,
        'currency': currency,
        'durationValue': durationValue,
        'durationUnit': durationUnit.name,
        'note': note,
        'archived': archived,
      };

  factory Plan.fromMap(Map map) => Plan(
        id: '${map['id']}',
        name: '${map['name']}',
        price: (map['price'] as num?)?.toDouble() ?? 0,
        currency: '${map['currency'] ?? 'IRT'}',
        durationValue: (map['durationValue'] as num?)?.toInt() ?? 1,
        durationUnit: PlanDurationUnit.values.firstWhere(
            (u) => u.name == map['durationUnit'],
            orElse: () => PlanDurationUnit.month),
        note: '${map['note'] ?? ''}',
        archived: map['archived'] as bool? ?? false,
      );
}

/// ----- Transaction types -----
enum TxnKind {
  income, // Sale or income.
  expense, // Expense.
  receive, // Payment received from a customer (settlement).
  refund, // Payment or refund to a customer.
}

extension TxnKindX on TxnKind {
  String get label => switch (this) {
        TxnKind.income => 'Sale / income',
        TxnKind.expense => 'Expense',
        TxnKind.receive => 'Customer payment',
        TxnKind.refund => 'Refund to customer',
      };

  String get shortLabel => switch (this) {
        TxnKind.income => 'Income',
        TxnKind.expense => 'Expense',
        TxnKind.receive => 'Receive',
        TxnKind.refund => 'Payment',
      };

  IconData get icon => switch (this) {
        TxnKind.income => Icons.trending_up_rounded,
        TxnKind.expense => Icons.trending_down_rounded,
        TxnKind.receive => Icons.call_received_rounded,
        TxnKind.refund => Icons.call_made_rounded,
      };

  bool get isProfitKind => this == TxnKind.income || this == TxnKind.expense;

  /// Does this transaction affect the contact’s balance?
  bool get affectsBalance => this != TxnKind.income && this != TxnKind.expense;

  /// Cash direction: +1 inflow, −1 outflow, 0 no effect.
  int get cashDirection => switch (this) {
        TxnKind.receive => 1,
        TxnKind.refund => -1,
        _ => 0,
      };
}

/// ----- Transaction -----
class Txn {
  final String id;
  final TxnKind kind;
  final double amount;
  final String currency; // Transaction currency code.
  final double rateToBase; // Exchange rate to the base currency when recorded (snapshot).
  final DateTime date;
  final String? categoryId;
  final String? customerId;
  final String? subscriptionId;
  final bool credit; // For income/expense, true means charged to the customer’s account.
  final TxnScope scope; // Business or personal (business profit includes business transactions only).
  final String note;
  final DateTime createdAt;

  const Txn({
    required this.id,
    required this.kind,
    required this.amount,
    this.currency = 'IRT',
    this.rateToBase = 1,
    required this.date,
    this.categoryId,
    this.customerId,
    this.subscriptionId,
    this.credit = false,
    this.scope = TxnScope.business,
    this.note = '',
    required this.createdAt,
  });

  bool get isCash => !credit;

  Txn copyWith({
    TxnKind? kind,
    double? amount,
    String? currency,
    double? rateToBase,
    DateTime? date,
    String? categoryId,
    String? customerId,
    String? subscriptionId,
    bool? credit,
    TxnScope? scope,
    String? note,
    bool clearCustomer = false,
    bool clearCategory = false,
    bool clearSubscription = false,
  }) =>
      Txn(
        id: id,
        kind: kind ?? this.kind,
        amount: amount ?? this.amount,
        currency: currency ?? this.currency,
        rateToBase: rateToBase ?? this.rateToBase,
        date: date ?? this.date,
        categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
        customerId: clearCustomer ? null : (customerId ?? this.customerId),
        subscriptionId: clearSubscription ? null : (subscriptionId ?? this.subscriptionId),
        credit: credit ?? this.credit,
        scope: scope ?? this.scope,
        note: note ?? this.note,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'kind': kind.name,
        'amount': amount,
        'currency': currency,
        'rateToBase': rateToBase,
        'date': date.millisecondsSinceEpoch,
        'categoryId': categoryId,
        'customerId': customerId,
        'subscriptionId': subscriptionId,
        'credit': credit,
        'scope': scope.name,
        'note': note,
        'createdAt': createdAt.millisecondsSinceEpoch,
      };

  factory Txn.fromMap(Map map) => Txn(
        id: '${map['id']}',
        kind: TxnKind.values.firstWhere((k) => k.name == map['kind'],
            orElse: () => TxnKind.income),
        amount: (map['amount'] as num?)?.toDouble() ?? 0,
        currency: '${map['currency'] ?? 'IRT'}',
        rateToBase: (map['rateToBase'] as num?)?.toDouble() ?? 1,
        date: DateTime.fromMillisecondsSinceEpoch((map['date'] as num).toInt()),
        categoryId: map['categoryId'] as String?,
        customerId: map['customerId'] as String?,
        subscriptionId: map['subscriptionId'] as String?,
        credit: map['credit'] as bool? ?? false,
        scope: TxnScope.values.firstWhere((v) => v.name == map['scope'],
            orElse: () => TxnScope.business),
        note: '${map['note'] ?? ''}',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (map['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch),
      );
}

/// ----- Subscription status -----
enum SubStatus { active, expiringSoon, expired }

extension SubStatusX on SubStatus {
  String get label => switch (this) {
        SubStatus.active => 'Active',
        SubStatus.expiringSoon => 'Expiring soon',
        SubStatus.expired => 'Expired',
      };

  Color get color => switch (this) {
        SubStatus.active => const Color(0xFF16A34A),
        SubStatus.expiringSoon => const Color(0xFFF59E0B),
        SubStatus.expired => const Color(0xFFDC2626),
      };
}

/// ============================================================
///  Personal finance
/// ============================================================

/// ----- Monthly category budget -----
class Budget {
  final String id;
  final String categoryId;
  final double limit; // Monthly limit in the base currency.
  final TxnScope scope;
  final bool enabled;

  const Budget({
    required this.id,
    required this.categoryId,
    required this.limit,
    this.scope = TxnScope.personal,
    this.enabled = true,
  });

  Budget copyWith({
    String? categoryId,
    double? limit,
    TxnScope? scope,
    bool? enabled,
  }) =>
      Budget(
        id: id,
        categoryId: categoryId ?? this.categoryId,
        limit: limit ?? this.limit,
        scope: scope ?? this.scope,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'categoryId': categoryId,
        'limit': limit,
        'scope': scope.name,
        'enabled': enabled,
      };

  factory Budget.fromMap(Map map) => Budget(
        id: '${map['id']}',
        categoryId: '${map['categoryId'] ?? ''}',
        limit: (map['limit'] as num?)?.toDouble() ?? 0,
        scope: TxnScope.values.firstWhere((v) => v.name == map['scope'],
            orElse: () => TxnScope.personal),
        enabled: map['enabled'] as bool? ?? true,
      );
}

/// Budget usage for the current month.
class BudgetUsage {
  final Budget budget;
  final String categoryName;
  final double spent;

  const BudgetUsage({
    required this.budget,
    required this.categoryName,
    required this.spent,
  });

  /// Usage ratio (0 to 1 and above).
  double get ratio => budget.limit <= 0 ? 0 : spent / budget.limit;

  double get remaining => budget.limit - spent;

  bool get isOver => spent > budget.limit;

  /// 0 = within limit, 1 = near limit, 2 = over limit.
  int get level => ratio >= 1 ? 2 : (ratio >= 0.8 ? 1 : 0);
}

/// ----- Recurring transaction (rent, internet, subscriptions, etc.) -----
enum RecurringPeriod { monthly, weekly, daily }

extension RecurringPeriodX on RecurringPeriod {
  String get label => switch (this) {
        RecurringPeriod.monthly => 'Monthly',
        RecurringPeriod.weekly => 'Weekly',
        RecurringPeriod.daily => 'Daily',
      };
}

class RecurringRule {
  final String id;
  final String title;
  final TxnKind kind;
  final TxnScope scope;
  final double amount;
  final String currency;
  final String? categoryId;
  final String? customerId;
  final String note;

  final RecurringPeriod period;

  /// Day of the Jalali month (1–31), used for monthly rules only.
  final int dayOfMonth;

  final DateTime startDate;
  final DateTime? endDate;
  final bool enabled;

  /// Last posting date (prevents duplicates).
  final DateTime? lastPosted;

  const RecurringRule({
    required this.id,
    required this.title,
    this.kind = TxnKind.expense,
    required this.amount,
    this.scope = TxnScope.personal,
    this.currency = 'IRT',
    this.categoryId,
    this.customerId,
    this.note = '',
    this.period = RecurringPeriod.monthly,
    this.dayOfMonth = 1,
    required this.startDate,
    this.endDate,
    this.enabled = true,
    this.lastPosted,
  });

  RecurringRule copyWith({
    String? title,
    TxnKind? kind,
    double? amount,
    TxnScope? scope,
    String? currency,
    String? categoryId,
    String? customerId,
    String? note,
    RecurringPeriod? period,
    int? dayOfMonth,
    DateTime? startDate,
    DateTime? endDate,
    bool? enabled,
    bool clearEndDate = false,
    DateTime? lastPosted,
    bool clearLastPosted = false,
  }) =>
      RecurringRule(
        id: id,
        title: title ?? this.title,
        kind: kind ?? this.kind,
        amount: amount ?? this.amount,
        scope: scope ?? this.scope,
        currency: currency ?? this.currency,
        categoryId: categoryId ?? this.categoryId,
        customerId: customerId ?? this.customerId,
        note: note ?? this.note,
        period: period ?? this.period,
        dayOfMonth: dayOfMonth ?? this.dayOfMonth,
        startDate: startDate ?? this.startDate,
        endDate: clearEndDate ? null : (endDate ?? this.endDate),
        enabled: enabled ?? this.enabled,
        lastPosted: clearLastPosted ? null : (lastPosted ?? this.lastPosted),
      );

  // ---------- Due-date calculations ----------
  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Number of days in a Jalali month.
  static int _monthLength(int y, int m) => Jalali(y, m).monthLength;

  /// Day of the month, clamped to the month length (for example, 31 → 29).
  int _dayIn(int y, int m) {
    final len = _monthLength(y, m);
    if (dayOfMonth < 1) return 1;
    return dayOfMonth > len ? len : dayOfMonth;
  }

  DateTime _advance(DateTime d) {
    switch (period) {
      case RecurringPeriod.daily:
        return _dateOnly(DateTime(d.year, d.month, d.day + 1));
      case RecurringPeriod.weekly:
        return _dateOnly(DateTime(d.year, d.month, d.day + 7));
      case RecurringPeriod.monthly:
        final j = Jalali.fromDateTime(d);
        var y = j.year;
        var m = j.month + 1;
        if (m > 12) {
          m = 1;
          y += 1;
        }
        return Jalali(y, m, _dayIn(y, m)).toDateTime();
    }
  }

  /// First occurrence, taking the selected day of the month into account.
  DateTime get _firstOccurrence {
    final start = _dateOnly(startDate);
    if (period != RecurringPeriod.monthly) return start;
    final j = Jalali.fromDateTime(start);
    final candidate = Jalali(j.year, j.month, _dayIn(j.year, j.month)).toDateTime();
    return candidate.isBefore(start) ? _advance(start) : candidate;
  }

  /// All occurrences of this rule from the start date through [to].
  List<DateTime> occurrencesUpTo(DateTime to, {int limit = 600}) {
    final out = <DateTime>[];
    final end = _dateOnly(to);
    final stop = endDate == null ? null : _dateOnly(endDate!);
    var cur = _firstOccurrence;
    var guard = 0;
    while (!cur.isAfter(end) && guard++ < limit) {
      if (stop != null && cur.isAfter(stop)) break;
      out.add(cur);
      cur = _advance(cur);
    }
    return out;
  }

  /// Due occurrences that have not yet been posted.
  List<DateTime> pendingDues(DateTime now) {
    if (!enabled) return const [];
    final first = _dateOnly(startDate);
    final from = lastPosted == null
        ? first
        : Jalali.fromDateTime(_dateOnly(DateTime(
                lastPosted!.year, lastPosted!.month, lastPosted!.day + 1)))
            .toDateTime();
    return occurrencesUpTo(now).where((d) => !d.isBefore(from)).toList();
  }

  /// Next due date for display in the UI.
  DateTime? nextDue(DateTime now) {
    if (!enabled) return null;
    final from = lastPosted ?? _dateOnly(startDate);
    final list = occurrencesUpTo(DateTime(now.year, now.month + 1, now.day),
        limit: 60);
    for (final d in list) {
      if (d.isAfter(_dateOnly(from))) return d;
    }
    return null;
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'kind': kind.name,
        'amount': amount,
        'scope': scope.name,
        'currency': currency,
        'categoryId': categoryId,
        'customerId': customerId,
        'note': note,
        'period': period.name,
        'dayOfMonth': dayOfMonth,
        'startDate': startDate.millisecondsSinceEpoch,
        'endDate': endDate?.millisecondsSinceEpoch,
        'enabled': enabled,
        'lastPosted': lastPosted?.millisecondsSinceEpoch,
      };

  factory RecurringRule.fromMap(Map map) => RecurringRule(
        id: '${map['id']}',
        title: '${map['title'] ?? ''}',
        kind: TxnKind.values.firstWhere((k) => k.name == map['kind'],
            orElse: () => TxnKind.expense),
        amount: (map['amount'] as num?)?.toDouble() ?? 0,
        scope: TxnScope.values.firstWhere((v) => v.name == map['scope'],
            orElse: () => TxnScope.personal),
        currency: '${map['currency'] ?? 'IRT'}',
        categoryId: map['categoryId'] as String?,
        customerId: map['customerId'] as String?,
        note: '${map['note'] ?? ''}',
        period: RecurringPeriod.values.firstWhere(
            (p) => p.name == map['period'],
            orElse: () => RecurringPeriod.monthly),
        dayOfMonth: (map['dayOfMonth'] as num?)?.toInt() ?? 1,
        startDate: DateTime.fromMillisecondsSinceEpoch(
            (map['startDate'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch),
        endDate: (map['endDate'] as num?) == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch((map['endDate'] as num).toInt()),
        enabled: map['enabled'] as bool? ?? true,
        lastPosted: (map['lastPosted'] as num?) == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                (map['lastPosted'] as num).toInt()),
      );
}

/// ----- Dashboard quick-entry button -----
class QuickExpense {
  final String id;
  final String label;

  /// If zero, ask for an amount when recording.
  final double amount;
  final TxnKind kind;
  final TxnScope scope;
  final String? categoryId;

  /// Icon code point (Icons.xxx.codePoint).
  final int iconCodePoint;
  final int sortOrder;

  const QuickExpense({
    required this.id,
    required this.label,
    this.amount = 0,
    this.kind = TxnKind.expense,
    this.scope = TxnScope.personal,
    this.categoryId,
    this.iconCodePoint = 0xe15b, // Icons.receipt_long_outlined
    this.sortOrder = 0,
  });

  bool get hasFixedAmount => amount > 0;

  QuickExpense copyWith({
    String? label,
    double? amount,
    TxnKind? kind,
    TxnScope? scope,
    String? categoryId,
    int? iconCodePoint,
    int? sortOrder,
  }) =>
      QuickExpense(
        id: id,
        label: label ?? this.label,
        amount: amount ?? this.amount,
        kind: kind ?? this.kind,
        scope: scope ?? this.scope,
        categoryId: categoryId ?? this.categoryId,
        iconCodePoint: iconCodePoint ?? this.iconCodePoint,
        sortOrder: sortOrder ?? this.sortOrder,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'amount': amount,
        'kind': kind.name,
        'scope': scope.name,
        'categoryId': categoryId,
        'iconCodePoint': iconCodePoint,
        'sortOrder': sortOrder,
      };

  factory QuickExpense.fromMap(Map map) => QuickExpense(
        id: '${map['id']}',
        label: '${map['label'] ?? ''}',
        amount: (map['amount'] as num?)?.toDouble() ?? 0,
        kind: TxnKind.values.firstWhere((k) => k.name == map['kind'],
            orElse: () => TxnKind.expense),
        scope: TxnScope.values.firstWhere((v) => v.name == map['scope'],
            orElse: () => TxnScope.personal),
        categoryId: map['categoryId'] as String?,
        iconCodePoint: (map['iconCodePoint'] as num?)?.toInt() ?? 0xe15b,
        sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
      );

  /// Default personal finance quick-entry buttons.
  static List<QuickExpense> defaults() => [
        QuickExpense(
            id: 'q_food',
            label: 'Food',
            iconCodePoint: 0xf0a6, // Icons.restaurant_outlined
            sortOrder: 0),
        QuickExpense(
            id: 'q_transport',
            label: 'Transport',
            iconCodePoint: 0xf8e9, // Icons.directions_bus_outlined
            sortOrder: 1),
        QuickExpense(
            id: 'q_market',
            label: 'Daily shopping',
            iconCodePoint: 0xf7bb, // Icons.shopping_bag_outlined
            sortOrder: 2),
        QuickExpense(
            id: 'q_bill',
            label: 'Bills',
            iconCodePoint: 0xf0ac, // Icons.receipt_outlined
            sortOrder: 3),
        QuickExpense(
            id: 'q_cafe',
            label: 'Cafe',
            iconCodePoint: 0xf0a8, // Icons.local_cafe_outlined
            sortOrder: 4),
        QuickExpense(
            id: 'q_health',
            label: 'Health',
            iconCodePoint: 0xf0ad, // Icons.local_hospital_outlined
            sortOrder: 5),
      ];
}
