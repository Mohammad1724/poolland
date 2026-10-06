import 'package:intl/intl.dart';

import 'localization.dart';

/// Number, currency, and Jalali date formatting utilities.
class Fmt {
  Fmt._();

  static const _en = 'en_US';
  static final NumberFormat _grouped = NumberFormat('#,##0', _en);
  static final NumberFormat _plainDecimal = NumberFormat('#,##0.##', _en);

  static const _faDigits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

  /// Convert Latin digits to Persian digits.
  static String toFaDigits(String input) {
    final sb = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final idx = '0123456789'.indexOf(ch);
      sb.write(idx >= 0 ? _faDigits[idx] : ch);
    }
    return sb.toString();
  }

  /// Convert Persian and Arabic-Indic digits to Latin digits for matching.
  static String toLatinDigits(String input) => String.fromCharCodes(
    input.runes.map((rune) {
      if (rune >= 0x06F0 && rune <= 0x06F9) return rune - 0x06F0 + 0x30;
      if (rune >= 0x0660 && rune <= 0x0669) return rune - 0x0660 + 0x30;
      return rune;
    }),
  );

  /// Normalize user-entered search text across Persian and Arabic keyboards.
  static String normalizeSearchText(String input) =>
      toLatinDigits(input)
          .toLowerCase()
          .replaceAll('ي', 'ی')
          .replaceAll('ك', 'ک')
          .replaceAll('\u200c', '')
          .replaceAll('\u200e', '')
          .replaceAll('\u200f', '')
          .trim();

  /// Use Persian digits and separators when requested.
  static String _localize(String s, bool persian) {
    if (!persian) return s;
    return toFaDigits(s).replaceAll(',', '٬').replaceAll('.', '٫');
  }

  /// Format a number without a currency unit.
  static String number(num value, {int decimals = 0, bool persian = false}) {
    final s = decimals > 0
        ? NumberFormat('#,##0.${'0' * decimals}', _en).format(value)
        : _grouped.format(value.round());
    return _localize(s, persian);
  }

  /// Format an amount with an optional currency symbol or code.
  static String money(
    num value, {
    String symbol = 'Toman',
    int decimals = 0,
    bool persian = false,
    bool withSymbol = true,
    bool sign = false,
  }) {
    String s;
    if (decimals > 0) {
      s = NumberFormat('#,##0.${'0' * decimals}', _en).format(value.abs());
    } else {
      s = _grouped.format(value.abs().round());
    }
    s = _localize(s, persian);
    final prefix = sign ? (value < 0 ? '−' : '+') : (value < 0 ? '−' : '');
    return withSymbol ? '$prefix$s $symbol' : '$prefix$s';
  }

  /// Compact amount for summary cards: 12.5 billion, 340 thousand, and so on.
  static String compactMoney(
    num value, {
    String symbol = 'Toman',
    bool persian = false,
  }) {
    final v = value.abs();
    String out;
    if (v >= 1000000000) {
      out =
          '${NumberFormat('#,##0.##', _en).format(v / 1000000000)} ${'billion'.tr}';
    } else if (v >= 1000000) {
      out =
          '${NumberFormat('#,##0.##', _en).format(v / 1000000)} ${'million'.tr}';
    } else if (v >= 1000) {
      out = '${NumberFormat('#,##0.#', _en).format(v / 1000)} ${'thousand'.tr}';
    } else {
      out = _plainDecimal.format(v);
    }
    final sign = value < 0 ? '−' : '';
    return '$sign${_localize(out, persian)} $symbol';
  }

  /// Format a decimal input value without grouping separators.
  static String inputNumber(num value, {int decimals = 2}) {
    final s = value.toStringAsFixed(decimals);
    return s.endsWith('.00') && decimals == 2 ? value.toStringAsFixed(0) : s;
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// Format a Jalali date, e.g. 1405/07/12.
  static String date(
    int y,
    int m,
    int d, {
    bool persian = false,
    String sep = '/',
  }) {
    final s = '$y$sep${_two(m)}$sep${_two(d)}';
    return persian ? toFaDigits(s) : s;
  }

  /// Format a long Jalali date, e.g. 12 Mehr 1405.
  static String dateLong(int y, int m, int d, {bool persian = false}) {
    final s = '$d ${monthName(m)} $y';
    return persian ? toFaDigits(s) : s;
  }

  /// Format a Jalali month and year, e.g. Mehr 1405.
  static String monthLabel(int y, int m, {bool persian = false}) {
    final s = '${monthName(m)} $y';
    return persian ? toFaDigits(s) : s;
  }

  static String ordinal(int day, {bool persian = false}) {
    final s = '$day';
    return persian ? toFaDigits(s) : s;
  }

  static const jalaliMonths = <String>[
    'Farvardin',
    'Ordibehesht',
    'Khordad',
    'Tir',
    'Mordad',
    'Shahrivar',
    'Mehr',
    'Aban',
    'Azar',
    'Dey',
    'Bahman',
    'Esfand',
  ];

  static const _faJalaliMonths = <String>[
    'فروردین',
    'اردیبهشت',
    'خرداد',
    'تیر',
    'مرداد',
    'شهریور',
    'مهر',
    'آبان',
    'آذر',
    'دی',
    'بهمن',
    'اسفند',
  ];

  static const weekDays = <String>[
    'Saturday',
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
  ];

  static const _faWeekDays = <String>[
    'شنبه',
    'یکشنبه',
    'دوشنبه',
    'سه‌شنبه',
    'چهارشنبه',
    'پنجشنبه',
    'جمعه',
  ];

  static String monthName(int m) {
    if (m < 1 || m > 12) return '';
    return (AppLocalization.languageCode == 'fa'
        ? _faJalaliMonths
        : jalaliMonths)[m - 1];
  }

  /// Return the weekday name for a Jalali weekday (1 = Saturday, 7 = Friday).
  static String weekDayName(int weekDay) {
    if (weekDay < 1 || weekDay > 7) return '';
    return (AppLocalization.languageCode == 'fa'
        ? _faWeekDays
        : weekDays)[weekDay - 1];
  }

  /// Describe the remaining or elapsed days until expiry.
  static String expiryLabel(int days, {bool persian = false}) {
    String count(int value) => persian ? toFaDigits('$value') : '$value';

    if (days == 0) return 'Today'.tr;
    if (days == 1) return 'Tomorrow'.tr;
    if (days > 1) {
      return '{days} days left'.trArgs({'days': count(days)});
    }
    final passed = -days;
    return (passed == 1 ? '{days} day ago' : '{days} days ago').trArgs({
      'days': count(passed),
    });
  }

  static String percent(double ratio, {bool persian = false}) =>
      '${_localize(NumberFormat('#,##0.#', _en).format(ratio * 100), persian)}${persian ? '٪' : '%'}';

  /// Format a clock time, e.g. 14:30.
  static String clock(DateTime dt, {bool persian = false}) {
    final s = '${_two(dt.hour)}:${_two(dt.minute)}';
    return persian ? toFaDigits(s) : s;
  }
}

/// Parse Latin, Arabic, or Persian digits and separators into a number.
double parseAmount(String input) {
  if (input.trim().isEmpty) return 0;
  var s = input;
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  const ar = '٠١٢٣٤٥٦٧٨٩';
  for (var i = 0; i < 10; i++) {
    s = s.replaceAll(fa[i], '$i').replaceAll(ar[i], '$i');
  }
  s = s
      .replaceAll('٬', '')
      .replaceAll(',', '')
      .replaceAll(' ', '')
      .replaceAll('\u200c', '')
      .replaceAll('٫', '.');
  s = s.replaceAll(RegExp(r'[^0-9.\-]'), '');
  return double.tryParse(s) ?? 0;
}

/// Group a number using Persian digits when needed.
String faNumber(num value, {int decimals = 0}) =>
    Fmt.number(value, decimals: decimals, persian: true);

/// Group a number using Latin digits.
String groupedNumber(num value, {int decimals = 0}) =>
    Fmt.number(value, decimals: decimals, persian: false);

/// Format a phone number, e.g. 0912 123 4567.
String formatPhone(String value, {bool persian = false}) {
  final s = value.trim();
  if (s.isEmpty) return '';
  final out = s.replaceAllMapped(
    RegExp(r'(\d{4})(\d{3})(\d{4})$'),
    (m) => '${m[1]} ${m[2]} ${m[3]}',
  );
  return persian ? Fmt.toFaDigits(out) : out;
}
