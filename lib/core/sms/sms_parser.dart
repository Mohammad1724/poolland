import 'bank_rules.dart';
import 'sms_models.dart';

/// ============================================================
///  موتور تجزیه‌ی پیامک بانکی (تابع خالص — قابل تست)
///
///  وظایف:
///   ۱. نرمال‌سازی متن (ارقام عربی/فارسی، نیم‌فاصله، ی/ک)
///   ۲. فیلتر پیامک‌های غیرمالی (رمز یک‌بار، کد تایید، اطلاع‌رسانی…)
///   ۳. تشخیص بانک از روی فرستنده یا متن
///   ۴. تشخیص جهت: واریز / برداشت
///   ۵. استخراج مبلغ + تبدیل «ریال به تومان»
///   ۶. استخراج کارت، مانده و شماره پیگیری
/// ============================================================
class SmsParser {
  SmsParser._();

  // ---------------------------------------------------------
  // واژگان
  // ---------------------------------------------------------

  /// پیامک‌هایی که تراکنش مالی نیستند
  static const List<String> ignoreKeywords = <String>[
    'رمز',
    'otp',
    'one-time',
    'فعال سازی',
    'فعال‌سازی',
    'غیرفعال',
    'خبرنامه',
    'تبریک',
    'قرعه',
    'مسدود',
    'احراز هویت',
    'کلمه عبور',
    'کد تایید',
    'کد تأیید',
    'کد ورود',
    'کد فعالسازی',
    'ورود به',
  ];

  static const List<String> withdrawWords = <String>[
    'برداشت',
    'خرید',
    'خريد',
    'پرداخت',
    'کاهش موجودی',
    'حوله',
    'اقساط',
    'کارمزد',
    'withdraw',
    'purchase',
    'debit',
  ];

  static const List<String> depositWords = <String>[
    'واریز',
    'واريز',
    'وصول',
    'افزایش موجودی',
    'افزايش موجودي',
    'دریافت وجه',
    'دريافت وجه',
    'سود سپرده',
    'انتقال ورودی',
    'deposit',
    'credited',
  ];

  // ---------------------------------------------------------
  // الگوها
  // ---------------------------------------------------------
  static final RegExp _numberRe = RegExp(
    r'[0-9\u06F0-\u06F9\u0660-\u0669][0-9\u06F0-\u06F9\u0660-\u0669,\u066C\u200c ]*',
  );

  static final RegExp _amountKeywordRe = RegExp(
    r'(?:مبلغ|مبلغ کل|amount)[^0-9\u06F0-\u06F9\u0660-\u0669]{0,10}([0-9\u06F0-\u06F9\u0660-\u0669][0-9\u06F0-\u06F9\u0660-\u0669,\u066C\u200c ]*)',
    caseSensitive: false,
  );

  static final RegExp _balanceRe = RegExp(
    r'(?:مانده|موجودی|موجودي|balance)[^0-9\u06F0-\u06F9\u0660-\u0669]{0,10}([0-9\u06F0-\u06F9\u0660-\u0669][0-9\u06F0-\u06F9\u0660-\u0669,\u066C\u200c ]*)',
    caseSensitive: false,
  );

  static final RegExp _cardStarRe = RegExp(
    r'[0-9\u06F0-\u06F9\u0660-\u0669]*\*{2,}[0-9\u06F0-\u06F9\u0660-\u0669]*',
  );

  static final RegExp _cardWordRe = RegExp(
    r'(?:کارت|كارت|card)[^0-9\u06F0-\u06F9\u0660-\u0669*]{0,8}([0-9\u06F0-\u06F9\u0660-\u0669*]{4,})',
    caseSensitive: false,
  );

  static final RegExp _refRe = RegExp(
    r'(?:پیگیری|پيگيري|مرجع|سریال|سريال|ref|reference|sequence)[^0-9\u06F0-\u06F9\u0660-\u0669]{0,8}([0-9\u06F0-\u06F9\u0660-\u0669]{4,})',
    caseSensitive: false,
  );

  // ---------------------------------------------------------
  // نرمال‌سازی
  // ---------------------------------------------------------
  static String normalize(String input) {
    var s = input;
    s = s
        .replaceAll('ي', 'ی')
        .replaceAll('ك', 'ک')
        .replaceAll('ۀ', 'ه')
        .replaceAll('ة', 'ه')
        .replaceAll('\u200c', ' ')
        .replaceAll('\u200f', '')
        .replaceAll('\ufeff', '');
    return s;
  }

  /// ارقام عربی/فارسی → لاتین
  static String toLatinDigits(String input) {
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    const ar = '٠١٢٣٤٥٦٧٨٩';
    var s = input;
    for (var i = 0; i < 10; i++) {
      s = s.replaceAll(fa[i], '$i').replaceAll(ar[i], '$i');
    }
    return s;
  }

  static double _toDouble(String raw) {
    var s = toLatinDigits(raw).replaceAll(RegExp(r'[^0-9.]'), '');
    while (s.endsWith('.')) {
      s = s.substring(0, s.length - 1);
    }
    return double.tryParse(s) ?? 0;
  }

  /// فقط ارقام (برای مقایسه‌ی کارت/شناسه)
  static String digitsOnly(String input) =>
      toLatinDigits(input).replaceAll(RegExp(r'[^0-9]'), '');

  // ---------------------------------------------------------
  // API اصلی
  // ---------------------------------------------------------
  static ParsedSms parse(
    SmsMessage msg, {
    List<BankRule> extraRules = const <BankRule>[],
  }) {
    final body = normalize(msg.body);
    final address = normalize(msg.address).toUpperCase();
    final rule = findRule(address, body, extraRules);

    if (isIgnored(body)) {
      return ParsedSms(
        message: msg,
        bankName: rule?.bankName,
        note: 'پیامک غیرتراکنشی (رمز، کد یا اطلاع‌رسانی)',
      );
    }

    final direction = detectDirection(body);
    final amount = _extractAmount(body, rule);
    final balance = _extractBalance(body, rule);
    final card = _extractCard(body);
    final ref = _extractReference(body);
    final cardDigits = card == null ? '' : digitsOnly(card);

    final confident =
        direction != SmsDirection.unknown &&
        amount.value > 0 &&
        (rule != null || amount.unit != '');

    return ParsedSms(
      message: msg,
      bankName: rule?.bankName,
      amount: amount.value,
      currency: amount.currency,
      direction: direction,
      cardMask: card,
      cardDigits: cardDigits,
      balance: balance,
      reference: ref,
      confident: confident,
      note: _buildNote(rule, amount, direction),
    );
  }

  static List<ParsedSms> parseAll(
    Iterable<SmsMessage> messages, {
    List<BankRule> extraRules = const <BankRule>[],
  }) => messages.map((m) => parse(m, extraRules: extraRules)).toList();

  // ---------------------------------------------------------
  // تشخیص بانک
  // ---------------------------------------------------------
  static BankRule? findRule(
    String upperAddress,
    String body,
    List<BankRule> extraRules,
  ) {
    // قوانین اختصاصی کاربر اولویت دارند
    for (final rule in [...extraRules, ...builtinBankRules]) {
      for (final hint in rule.senderHints) {
        final h = normalize(hint).toUpperCase();
        if (h.isEmpty) continue;
        if (upperAddress == h) return rule;
        if (h.length >= 4 && upperAddress.contains(h)) return rule;
      }
    }
    for (final rule in [...extraRules, ...builtinBankRules]) {
      for (final hint in rule.bodyHints) {
        if (hint.isNotEmpty && body.contains(normalize(hint))) return rule;
      }
    }
    return null;
  }

  // ---------------------------------------------------------
  // فیلتر پیامک‌های غیرمالی
  // ---------------------------------------------------------
  static bool isIgnored(String body) {
    for (final w in ignoreKeywords) {
      if (body.contains(w)) return true;
    }
    return false;
  }

  // ---------------------------------------------------------
  // جهت تراکنش
  // ---------------------------------------------------------
  static SmsDirection detectDirection(String body) {
    for (final w in withdrawWords) {
      if (body.contains(w)) return SmsDirection.withdraw;
    }
    for (final w in depositWords) {
      if (body.contains(w)) return SmsDirection.deposit;
    }
    if (body.contains('انتقال')) return SmsDirection.withdraw;
    if (body.contains('شارژ')) return SmsDirection.deposit;
    return SmsDirection.unknown;
  }

  // ---------------------------------------------------------
  // مبلغ
  // ---------------------------------------------------------
  static _Amount _extractAmount(String body, BankRule? rule) {
    // ۱) بعد از واژه‌ی «مبلغ / amount»
    final kw = _amountKeywordRe.firstMatch(body);
    if (kw != null) {
      final v = _toDouble(kw.group(1)!.trim());
      if (v > 0) return _convert(v, _unitAfter(body, kw.end), rule);
    }

    // ۲) عددی که بلافاصله واحد پول دارد
    for (final m in _numberRe.allMatches(body)) {
      if (_isExcluded(body, m)) continue;
      final unit = _unitAfter(body, m.end);
      if (unit.isNotEmpty) {
        final v = _toDouble(m.group(0)!.trim());
        if (v > 0) return _convert(v, unit, rule);
      }
    }

    // ۳) اولین عددِ قابل‌توجهِ باقی‌مانده
    double? fallback;
    for (final m in _numberRe.allMatches(body)) {
      if (_isExcluded(body, m)) continue;
      final v = _toDouble(m.group(0)!.trim());
      if (v >= 1000) return _convert(v, '', rule);
      fallback ??= v;
    }
    if (fallback != null && fallback > 0) {
      return _convert(fallback, '', rule);
    }
    return const _Amount(0, 'IRT', '');
  }

  static _Amount _convert(double value, String unit, BankRule? rule) {
    switch (unit) {
      case 'rial':
        return _Amount(value / 10, 'IRT', 'rial');
      case 'usd':
        return _Amount(value, 'USD', 'usd');
      case 'eur':
        return _Amount(value, 'EUR', 'eur');
      case 'toman':
        return _Amount(value, 'IRT', 'toman');
      default:
        // واحد ذکر نشده → واحد پیش‌فرضِ بانک
        if (rule != null && rule.defaultUnit == AmountUnit.rial) {
          return _Amount(value / 10, 'IRT', 'rial?');
        }
        return _Amount(value, 'IRT', 'toman?');
    }
  }

  /// واحد پول در ۱۶ کاراکترِ بعد از عدد
  static String _unitAfter(String body, int endIndex) {
    if (endIndex >= body.length) return '';
    final tail = body
        .substring(endIndex, (endIndex + 16).clamp(0, body.length))
        .toLowerCase();
    if (tail.contains('ریال') ||
        tail.contains('ريال') ||
        tail.contains('rial')) {
      return 'rial';
    }
    if (tail.contains('تومان') || tail.contains('toman')) return 'toman';
    if (tail.contains('دلار') ||
        tail.contains('dollar') ||
        tail.contains('usd')) {
      return 'usd';
    }
    if (tail.contains('یورو') || tail.contains('euro')) return 'eur';
    return '';
  }

  /// آیا این عدد نباید به‌عنوان مبلغ در نظر گرفته شود؟
  /// (تاریخ، بخشی از شماره کارت، مانده حساب، شماره پیگیری)
  static bool _isExcluded(String body, Match m) {
    final start = m.start;
    final end = m.end;

    // چسبیده به ستاره (بخشی از شماره کارت)
    if (start > 0 && body[start - 1] == '*') return true;
    if (end < body.length && body[end] == '*') return true;

    // بخشی از تاریخ: 1405/07/12 یا 12-07
    final after = end < body.length ? body[end] : '';
    final before = start > 0 ? body[start - 1] : '';
    if ((after == '/' || after == '-') && end + 1 < body.length) {
      final c = body[end + 1];
      if (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) return true;
    }
    if (before == '/' || before == '-') return true;

    // مانده/موجودی
    final headStart = (start - 12).clamp(0, body.length);
    final head = body.substring(headStart, start);
    if (head.contains('مانده') ||
        head.contains('موجودی') ||
        head.contains('موجودي')) {
      return true;
    }

    // شماره پیگیری
    if (head.contains('پیگیری') ||
        head.contains('پيگيري') ||
        head.contains('سریال')) {
      return true;
    }
    return false;
  }

  // ---------------------------------------------------------
  // مانده حساب
  // ---------------------------------------------------------
  static double? _extractBalance(String body, BankRule? rule) {
    final m = _balanceRe.firstMatch(body);
    if (m == null) return null;
    final v = _toDouble(m.group(1)!.trim());
    if (v <= 0) return null;
    final converted = _convert(v, _unitAfter(body, m.end), rule);
    return converted.value;
  }

  // ---------------------------------------------------------
  // شماره کارت
  // ---------------------------------------------------------
  static String? _extractCard(String body) {
    final star = _cardStarRe.firstMatch(body);
    if (star != null) {
      final raw = star.group(0)!.trim();
      final digits = digitsOnly(raw);
      if (digits.length >= 4) return raw;
    }
    final word = _cardWordRe.firstMatch(body);
    if (word != null) {
      final raw = word.group(1)!.trim();
      if (digitsOnly(raw).length >= 4) return raw;
    }
    return null;
  }

  // ---------------------------------------------------------
  // شماره پیگیری
  // ---------------------------------------------------------
  static String? _extractReference(String body) {
    final m = _refRe.firstMatch(body);
    if (m == null) return null;
    final v = m.group(1)!.trim();
    return v.isEmpty ? null : v;
  }

  // ---------------------------------------------------------
  // تطبیق با مشتری (نگاشت کارت/شماره)
  // ---------------------------------------------------------
  /// آیا این پیامک به یکی از شناسه‌های بانکیِ مشتری می‌خورد؟
  static bool matchesIdentifiers(ParsedSms sms, List<String> identifiers) {
    final body = normalize(sms.message.body);
    final cardDigits = sms.cardDigits;
    final bodyDigits = digitsOnly(body);

    for (final raw in identifiers) {
      final id = digitsOnly(raw);
      if (id.length < 4) continue;
      // اولویت با ارقامِ خودِ کارت (کمترین احتمال اشتباه)
      if (cardDigits.isNotEmpty && cardDigits.contains(id)) return true;
      if (cardDigits.isEmpty && bodyDigits.contains(id)) return true;
    }
    return false;
  }

  static String _buildNote(BankRule? rule, _Amount amount, SmsDirection dir) {
    final parts = <String>[];
    if (rule != null) parts.add(rule.bankName);
    if (amount.unit == 'rial') parts.add('مبلغ از ریال به تومان تبدیل شد');
    if (amount.unit == 'rial?') parts.add('مبلغ ریال فرض شد (طبق قانون بانک)');
    if (dir == SmsDirection.unknown) parts.add('جهت تراکنش مشخص نیست');
    return parts.join(' · ');
  }
}

/// نتیجه‌ی استخراج مبلغ (به تومان + ارز + واحد تشخیص‌داده‌شده)
class _Amount {
  final double value;
  final String currency;
  final String unit;
  const _Amount(this.value, this.currency, this.unit);
}
