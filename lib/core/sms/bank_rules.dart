// ============================================================
//  Bank SMS detection rules.
//
//  This rule-based structure makes it easy to add more rules later
//  (including custom rules created in the app).
// ============================================================

// Default amount unit used by this bank’s SMS messages.
enum AmountUnit { rial, toman }

class BankRule {
  /// Stable identifier for this built-in or custom rule.
  final String id;

  /// Bank name shown in the app.
  final String bankName;

  /// Sender hints (such as BANKMELAT); compared in uppercase.
  final List<String> senderHints;

  /// Hints in the SMS body (for example, a bank name in Persian).
  final List<String> bodyHints;

  /// Which unit to assume when the SMS does not specify one.
  final AmountUnit defaultUnit;

  /// Whether this is a user-created rule (which can be deleted).
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

/// Built-in rules for common Iranian banks.
/// Wallet and payment-app senders require an explicit custom rule.
const List<BankRule> builtinBankRules = <BankRule>[
  BankRule(
    id: 'melat',
    bankName: 'Mellat Bank',
    senderHints: ['BANKMELAT', 'MELLAT', 'ملت'],
    bodyHints: ['بانک ملت'],
  ),
  BankRule(
    id: 'saderat',
    bankName: 'Saderat Bank',
    senderHints: ['BSI', 'SADERAT', 'صادرات'],
    bodyHints: ['بانک صادرات'],
  ),
  BankRule(
    id: 'tejarat',
    bankName: 'Tejarat Bank',
    senderHints: ['TEJARAT', 'تجارت'],
    bodyHints: ['بانک تجارت'],
  ),
  BankRule(
    id: 'melli',
    bankName: 'Melli Bank',
    senderHints: ['BANKMELLI', 'MELLIBANK', 'ملی'],
    bodyHints: ['بانک ملی'],
  ),
  BankRule(
    id: 'parsian',
    bankName: 'Parsian Bank',
    senderHints: ['PARSIAN', 'BPI', 'پارسیان'],
    bodyHints: ['بانک پارسیان'],
  ),
  BankRule(
    id: 'saman',
    bankName: 'Saman Bank',
    senderHints: ['SAMAN', 'سامان'],
    bodyHints: ['بانک سامان'],
  ),
  BankRule(
    id: 'pasargad',
    bankName: 'Pasargad Bank',
    senderHints: ['PASARGAD', 'پاسارگاد'],
    bodyHints: ['بانک پاسارگاد'],
  ),
  BankRule(
    id: 'ayandeh',
    bankName: 'Ayandeh Bank',
    senderHints: ['AYANDEH', 'ANSAR', 'آینده', 'انصار'],
    bodyHints: ['بانک آینده'],
  ),
  BankRule(
    id: 'resalat',
    bankName: 'Resalat Bank',
    senderHints: ['RESALAT', 'QMB', 'رسالت'],
    bodyHints: ['بانک رسالت'],
  ),
  BankRule(
    id: 'sina',
    bankName: 'Sina Bank / Blu Bank',
    senderHints: ['SINA', 'BLU', 'سینا', 'بلو'],
    bodyHints: ['بانک سینا', 'بلوبانک'],
  ),
  BankRule(
    id: 'keshavarzi',
    bankName: 'Keshavarzi Bank',
    senderHints: ['BKI', 'KESHAVARZI', 'AGRI', 'کشاورزی'],
    bodyHints: ['بانک کشاورزی'],
  ),
  BankRule(
    id: 'refah',
    bankName: 'Refah Bank',
    senderHints: ['REFAH', 'رفاه'],
    bodyHints: ['بانک رفاه'],
  ),
  BankRule(
    id: 'shahr',
    bankName: 'Shahr Bank',
    senderHints: ['BANK SHAHR', 'SHAHR', 'شهر'],
    bodyHints: ['بانک شهر'],
  ),
  BankRule(
    id: 'karafarin',
    bankName: 'Karafarin Bank',
    senderHints: ['KARAFARIN', 'کارآفرین'],
    bodyHints: ['بانک کارآفرین'],
  ),
  BankRule(
    id: 'sarmaye',
    bankName: 'Sarmayeh Bank',
    senderHints: ['SARMAYEH', 'سرمایه'],
    bodyHints: ['بانک سرمایه'],
  ),
  BankRule(
    id: 'sepah',
    bankName: 'Sepah Bank',
    senderHints: ['SEPAH', 'سپه'],
    bodyHints: ['بانک سپه'],
  ),
  BankRule(
    id: 'postbank',
    bankName: 'Post Bank',
    senderHints: ['POSTBANK', 'پست بانک'],
    bodyHints: ['پست بانک'],
  ),
  BankRule(
    id: 'iranzamin',
    bankName: 'Iran Zamin Bank',
    senderHints: ['IRANZAMIN', 'IZB', 'ایران زمین'],
    bodyHints: ['بانک ایران زمین'],
  ),
  BankRule(
    id: 'day',
    bankName: 'Day Bank',
    senderHints: ['BANK DAY', 'DAYBANK', 'دی'],
    bodyHints: ['بانک دی'],
  ),
  BankRule(
    id: 'tourism',
    bankName: 'Tourism Bank',
    senderHints: ['TOURISM', 'GARDESH', 'گردشگری'],
    bodyHints: ['بانک گردشگری'],
  ),
  BankRule(
    id: 'mehr',
    bankName: 'Mehr Bank / Qarz al-Hasaneh',
    senderHints: ['MEHRBANK', 'QARZ', 'مهر'],
    bodyHints: ['بانک مهر', 'قرض الحسنه'],
  ),
];
