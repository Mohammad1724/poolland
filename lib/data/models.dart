import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../core/format_utils.dart';

/// ============================================================
///  مدل‌های داده‌ی «دفتر وی‌پی‌ان»
///  همه‌ی مدل‌ها به‌صورت Map ذخیره می‌شوند (سازگار با Hive و JSON)
/// ============================================================

/// ----- ارز -----
class CurrencyDef {
  final String code; // IRT, USD, USDT, EUR ...
  final String name; // تومان، دلار ...
  final String symbol; // تومان، $ ...
  final double rateToBase; // هر ۱ واحد از این ارز = چند واحد ارز پایه
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

/// ----- تنظیمات برنامه -----
class AppSettings {
  final String businessName;
  final String baseCurrency; // کد ارز پایه (پیش‌فرض IRT = تومان)
  final List<CurrencyDef> currencies;
  final bool persianDigits;
  final int reminderDays; // چند روز قبل از انقضا هشدار بده
  final String? pinHash; // قفل برنامه (اختیاری)
  final String themeMode; // system | light | dark
  final double openingCash; // موجودی نقدی/بانکی اولیه
  final bool setupDone; // آیا راه‌اندازی اولیه انجام شده؟

  // ---- پیامک بانکی ----
  final bool smsEnabled; // خواندن پیامک فعال باشد؟
  final int smsSyncDays; // چند روز گذشته بررسی شود
  final bool smsAutoApprove; // ثبت خودکار موارد کاملاً مطمئن
  final int smsLastSyncAt; // آخرین همگام‌سازی (برای به‌روزرسانی افزایشی)

  const AppSettings({
    this.businessName = 'فروش وی‌پی‌ان من',
    this.baseCurrency = 'IRT',
    this.currencies = defaultCurrencies,
    this.persianDigits = true,
    this.reminderDays = 3,
    this.pinHash,
    this.themeMode = 'system',
    this.openingCash = 0,
    this.setupDone = false,
    this.smsEnabled = false,
    this.smsSyncDays = 90,
    this.smsAutoApprove = false,
    this.smsLastSyncAt = 0,
  });

  /// ارزهای پیش‌فرض: تومان (پایه) + ارزهای رایج برای فروشنده‌ی VPN
  static const defaultCurrencies = <CurrencyDef>[
    CurrencyDef(code: 'IRT', name: 'تومان', symbol: 'تومان', rateToBase: 1, decimals: 0),
    CurrencyDef(code: 'USD', name: 'دلار', symbol: r'$', rateToBase: 130000, decimals: 2),
    CurrencyDef(code: 'USDT', name: 'تتر', symbol: 'USDT', rateToBase: 130000, decimals: 2),
    CurrencyDef(code: 'EUR', name: 'یورو', symbol: '€', rateToBase: 140000, decimals: 2),
  ];

  CurrencyDef currency(String code) => currencies.firstWhere(
        (c) => c.code == code,
        orElse: () => currencies.isNotEmpty
            ? currencies.first
            : const CurrencyDef(code: 'IRT', name: 'تومان', symbol: 'تومان', rateToBase: 1),
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
      };

  factory AppSettings.fromMap(Map map) => AppSettings(
        businessName: '${map['businessName'] ?? 'فروش وی‌پی‌ان من'}',
        baseCurrency: '${map['baseCurrency'] ?? 'IRT'}',
        currencies: (map['currencies'] as List?)
                ?.map((e) => CurrencyDef.fromMap(Map.from(e as Map)))
                .toList() ??
            defaultCurrencies,
        persianDigits: map['persianDigits'] as bool? ?? true,
        reminderDays: (map['reminderDays'] as num?)?.toInt() ?? 3,
        pinHash: map['pinHash'] as String?,
        themeMode: '${map['themeMode'] ?? 'system'}',
        openingCash: (map['openingCash'] as num?)?.toDouble() ?? 0,
        setupDone: map['setupDone'] as bool? ?? false,
        smsEnabled: map['smsEnabled'] as bool? ?? false,
        smsSyncDays: (map['smsSyncDays'] as num?)?.toInt() ?? 90,
        smsAutoApprove: map['smsAutoApprove'] as bool? ?? false,
        smsLastSyncAt: (map['smsLastSyncAt'] as num?)?.toInt() ?? 0,
      );
}

/// ----- دسته‌بندی درآمد/هزینه -----
class Category {
  final String id;
  final String name;
  final TxnKind kind; // فقط income و expense معنی دارند
  final int sortOrder;

  const Category({
    required this.id,
    required this.name,
    required this.kind,
    this.sortOrder = 0,
  });

  Map<String, dynamic> toMap() =>
      {'id': id, 'name': name, 'kind': kind.name, 'sortOrder': sortOrder};

  factory Category.fromMap(Map map) => Category(
        id: '${map['id']}',
        name: '${map['name']}',
        kind: TxnKind.values.firstWhere((k) => k.name == map['kind'],
            orElse: () => TxnKind.expense),
        sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
      );
}

/// ----- طرف حساب (مشتری / تأمین‌کننده) -----
class Customer {
  final String id;
  final String name;
  final String phone;
  final String telegram;
  final String note;
  final double openingBalance; // + یعنی از قبل بدهکار بوده، − یعنی از قبل بستانکار
  final DateTime createdAt;
  final bool archived;

  /// شناسه‌های بانکی این مشتری برای تطبیق خودکار پیامک‌ها
  /// (مثلاً ۴ رقم آخر کارت یا شماره کامل کارت)
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

/// ----- اشتراک -----
class Subscription {
  final String id;
  final String customerId;
  final String? planId; // پلن انتخاب‌شده (اختیاری)
  final String planName; // مثلاً: ۱ ماهه ۵۰ گیگ - دو کاربره
  final DateTime startDate;
  final DateTime endDate;
  final double amount; // مبلغ فروش
  final String currency; // کد ارز
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

/// ----- پلن آماده (قالب فروش) -----
enum PlanDurationUnit { day, month }

class Plan {
  final String id;
  final String name; // مثلاً: ۱ ماهه ۵۰ گیگ
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
      '${Fmt.toFaDigits('$durationValue')} ${durationUnit == PlanDurationUnit.month ? 'ماه' : 'روز'}';

  /// تاریخ پایان بر اساس تاریخ شروع (ماه‌ها شمسی هستند)
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

/// ----- انواع تراکنش -----
enum TxnKind {
  income, // فروش / درآمد
  expense, // هزینه
  receive, // دریافت پول از مشتری (تسویه)
  refund, // پرداخت/برگشت پول به مشتری
}

extension TxnKindX on TxnKind {
  String get label => switch (this) {
        TxnKind.income => 'فروش / درآمد',
        TxnKind.expense => 'هزینه',
        TxnKind.receive => 'دریافت از مشتری',
        TxnKind.refund => 'پرداخت به مشتری',
      };

  String get shortLabel => switch (this) {
        TxnKind.income => 'درآمد',
        TxnKind.expense => 'هزینه',
        TxnKind.receive => 'دریافت',
        TxnKind.refund => 'پرداخت',
      };

  IconData get icon => switch (this) {
        TxnKind.income => Icons.trending_up_rounded,
        TxnKind.expense => Icons.trending_down_rounded,
        TxnKind.receive => Icons.call_received_rounded,
        TxnKind.refund => Icons.call_made_rounded,
      };

  bool get isProfitKind => this == TxnKind.income || this == TxnKind.expense;

  /// آیا این تراکنش روی حساب طرف حساب اثر دارد؟
  bool get affectsBalance => this != TxnKind.income && this != TxnKind.expense;

  /// جهت پول نقد: +۱ ورود، −۱ خروج، ۰ بی‌اثر
  int get cashDirection => switch (this) {
        TxnKind.receive => 1,
        TxnKind.refund => -1,
        _ => 0,
      };
}

/// ----- تراکنش -----
class Txn {
  final String id;
  final TxnKind kind;
  final double amount;
  final String currency; // کد ارز تراکنش
  final double rateToBase; // نرخ ارز به ارز پایه، در لحظه‌ی ثبت (اسنپ‌شات)
  final DateTime date;
  final String? categoryId;
  final String? customerId;
  final String? subscriptionId;
  final bool credit; // برای درآمد/هزینه: true یعنی «نسیه / روی حساب»
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
        note: '${map['note'] ?? ''}',
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            (map['createdAt'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch),
      );
}

/// ----- وضعیت اشتراک -----
enum SubStatus { active, expiringSoon, expired }

extension SubStatusX on SubStatus {
  String get label => switch (this) {
        SubStatus.active => 'فعال',
        SubStatus.expiringSoon => 'نزدیک انقضا',
        SubStatus.expired => 'منقضی',
      };

  Color get color => switch (this) {
        SubStatus.active => const Color(0xFF16A34A),
        SubStatus.expiringSoon => const Color(0xFFF59E0B),
        SubStatus.expired => const Color(0xFFDC2626),
      };
}
