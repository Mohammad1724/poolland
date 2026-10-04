import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/format_utils.dart';
import '../../core/money.dart';
import '../../data/ledger.dart';

/// نمودار ستونیِ درآمد/هزینه برای نقاطِ زمانیِ دلخواه
/// (روزانه، هفتگی، ماهانه)
class PeriodBarChart extends StatelessWidget {
  const PeriodBarChart({
    super.key,
    required this.points,
    required this.labelOf,
    this.height = 200,
    this.showIncome = true,
  });

  final List<DayPoint> points;
  final String Function(DayPoint point) labelOf;
  final double height;
  final bool showIncome;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final maxValue = points
        .expand((p) => showIncome ? [p.income, p.expense] : [p.expense])
        .fold<double>(0, (a, b) => a > b ? a : b);
    final maxY = maxValue <= 0 ? 1000.0 : maxValue * 1.25;

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (group) =>
                  Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF23304A)
                      : const Color(0xFF1F2937),
              getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                  BarTooltipItem(
                Money.text(rod.toY, compact: true, withSymbol: false),
                const TextStyle(
                    fontFamily: 'Vazirmatn', color: Colors.white, fontSize: 11),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 46,
                getTitlesWidget: (value, meta) {
                  if (value == 0) return const SizedBox.shrink();
                  return Text(
                    _short(value),
                    style: TextStyle(
                        fontSize: 9.5, color: onSurface.withValues(alpha: 0.55)),
                    textAlign: TextAlign.left,
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= points.length) return const SizedBox.shrink();
                  // برای جلوگیری از شلوغی، برچسب‌ها را یک‌درمیان نشان می‌دهیم
                  if (points.length > 16 && i % 2 != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      labelOf(points[i]),
                      style: TextStyle(
                          fontSize: 9.5, color: onSurface.withValues(alpha: 0.7)),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (value) => FlLine(
              color: onSurface.withValues(alpha: 0.08),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (var i = 0; i < points.length; i++)
              BarChartGroupData(
                x: i,
                barsSpace: showIncome ? 3 : 0,
                barRods: [
                  if (showIncome)
                    BarChartRodData(
                      toY: points[i].income,
                      color: const Color(0xFF16A34A),
                      width: showIncome ? 7 : 12,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                  BarChartRodData(
                    toY: points[i].expense,
                    color: const Color(0xFFE11D48),
                    width: showIncome ? 7 : 12,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _short(double v) {
    if (v >= 1000000000) {
      return '${Fmt.toFaDigits((v / 1000000000).toStringAsFixed(1))}م';
    }
    if (v >= 1000000) return '${Fmt.toFaDigits((v / 1000000).toStringAsFixed(1))}م';
    if (v >= 1000) return '${Fmt.toFaDigits((v / 1000).toStringAsFixed(0))}ه';
    return Fmt.toFaDigits(v.toStringAsFixed(0));
  }
}
