// ============================================================
//  قوانین تشخیص پیامک بانکی
//
//  ساختارِ قانون‌محور است تا بتوان بعداً قانون جدید اضافه کرد
//  (یا از داخل برنامه، قانونِ اختصاصی ساخت).
// ============================================================

// واحدِ پیش‌فرضِ مبالغ در پیامک‌های آن بانک
enum AmountUnit { rial, toman }

class BankRule {
  /// شناسه (برای قوانین اختصاصی کاربر)
  final String id;

  /// نام فارسی بانک
  final String bankName;

  /// نشانه‌های فرستنده (مثل BANKMELAT) — با حروف بزرگ مقایسه می‌شود
  final List<String> senderHints;

  /// نشانه‌های داخل متن پیامک (مثل «بانک ملت»)
  final List<String> bodyHints;

  /// اگر در پیامک واحد ذکر نشده باشد، مبلغ را چه واحدی فرض کنیم؟
  final AmountUnit defaultUnit;

  /// قانونِ ساخته‌شده توسط کاربر (در صورت نیاز قابل حذف است)
  final bool custom;

  const BankRule({
    required this.id,
    required this.bankName,
    this.senderHints = const [],
    this.bodyHints = const [],
    this.defaultUnit = AmountUnit.rial,
    this.custom = false,
  });

  BankRule copyWith({
    String? bankName,
    List<String>? senderHints,
    List<String>? bodyHints,
    AmountUnit? defaultUnit,
  }) => BankRule(
    id: id,
    bankName: bankName ?? this.bankName,
    senderHints: senderHints ?? this.senderHints,
    bodyHints: bodyHints ?? this.bodyHints,
    defaultUnit: defaultUnit ?? this.defaultUnit,
    custom: custom,
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'bankName': bankName,
    'senderHints': senderHints,
    'bodyHints': bodyHints,
    'defaultUnit': defaultUnit.name,
    'custom': custom,
  };

  factory BankRule.fromMap(Map map) => BankRule(
    id: '${map['id']}',
    bankName: '${map['bankName'] ?? ''}',
    senderHints: (map['senderHints'] as List? ?? const [])
        .map((e) => '$e')
        .where((e) => e.isNotEmpty)
        .toList(),
    bodyHints: (map['bodyHints'] as List? ?? const [])
        .map((e) => '$e')
        .where((e) => e.isNotEmpty)
        .toList(),
    defaultUnit: AmountUnit.values.firstWhere(
      (u) => u.name == map['defaultUnit'],
      orElse: () => AmountUnit.rial,
    ),
    custom: map['custom'] as bool? ?? false,
  );
}

/// قوانینِ آماده برای بانک‌ها و کیف‌پول‌های رایج ایران
const List<BankRule> builtinBankRules = <BankRule>[
  BankRule(
    id: 'melat',
    bankName: 'بانک ملت',
    senderHints: ['BANKMELAT', 'MELLAT', 'ملت'],
    bodyHints: ['بانک ملت'],
  ),
  BankRule(
    id: 'saderat',
    bankName: 'بانک صادرات',
    senderHints: ['BSI', 'SADERAT', 'صادرات'],
    bodyHints: ['بانک صادرات'],
  ),
  BankRule(
    id: 'tejarat',
    bankName: 'بانک تجارت',
    senderHints: ['TEJARAT', 'تجارت'],
    bodyHints: ['بانک تجارت'],
  ),
  BankRule(
    id: 'melli',
    bankName: 'بانک ملی',
    senderHints: ['BANKMELLI', 'MELLIBANK', 'ملی'],
    bodyHints: ['بانک ملی'],
  ),
  BankRule(
    id: 'parsian',
    bankName: 'بانک پارسیان',
    senderHints: ['PARSIAN', 'BPI', 'پارسیان'],
    bodyHints: ['بانک پارسیان'],
  ),
  BankRule(
    id: 'saman',
    bankName: 'بانک سامان',
    senderHints: ['SAMAN', 'سامان'],
    bodyHints: ['بانک سامان'],
  ),
  BankRule(
    id: 'pasargad',
    bankName: 'بانک پاسارگاد',
    senderHints: ['PASARGAD', 'پاسارگاد'],
    bodyHints: ['بانک پاسارگاد'],
  ),
  BankRule(
    id: 'ayandeh',
    bankName: 'بانک آینده',
    senderHints: ['AYANDEH', 'ANSAR', 'آینده', 'انصار'],
    bodyHints: ['بانک آینده'],
  ),
  BankRule(
    id: 'resalat',
    bankName: 'بانک رسالت',
    senderHints: ['RESALAT', 'QMB', 'رسالت'],
    bodyHints: ['بانک رسالت'],
  ),
  BankRule(
    id: 'sina',
    bankName: 'بانک سینا / بلو',
    senderHints: ['SINA', 'BLU', 'سینا', 'بلو'],
    bodyHints: ['بانک سینا', 'بلوبانک'],
  ),
  BankRule(
    id: 'keshavarzi',
    bankName: 'بانک کشاورزی',
    senderHints: ['BKI', 'KESHAVARZI', 'AGRI', 'کشاورزی'],
    bodyHints: ['بانک کشاورزی'],
  ),
  BankRule(
    id: 'refah',
    bankName: 'بانک رفاه',
    senderHints: ['REFAH', 'رفاه'],
    bodyHints: ['بانک رفاه'],
  ),
  BankRule(
    id: 'shahr',
    bankName: 'بانک شهر',
    senderHints: ['BANK SHAHR', 'SHAHR', 'شهر'],
    bodyHints: ['بانک شهر'],
  ),
  BankRule(
    id: 'karafarin',
    bankName: 'بانک کارآفرین',
    senderHints: ['KARAFARIN', 'کارآفرین'],
    bodyHints: ['بانک کارآفرین'],
  ),
  BankRule(
    id: 'sarmaye',
    bankName: 'بانک سرمایه',
    senderHints: ['SARMAYEH', 'سرمایه'],
    bodyHints: ['بانک سرمایه'],
  ),
  BankRule(
    id: 'sepah',
    bankName: 'بانک سپه',
    senderHints: ['SEPAH', 'سپه'],
    bodyHints: ['بانک سپه'],
  ),
  BankRule(
    id: 'postbank',
    bankName: 'پست‌بانک',
    senderHints: ['POSTBANK', 'پست بانک'],
    bodyHints: ['پست بانک'],
  ),
  BankRule(
    id: 'iranzamin',
    bankName: 'بانک ایران‌زمین',
    senderHints: ['IRANZAMIN', 'IZB', 'ایران زمین'],
    bodyHints: ['بانک ایران زمین'],
  ),
  BankRule(
    id: 'day',
    bankName: 'بانک دی',
    senderHints: ['BANK DAY', 'DAYBANK', 'دی'],
    bodyHints: ['بانک دی'],
  ),
  BankRule(
    id: 'tourism',
    bankName: 'بانک گردشگری',
    senderHints: ['TOURISM', 'GARDESH', 'گردشگری'],
    bodyHints: ['بانک گردشگری'],
  ),
  BankRule(
    id: 'mehr',
    bankName: 'بانک مهر / قرض‌الحسنه',
    senderHints: ['MEHRBANK', 'QARZ', 'مهر'],
    bodyHints: ['بانک مهر', 'قرض الحسنه'],
  ),
  BankRule(
    id: 'mellat_wallet',
    bankName: 'کیف‌پول / اپلیکیشن پرداخت',
    senderHints: ['JIBJET', 'TOOMAN', 'TOMAN', 'APPAY', 'جیب جت', 'تومن'],
    bodyHints: ['کیف پول', 'جیب جت'],
    defaultUnit: AmountUnit.toman,
  ),
];
