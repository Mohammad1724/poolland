import 'bank_rules.dart';
import 'sms_models.dart';

/// ============================================================
///  Bank SMS parsing engine (pure function, easy to test).
///
///  Responsibilities:
///   1. Normalize text (Arabic/Persian digits, spacing, and character variants).
///   2. Filter non-financial messages (one-time passwords, codes, notifications, etc.).
///   3. Identify the bank from the sender or message body.
///   4. Detect direction: deposit or withdrawal.
///   5. Extract the amount and convert Rials to Tomans.
///   6. Extract card number, balance, and reference number.
/// ============================================================
class SmsParser {
  SmsParser._();

  // ---------------------------------------------------------
  // Vocabulary
  // ---------------------------------------------------------

  /// Keywords used to identify non-financial messages.
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
    'کسر',
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
  // Patterns
  // ---------------------------------------------------------
  static final RegExp _numberRe = RegExp(
    r'[0-9\u06F0-\u06F9\u0660-\u0669][0-9\u06F0-\u06F9\u0660-\u0669,\u066C\u200c ]*',
  );

  static final RegExp _amountKeywordRe = RegExp(
    r'(?:مبلغ|مبلغ کل|amount)[^0-9\u06F0-\u06F9\u0660-\u0669]{0,10}([0-9\u06F0-\u06F9\u0660-\u0669][0-9\u06F0-\u06F9\u0660-\u0669,\u066C\u200c ]*)',
    caseSensitive: false,
  );

  static final RegExp _verbAmountRe = RegExp(
    r'(?:برداشت|خرید|خريد|پرداخت|واریز|واريز|وصول|دریافت\s+وجه|دريافت\s+وجه|withdraw|purchase|debit|deposit|credited)[^0-9\u06F0-\u06F9\u0660-\u0669]{0,32}([0-9\u06F0-\u06F9\u0660-\u0669][0-9\u06F0-\u06F9\u0660-\u0669,\u066C\u200c ]*)',
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

  static final RegExp _accountContextRe = RegExp(
    r'(?:حساب|account)(?:\s*(?:شماره|number|no\.?))?\s*[:：\-]?\s*$',
    caseSensitive: false,
  );

  static final RegExp _cardContextRe = RegExp(
    r'(?:کارت|card)\s*[:：\-]?\s*$',
    caseSensitive: false,
  );

  // ---------------------------------------------------------
  // Normalization
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

  /// Convert Arabic and Persian digits to Latin digits.
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

  /// Keep digits only (for card and identifier comparisons).
  static String digitsOnly(String input) =>
      toLatinDigits(input).replaceAll(RegExp(r'[^0-9]'), '');

  // ---------------------------------------------------------
  // Main API
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
        note: 'Non-transaction message (password, code, or notification)',
      );
    }

    final direction = detectDirection(body);
    final amount = _extractAmount(body, rule);
    final balance = _extractBalance(body, rule);
    final card = _extractCard(body);
    final ref = _extractReference(body);
    final cardDigits = card == null ? '' : digitsOnly(card);

    // Only a message matched to a built-in or custom bank rule is considered
    // a recognized bank transaction.
    final confident =
        rule != null &&
        direction != SmsDirection.unknown &&
        amount.value > 0;

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
  // Bank identification
  // ---------------------------------------------------------
  static BankRule? findRule(
    String upperAddress,
    String body,
    List<BankRule> extraRules,
  ) {
    // Custom user rules take priority.
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
  // Filter non-financial messages
  // ---------------------------------------------------------
  static bool isIgnored(String body) {
    for (final w in ignoreKeywords) {
      if (body.contains(w)) return true;
    }
    return false;
  }

  // ---------------------------------------------------------
  // Transaction direction
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
  // Amount
  // ---------------------------------------------------------
  static _Amount _extractAmount(String body, BankRule? rule) {
    // 1) Look for a value following “amount”.
    final kw = _amountKeywordRe.firstMatch(body);
    if (kw != null) {
      final v = _toDouble(kw.group(1)!.trim());
      if (v > 0) return _convert(v, _unitAfter(body, kw.end), rule);
    }

    // 2) Look for a number immediately followed by a currency unit.
    for (final m in _numberRe.allMatches(body)) {
      if (_isExcluded(body, m)) continue;
      final unit = _unitAfter(body, m.end);
      if (unit.isNotEmpty) {
        final v = _toDouble(m.group(0)!.trim());
        if (v > 0) return _convert(v, unit, rule);
      }
    }

    // 3) A number following the transaction verb (e.g. “برداشت 10,000,000”).
    // Many banks omit the word “مبلغ” and the currency unit in these messages.
    for (final m in _verbAmountRe.allMatches(body)) {
      final valueStart = m.start(1);
      final valueEnd = m.end(1);
      if (_isExcludedRange(body, valueStart, valueEnd)) continue;
      final value = _toDouble(m.group(1)!.trim());
      if (value > 0) {
        return _convert(value, _unitAfter(body, valueEnd), rule);
      }
    }

    // 4) A conservative fallback is allowed only when exactly one significant
    // number remains and the message has a recognized transaction direction.
    final candidates = <double>[];
    for (final m in _numberRe.allMatches(body)) {
      if (_isExcluded(body, m)) continue;
      final value = _toDouble(m.group(0)!.trim());
      if (value >= 1000) candidates.add(value);
    }
    if (candidates.length == 1 &&
        detectDirection(body) != SmsDirection.unknown) {
      return _convert(candidates.single, '', rule);
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
        // No unit specified; use the bank’s default unit.
        if (rule != null && rule.defaultUnit == AmountUnit.rial) {
          return _Amount(value / 10, 'IRT', 'rial?');
        }
        return _Amount(value, 'IRT', 'toman?');
    }
  }

  /// Detect the currency unit within 16 characters after the number.
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

  /// Should this number be excluded from amount detection?
  /// (For example, a date, card digits, balance, or reference number.)
  static bool _isExcluded(String body, Match m) =>
      _isExcludedRange(body, m.start, m.end);

  static bool _isExcludedRange(String body, int start, int end) {
    // Adjacent to an asterisk (part of a card number).
    if (start > 0 && body[start - 1] == '*') return true;
    if (end < body.length && body[end] == '*') return true;

    // Part of a date, such as 1405/07/12 or 12-07.
    final after = end < body.length ? body[end] : '';
    final before = start > 0 ? body[start - 1] : '';
    if ((after == '/' || after == '-') && end + 1 < body.length) {
      final c = body[end + 1];
      if (c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) return true;
    }
    if (before == '/' || before == '-') return true;

    // Account and card numbers are identifiers, not transaction amounts.
    final headStart = (start - 32).clamp(0, body.length);
    final head = body.substring(headStart, start);
    if (_accountContextRe.hasMatch(head) || _cardContextRe.hasMatch(head)) {
      return true;
    }

    // Balance and reference/serial numbers are not the transaction amount.
    final normalizedHead = head.toLowerCase();
    if (normalizedHead.contains('مانده') ||
        normalizedHead.contains('موجودی') ||
        normalizedHead.contains('موجودي')) {
      return true;
    }
    if (normalizedHead.contains('پیگیری') ||
        normalizedHead.contains('پيگيري') ||
        normalizedHead.contains('مرجع') ||
        normalizedHead.contains('سریال') ||
        normalizedHead.contains('سريال') ||
        normalizedHead.contains('شناسه') ||
        normalizedHead.contains('reference') ||
        normalizedHead.contains('sequence')) {
      return true;
    }
    return false;
  }

  // ---------------------------------------------------------
  // Account balance
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
  // Card number
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
  // Reference number
  // ---------------------------------------------------------
  static String? _extractReference(String body) {
    final m = _refRe.firstMatch(body);
    if (m == null) return null;
    final v = m.group(1)!.trim();
    return v.isEmpty ? null : v;
  }

  // ---------------------------------------------------------
  // Match to a customer (card or number mapping)
  // ---------------------------------------------------------
  /// Does this SMS match one of the customer’s bank identifiers?
  static bool matchesIdentifiers(ParsedSms sms, List<String> identifiers) {
    final body = normalize(sms.message.body);
    final cardDigits = sms.cardDigits;
    final bodyDigits = digitsOnly(body);

    for (final raw in identifiers) {
      final id = digitsOnly(raw);
      if (id.length < 4) continue;
      // Prefer card digits because they are least likely to produce a false match.
      if (cardDigits.isNotEmpty && cardDigits.contains(id)) return true;
      if (cardDigits.isEmpty && bodyDigits.contains(id)) return true;
    }
    return false;
  }

  static String _buildNote(BankRule? rule, _Amount amount, SmsDirection dir) {
    final parts = <String>[];
    if (rule != null) parts.add(rule.bankName);
    if (amount.unit == 'rial') {
      parts.add('Amount converted from Rials to Tomans');
    }
    if (amount.unit == 'rial?') {
      parts.add('Amount assumed to be in Rials (bank rule)');
    }
    if (dir == SmsDirection.unknown) {
      parts.add('Transaction direction could not be determined');
    }
    return parts.join(' · ');
  }
}

/// Extracted amount result (value, currency, and detected unit).
class _Amount {
  final double value;
  final String currency;
  final String unit;
  const _Amount(this.value, this.currency, this.unit);
}
