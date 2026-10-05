import 'package:shamsi_date/shamsi_date.dart';

import 'format_utils.dart';

/// Utilities for converting and working with Jalali dates.
class J {
  J._();

  static Jalali of(DateTime dt) => Jalali.fromDateTime(dt);

  static DateTime toDate(int y, int m, int d) => Jalali(y, m, d).toDateTime();

  static DateTime get today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static DateTime dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  /// Format a Jalali date, e.g. 1405/07/12.
  static String d(DateTime dt, {bool persian = false, String sep = '/'}) {
    final j = of(dt);
    return Fmt.date(j.year, j.month, j.day, persian: persian, sep: sep);
  }

  /// Format a long Jalali date, e.g. 12 Mehr 1405.
  static String dLong(DateTime dt, {bool persian = false}) {
    final j = of(dt);
    return Fmt.dateLong(j.year, j.month, j.day, persian: persian);
  }

  /// Format a full Jalali date with weekday, e.g. Wednesday 12 Mehr 1405.
  static String dFull(DateTime dt, {bool persian = false}) {
    final j = of(dt);
    final s =
        '${Fmt.weekDayName(j.weekDay)} ${j.day} ${Fmt.monthName(j.month)} ${j.year}';
    return persian ? Fmt.toFaDigits(s) : s;
  }

  /// Format a Jalali month and year, e.g. Mehr 1405.
  static String mLabel(DateTime dt, {bool persian = false}) {
    final j = of(dt);
    return Fmt.monthLabel(j.year, j.month, persian: persian);
  }

  /// Format a short Jalali date, e.g. 12 Mehr.
  static String dShort(DateTime dt, {bool persian = false}) {
    final j = of(dt);
    final s = '${j.day} ${Fmt.monthName(j.month)}';
    return persian ? Fmt.toFaDigits(s) : s;
  }

  /// Format a Jalali date and time.
  static String dTime(DateTime dt, {bool persian = false}) =>
      '${d(dt, persian: persian)} - ${Fmt.clock(dt, persian: persian)}';

  static int jalaliYear(DateTime dt) => of(dt).year;

  static DateTime startOfMonth(DateTime dt) {
    final j = of(dt);
    return Jalali(j.year, j.month, 1).toDateTime();
  }

  static DateTime endOfMonth(DateTime dt) {
    final j = of(dt);
    return Jalali(j.year, j.month, j.monthLength).toDateTime();
  }

  static DateTime startOfYear(DateTime dt) =>
      Jalali(of(dt).year, 1, 1).toDateTime();

  static DateTime startOfDay(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day);

  static DateTime endOfDay(DateTime dt) =>
      DateTime(dt.year, dt.month, dt.day, 23, 59, 59, 999);

  static DateTime addMonths(DateTime dt, int months) =>
      of(dt).addMonths(months).toDateTime();

  static DateTime addDays(DateTime dt, int days) =>
      of(dt).addDays(days).toDateTime();

  static bool sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool sameMonth(DateTime a, DateTime b) {
    final ja = of(a), jb = of(b);
    return ja.year == jb.year && ja.month == jb.month;
  }

  static bool sameYear(DateTime a, DateTime b) => of(a).year == of(b).year;

  static int monthLength(int year, int month) =>
      Jalali(year, month, 1).monthLength;

  /// Return the Jalali weekday (1 = Saturday, 7 = Friday).
  static int weekDay(DateTime dt) => of(dt).weekDay;

  /// Return the day difference (positive means the target is in the future).
  static int daysBetween(DateTime from, DateTime to) =>
      dateOnly(to).difference(dateOnly(from)).inDays;

  /// Count the empty calendar cells before the first day of a month.
  static int leadingBlanks(int year, int month) =>
      Jalali(year, month, 1).weekDay - 1;
}
