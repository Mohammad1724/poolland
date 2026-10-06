import 'package:flutter_test/flutter_test.dart';
import 'package:poolland/core/jalali_utils.dart';
import 'package:poolland/data/models.dart';
import 'package:shamsi_date/shamsi_date.dart';

void main() {
  test('adding a month clamps the day to the target Jalali month', () {
    final start = Jalali(1405, 6, 31).toDateTime();

    final target = J.of(J.addMonths(start, 1));

    expect(target.year, 1405);
    expect(target.month, 7);
    expect(target.day, 30);
  });

  test('monthly plan end date handles a month-end start date', () {
    final start = Jalali(1405, 6, 31).toDateTime();
    const plan = Plan(id: 'one-month', name: 'One month');

    final end = J.of(plan.endFrom(start));

    expect(end.year, 1405);
    expect(end.month, 7);
    expect(end.day, 29);
  });
}
