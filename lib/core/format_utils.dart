import 'package:intl/intl.dart';

/// ابزارهای قالب‌بندی عدد، پول و تاریخ (شمسی).
class Fmt {
  Fmt._();

  static const _en = 'en_US';
  static final NumberFormat _grouped = NumberFormat('#,##0', _en);
  static final NumberFormat _plainDecimal = NumberFormat('#,##0.##', _en);

  static const _faDigits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

  /// تبدیل ارقام لاتین به فارسی
  static String toFaDigits(String input) {
    final sb = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final idx = '0123456789'.indexOf(ch);
      sb.write(idx >= 0 ? _faDigits[idx] : ch);
    }
    return sb.toString();
  }

  /// تبدیل ارقام فارسی/عربی به لاتین (برای جست‌وجو)
  static String toLatinDigits(String input) {
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    const ar = '٠١٢٣٤٥٦٧٨٩';
    var s = input;
    for (var i = 0; i < 10; i++) {
      s = s.replaceAll(fa[i], '$i').replaceAll(ar[i], '$i');
    }
    return s.replaceAll('٬', ',').replaceAll('٫', '.');
  }

  /// جداکننده هزارگان فارسی + اعشار فارسی
  static String _localize(String s, bool persian) {
    if (!persian) return s;
    return toFaDigits(s).replaceAll(',', '٬').replaceAll('.', '٫');
  }

  /// قالب‌بندی عدد (بدون واحد پول)
  static String number(num value, {int decimals = 0, bool persian = true}) {
    final s = decimals > 0
        ? NumberFormat('#,##0.${'0' * decimals}', _en).format(value)
        : _grouped.format(value.round());
    return _localize(s, persian);
  }

  /// قالب‌بندی مبلغ به همراه نماد/کد ارز
  static String money(
    num value, {
    String symbol = 'تومان',
    int decimals = 0,
    bool persian = true,
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

  /// نمایش خلاصه‌ی مبلغ برای کارت‌ها: ۱۲٫۵ میلیون / ۳۴۰ هزار / ۱٫۲ میلیارد
  static String compactMoney(num value, {String symbol = 'تومان', bool persian = true}) {
    final v = value.abs();
    String out;
    if (v >= 1000000000) {
      out = '${NumberFormat('#,##0.##', _en).format(v / 1000000000)} میلیارد';
    } else if (v >= 1000000) {
      out = '${NumberFormat('#,##0.##', _en).format(v / 1000000)} میلیون';
    } else if (v >= 1000) {
      out = '${NumberFormat('#,##0.#', _en).format(v / 1000)} هزار';
    } else {
      out = _plainDecimal.format(v);
    }
    final sign = value < 0 ? '−' : '';
    return '$sign${_localize(out, persian)} $symbol';
  }

  /// عدد اعشاری ساده بدون جداکننده (برای فیلدهای ورودی)
  static String inputNumber(num value, {int decimals = 2}) {
    final s = value.toStringAsFixed(decimals);
    return s.endsWith('.00') && decimals == 2 ? value.toStringAsFixed(0) : s;
  }

  static String _two(int v) => v.toString().padLeft(2, '0');

  /// ۱۴۰۵/۰۷/۱۲
  static String date(int y, int m, int d, {bool persian = true, String sep = '/'}) {
    final s = '$y$sep${_two(m)}$sep${_two(d)}';
    return persian ? toFaDigits(s) : s;
  }

  /// ۱۲ مهر ۱۴۰۵
  static String dateLong(int y, int m, int d, {bool persian = true}) {
    final s = '$y ${monthName(m)} $d';
    return persian ? toFaDigits(s) : s;
  }

  /// مهر ۱۴۰۵
  static String monthLabel(int y, int m, {bool persian = true}) {
    final s = '${monthName(m)} $y';
    return persian ? toFaDigits(s) : s;
  }

  static String ordinal(int day, {bool persian = true}) {
    final s = '$day';
    return persian ? toFaDigits(s) : s;
  }

  static const jalaliMonths = <String>[
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
    'شنبه',
    'یک‌شنبه',
    'دوشنبه',
    'سه‌شنبه',
    'چهارشنبه',
    'پنج‌شنبه',
    'جمعه',
  ];

  static String monthName(int m) => (m >= 1 && m <= 12) ? jalaliMonths[m - 1] : '';

  /// نام روز هفته بر اساس شماره‌ی هفته‌ی جلالی (۱ = شنبه … ۷ = جمعه)
  static String weekDayName(int weekDay) =>
      (weekDay >= 1 && weekDay <= 7) ? weekDays[weekDay - 1] : '';

  /// «۳ روز مانده»، «امروز آخرین روز»، «۵ روز گذشته»
  static String expiryLabel(int days, {bool persian = true}) {
    if (days == 0) return 'امروز';
    if (days == 1) return 'فردا';
    if (days > 1) return '${persian ? toFaDigits('$days') : days} روز مانده';
    final passed = -days;
    return '${persian ? toFaDigits('$passed') : passed} روز گذشته';
  }

  static String percent(double ratio, {bool persian = true}) =>
      '${_localize(NumberFormat('#,##0.#', _en).format(ratio * 100), persian)}٪';

  /// ساعت ۱۴:۳۰
  static String clock(DateTime dt, {bool persian = true}) {
    final s = '${_two(dt.hour)}:${_two(dt.minute)}';
    return persian ? toFaDigits(s) : s;
  }
}

/// تبدیل ورودی کاربر (ارقام فارسی/عربی، جداکننده) به عدد
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
  // چند نقطه: «1.234.567» جداکننده‌ی هزارگان است، «1.2.3» اعشاری.
  // اگر همه‌ی بخش‌ها بعد از نقطه‌ی اول دقیقاً ۳ رقم باشند، هزارگان است.
  if ('.'.allMatches(s).length > 1) {
    final parts = s.split('.');
    final isThousands = parts.skip(1).every((p) => p.length == 3);
    if (isThousands) {
      s = parts.join('');
    } else {
      // فقط اولین نقطه اعشار است، بقیه حذف می‌شوند
      s = '${parts.first}.${parts.skip(1).join()}';
    }
  }
  return double.tryParse(s) ?? 0;
}

/// عدد → رشتهٔ گروه‌بندی‌شده با ارقام فارسی
String faNumber(num value, {int decimals = 0}) =>
    Fmt.number(value, decimals: decimals, persian: true);

/// عدد → رشتهٔ گروه‌بندی‌شده با ارقام لاتین
String groupedNumber(num value, {int decimals = 0}) =>
    Fmt.number(value, decimals: decimals, persian: false);

/// قالب‌بندی شماره تلفن: ۰۹۱۲ ۱۲۳ ۴۵۶۷
String formatPhone(String value, {bool persian = true}) {
  final s = value.trim();
  if (s.isEmpty) return '';
  final out = s.replaceAllMapped(
      RegExp(r'(\d{4})(\d{3})(\d{4})$'), (m) => '${m[1]} ${m[2]} ${m[3]}');
  return persian ? Fmt.toFaDigits(out) : out;
}
