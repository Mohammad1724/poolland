// ============================================================
//  مدل‌های مربوط به پیامک‌های بانکی
//  بدون وابستگی به فلاتر و پلتفرم (کاملاً قابل تست)
// ============================================================

// جهت حرکت پول در پیامک
enum SmsDirection {
  deposit, // واریز به حساب ما (پول وارد شده)
  withdraw, // برداشت / خرید / پرداخت (پول خارج شده)
  unknown;

  String get label => switch (this) {
    SmsDirection.deposit => 'واریز',
    SmsDirection.withdraw => 'برداشت / خرید',
    SmsDirection.unknown => 'نامشخص',
  };
}

/// یک پیامک خامِ خوانده‌شده از دستگاه (اندروید)
class SmsMessage {
  final String id;
  final String address; // فرستنده: BANKMELAT یا شماره
  final String body;
  final DateTime date;

  const SmsMessage({
    required this.id,
    required this.address,
    required this.body,
    required this.date,
  });

  /// کلید یکتا برای تشخیص تکراری‌ها
  ///
  /// نکتهٔ مهم: این کلید بر اساس «محتوا» ساخته می‌شود نه شناسه‌ی پیامک،
  /// چون یک پیامک ممکن است دو بار (یک بار از گیرنده و یک بار از صندوق پیامک‌ها)
  /// به برنامه برسد و شناسه‌های متفاوتی داشته باشد.
  String get key {
    final minuteBucket = date.millisecondsSinceEpoch ~/ 60000;
    return '${address.trim()}|$minuteBucket|$body';
  }

  factory SmsMessage.fromMap(Map<dynamic, dynamic> map) => SmsMessage(
    id: '${map['id'] ?? ''}',
    address: '${map['address'] ?? ''}',
    body: '${map['body'] ?? ''}',
    date: DateTime.fromMillisecondsSinceEpoch(
      (map['date'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
    ),
  );

  Map<String, dynamic> toMap() => {
    'id': id,
    'address': address,
    'body': body,
    'date': date.millisecondsSinceEpoch,
  };
}

/// نتیجه‌ی تجزیه‌ی یک پیامک
class ParsedSms {
  final SmsMessage message;

  /// نام بانک (اگر شناسایی شده باشد)
  final String? bankName;

  /// مبلغ به «تومان» (اگر پیامک به ریال بوده، تبدیل شده است)
  final double amount;

  /// ارز مبلغ (معمولاً IRT)
  final String currency;

  final SmsDirection direction;

  /// شماره کارت به صورت ماسک‌شده (مثل 6104********1234)
  final String? cardMask;

  /// ارقام خالصِ کارت (برای تطبیق با مشتری)
  final String cardDigits;

  /// مانده‌ی اعلام‌شده در پیامک (به تومان)
  final double? balance;

  /// شماره پیگیری / مرجع (در صورت وجود)
  final String? reference;

  /// آیا پارسینگ به اندازه‌ی کافی مطمئن است؟
  final bool confident;

  /// توضیح کوتاه درباره‌ی نحوه‌ی تشخیص
  final String note;

  const ParsedSms({
    required this.message,
    this.bankName,
    this.amount = 0,
    this.currency = 'IRT',
    this.direction = SmsDirection.unknown,
    this.cardMask,
    this.cardDigits = '',
    this.balance,
    this.reference,
    this.confident = false,
    this.note = '',
  });

  String get key => message.key;

  /// آیا اصلاً یک تراکنش مالی است؟ (قابل نمایش در صف بررسی)
  bool get isTransaction => amount > 0 && direction != SmsDirection.unknown;

  /// نوع تراکنش پیشنهادی در دفتر
  /// واریز → دریافت از مشتری / درآمد · برداشت → هزینه
  String get suggestedKindLabel => switch (direction) {
    SmsDirection.deposit => 'دریافت از مشتری',
    SmsDirection.withdraw => 'هزینه',
    SmsDirection.unknown => 'نامشخص',
  };
}
