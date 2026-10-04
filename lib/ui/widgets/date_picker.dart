import 'package:flutter/material.dart';

import '../../core/format_utils.dart';
import '../../core/jalali_utils.dart';

/// انتخابگر تاریخ شمسی (بدون وابستگی به پکیج‌های اضافه)
Future<DateTime?> showJalaliPicker(
  BuildContext context, {
  required DateTime initial,
  DateTime? firstDate,
  DateTime? lastDate,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _JalaliPickerDialog(
      initial: initial,
      firstDate: firstDate,
      lastDate: lastDate,
    ),
  );
}

class _JalaliPickerDialog extends StatefulWidget {
  const _JalaliPickerDialog({required this.initial, this.firstDate, this.lastDate});

  final DateTime initial;
  final DateTime? firstDate;
  final DateTime? lastDate;

  @override
  State<_JalaliPickerDialog> createState() => _JalaliPickerDialogState();
}

class _JalaliPickerDialogState extends State<_JalaliPickerDialog> {
  late int year;
  late int month;
  late DateTime selected;

  @override
  void initState() {
    super.initState();
    final j = J.of(widget.initial);
    year = j.year;
    month = j.month;
    selected = widget.initial;
  }

  void _shiftMonth(int delta) {
    final j = J.of(J.addMonths(J.toDate(year, month, 1), delta));
    setState(() {
      year = j.year;
      month = j.month;
    });
  }

  bool _allowed(int y, int m, int d) {
    final dt = J.toDate(y, m, d);
    if (widget.firstDate != null && dt.isBefore(J.dateOnly(widget.firstDate!))) return false;
    if (widget.lastDate != null && dt.isAfter(J.dateOnly(widget.lastDate!))) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final length = J.monthLength(year, month);
    final blanks = J.leadingBlanks(year, month);
    final selectedJ = J.of(selected);
    final today = J.today;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // انتخاب سال و ماه
            Row(
              children: [
                IconButton(
                  tooltip: 'سال قبل',
                  onPressed: () => setState(() => year--),
                  icon: const Icon(Icons.keyboard_double_arrow_right_rounded, size: 20),
                ),
                IconButton(
                  tooltip: 'ماه قبل',
                  onPressed: () => _shiftMonth(-1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '${Fmt.monthName(month)} ${Fmt.toFaDigits('$year')}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'ماه بعد',
                  onPressed: () => _shiftMonth(1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                IconButton(
                  tooltip: 'سال بعد',
                  onPressed: () => setState(() => year++),
                  icon: const Icon(Icons.keyboard_double_arrow_left_rounded, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // نام روزهای هفته
            Row(
              children: [
                for (final w in Fmt.weekDays)
                  Expanded(
                    child: Center(
                      child: Text(w.substring(0, w.contains('\u200c') ? 1 : 1),
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: onSurface.withValues(alpha: 0.55))),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            // روزها
            SizedBox(
              height: 240,
              child: GridView.count(
                crossAxisCount: 7,
                childAspectRatio: 1.15,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (var i = 0; i < blanks; i++) const SizedBox(),
                  for (var d = 1; d <= length; d++)
                    _DayCell(
                      day: d,
                      enabled: _allowed(year, month, d),
                      isSelected: selectedJ.year == year &&
                          selectedJ.month == month &&
                          selectedJ.day == d,
                      isToday: J.sameDay(today, J.toDate(year, month, d)),
                      onTap: () => Navigator.pop(context, J.toDate(year, month, d)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => Navigator.pop(context, J.today),
                  icon: const Icon(Icons.today_rounded, size: 17),
                  label: const Text('امروز'),
                ),
                const Spacer(),
                TextButton(
                    onPressed: () => Navigator.pop(context), child: const Text('انصراف')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.enabled,
    required this.isSelected,
    required this.isToday,
    required this.onTap,
  });

  final int day;
  final bool enabled;
  final bool isSelected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: enabled ? onTap : null,
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? primary : colorsOf(isToday, primary),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              Fmt.toFaDigits('$day'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected || isToday ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : enabled
                        ? onSurface
                        : onSurface.withValues(alpha: 0.3),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color? colorsOf(bool today, Color primary) =>
      today ? primary.withValues(alpha: 0.14) : null;
}
