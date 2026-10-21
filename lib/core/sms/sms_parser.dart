import '../localization.dart';
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
    'قرعه',
    'مسدود گردید',
    'مسدود شد',
    'حساب شما مسدود',
    'کارت شما مسدود',
    'احراز هویت',
    'کلمه عبور',
    'کد تایید',
    'کد تأیید',
    'کد ورود',
    'کد فعالسازی',
    'ورود به',
    'وارد همراه بانک',
    'وارد اینترنت بانک',
    'کسر خواهد گردید',
    'کسر خواهد شد',
  ];

  static const List<String> withdrawWords = <String>[
    'برداشت',
    'خرید',
    'خريد',
    'پرداخت',
    'کاهش موجودی',
    'حواله',
    'حوله',
    'اقساط',
    'قسط',
    'از حساب شما پرید',
    'از حساب شما کم شد',
    'بدهکار',
    'کسر گردید',
    'کسر شد',
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
    'انتقال به حساب شما',
    'به حساب شما نشست',
    'به حسابتان نشست',
    'بستانکار',
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
    r'(?:برداشت|خرید|خريد|پرداخت|حواله|قسط|بدهکار|واریز|واريز|وصول|بستانکار|دریافت\s+وجه|دريافت\s+وجه|withdraw|purchase|debit|deposit|credited)[^0-9\u06F0-\u06F9\u0660-\u0669]{0,32}([0-9\u06F0-\u06F9\u0660-\u0669][0-9\u06F0-\u06F9\u0660-\u0669,\u066C\u200c ]*)',
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
        .replaceAll('\u0640', '') // Arabic Tatweel (کشیده، مثل اصـلاحيه)
        .replaceAll('\u200c', ' ')
        .replaceAll('\u200f', '')
        .replaceAll('\ufeff', '');
    return s;
  }

  static bool _isDigitChar(String c) {
    if (c.isEmpty) return false;
    final code = c.codeUnitAt(0);
    return (code >= 0x30 && code <= 0x39) ||
        (code >= 0x06F0 && code <= 0x06F9) ||
        (code >= 0x0660 && code <= 0x0669);
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
    Set<String> disabledRuleIds = const <String>{},
  }) {
    final body = normalize(msg.body);
    final address = normalize(msg.address).toUpperCase();
    final rule = findRule(
      address,
      body,
      extraRules,
      disabledRuleIds: disabledRuleIds,
    );

    if (isIgnored(body)) {
      return ParsedSms(
        message: msg,
        bankName: rule?.bankName,
        note: 'Non-transaction message (password, code, or notification)'.tr,
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
    Set<String> disabledRuleIds = const <String>{},
  }) => messages
      .map(
        (m) => parse(
          m,
          extraRules: extraRules,
          disabledRuleIds: disabledRuleIds,
        ),
      )
      .toList();

  // ---------------------------------------------------------
  // Bank identification
  // ---------------------------------------------------------
  static final RegExp _shortAlphaHintRe = RegExp(
    r'^[A-Z\u0600-\u06FF]{3}$',
  );

  static BankRule? findRule(
    String upperAddress,
    String body,
    List<BankRule> extraRules, {
    Set<String> disabledRuleIds = const <String>{},
  }) {
    // Custom/edited user rules take priority over built-in defaults with the
    // same id, and disabled rules are never used.
    final overriddenIds = {for (final r in extraRules) r.id};
    final rules = [
      ...extraRules,
      ...builtinBankRules.where((b) => !overriddenIds.contains(b.id)),
    ].where((rule) => !disabledRuleIds.contains(rule.id)).toList();

    for (final rule in rules) {
      for (final hint in rule.senderHints) {
        final h = normalize(hint).toUpperCase();
        if (h.isEmpty) continue;
        if (upperAddress == h) return rule;
        if (h.length >= 4 && upperAddress.contains(h)) return rule;
        if (h.length == 3 &&
            _shortAlphaHintRe.hasMatch(h) &&
            upperAddress.contains(h)) {
          return rule;
        }
      }
    }
    for (final rule in rules) {
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
    // Strip "کارمزد" (fee) first because its middle letters ("کا-رمز-د")
    // contain the substring "رمز" (password).
    final cleaned = body.replaceAll('کارمزد', '');
    for (final w in ignoreKeywords) {
      if (cleaned.contains(w)) return true;
    }
    return false;
  }

  // ---------------------------------------------------------
  // Transaction direction
  // ---------------------------------------------------------
  static SmsDirection detectDirection(String body) {
    // 1) An explicit + / - sign attached to the transaction amount (common in
    // Melli Bank, Keshavarzi, Refah, Sepah, etc., e.g. "انتقال:4,000,000+" or
    // "قسط:18,080,791-") authoritatively sets deposit (+) vs withdrawal (-).
    final signed = _findSignedAmount(body);
    if (signed != null) {
      return signed.direction;
    }

    // 2) Compare the earliest occurrence of primary deposit vs withdrawal words
    // so trailing fee lines (e.g. "کارمزد: 0 ریال") or counterparty notes
    // never override the main transaction verb at the start of the SMS.
    int? earliestWithdraw;
    for (final w in withdrawWords) {
      final idx = body.indexOf(w);
      if (idx != -1 && (earliestWithdraw == null || idx < earliestWithdraw)) {
        earliestWithdraw = idx;
      }
    }

    int? earliestDeposit;
    for (final w in depositWords) {
      final idx = body.indexOf(w);
      if (idx != -1 && (earliestDeposit == null || idx < earliestDeposit)) {
        earliestDeposit = idx;
      }
    }

    if (earliestDeposit != null && earliestWithdraw != null) {
      return earliestDeposit <= earliestWithdraw
          ? SmsDirection.deposit
          : SmsDirection.withdraw;
    }
    if (earliestWithdraw != null) return SmsDirection.withdraw;
    if (earliestDeposit != null) return SmsDirection.deposit;

    if (body.contains('کسر') || body.contains('کارمزد')) {
      return SmsDirection.withdraw;
    }
    if (body.contains('انتقال')) return SmsDirection.withdraw;
    if (body.contains('شارژ')) return SmsDirection.deposit;
    return SmsDirection.unknown;
  }

  /// Finds a non-excluded transaction amount (>= 1000) that carries an
  /// explicit `+` or `-` / `−` sign immediately after or before the number
  /// (e.g. `انتقال:4,000,000+`, `قسط:18,080,791-`, `اصلاحیه:20,000,000+`).
  static _SignedMatch? _findSignedAmount(String body) {
    for (final m in _numberRe.allMatches(body)) {
      var end = m.end;
      while (end > m.start &&
          (body[end - 1] == ' ' || body[end - 1] == '\u200c')) {
        end--;
      }
      final start = m.start;
      if (_isExcludedRange(body, start, end)) continue;
      final value = _toDouble(body.substring(start, end));
      if (value < 1000) continue;

      // Check trailing sign (e.g. "4,000,000+" or "2,600,000-")
      var signIdx = end;
      while (signIdx < body.length && body[signIdx] == ' ') {
        signIdx++;
      }
      if (signIdx < body.length) {
        final ch = body[signIdx];
        if (ch == '+' || ch == '-' || ch == '−' || ch == '➕' || ch == '➖') {
          final nextIdx = signIdx + 1;
          final followedByDigit =
              nextIdx < body.length && _isDigitChar(body[nextIdx]);
          if (!followedByDigit) {
            final dir = (ch == '+' || ch == '➕')
                ? SmsDirection.deposit
                : SmsDirection.withdraw;
            return _SignedMatch(
              value: value,
              direction: dir,
              unitEnd: nextIdx,
            );
          }
        }
      }

      // Check leading sign (e.g. "+4,000,000" or "-2,600,000")
      var leadIdx = start - 1;
      while (leadIdx >= 0 && body[leadIdx] == ' ') {
        leadIdx--;
      }
      if (leadIdx >= 0) {
        final ch = body[leadIdx];
        if (ch == '+' || ch == '-' || ch == '−' || ch == '➕' || ch == '➖') {
          final prevIdx = leadIdx - 1;
          final precededByDigit =
              prevIdx >= 0 && _isDigitChar(body[prevIdx]);
          if (!precededByDigit) {
            final dir = (ch == '+' || ch == '➕')
                ? SmsDirection.deposit
                : SmsDirection.withdraw;
            return _SignedMatch(value: value, direction: dir, unitEnd: end);
          }
        }
      }
    }
    return null;
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

    // 3) Look for a signed transaction amount (e.g. "انتقال:4,000,000+" or
    // "قسط:18,080,791-").
    final signed = _findSignedAmount(body);
    if (signed != null && signed.value > 0) {
      return _convert(signed.value, _unitAfter(body, signed.unitEnd), rule);
    }

    // 4) A number following the transaction verb (e.g. “برداشت 10,000,000”).
    // Many banks omit the word “مبلغ” and the currency unit in these messages.
    for (final m in _verbAmountRe.allMatches(body)) {
      final captured = m.group(1)!;
      final valueEnd = m.end;
      final valueStart = valueEnd - captured.length;
      if (_isExcludedRange(body, valueStart, valueEnd)) continue;
      final value = _toDouble(captured.trim());
      if (value > 0) {
        return _convert(value, _unitAfter(body, valueEnd), rule);
      }
    }

    // 5) A conservative fallback is allowed only when exactly one significant
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

    // Part of a date, time, or dotted deposit number (e.g. 1405/07/12,
    // 0724-10:35, 11/18_00:43, 10.10001439.1, 777.800.12345678.1).
    final after = end < body.length ? body[end] : '';
    final before = start > 0 ? body[start - 1] : '';
    if ((after == '/' || after == '-' || after == '.' || after == ':') &&
        end + 1 < body.length) {
      if (_isDigitChar(body[end + 1])) return true;
    }
    if (before == '/' || before == '_' || after == '_') return true;
    if ((before == '-' || before == '.' || before == ':') &&
        start >= 2 &&
        _isDigitChar(body[start - 2])) {
      return true;
    }

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
        normalizedHead.contains('قرارداد') ||
        normalizedHead.contains('contract') ||
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
    // The note is rendered verbatim on the review cards, so it is built
    // in the active language; `bankName` itself stays an untranslated key
    // for callers that render it separately.
    final parts = <String>[];
    if (rule != null) parts.add(rule.bankName.tr);
    if (amount.unit == 'rial') {
      parts.add('Amount converted from Rials to Tomans'.tr);
    }
    if (amount.unit == 'rial?') {
      parts.add('Amount assumed to be in Rials (bank rule)'.tr);
    }
    if (dir == SmsDirection.unknown) {
      parts.add('Transaction direction could not be determined'.tr);
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

class _SignedMatch {
  final double value;
  final SmsDirection direction;
  final int unitEnd;
  const _SignedMatch({
    required this.value,
    required this.direction,
    required this.unitEnd,
  });
}
