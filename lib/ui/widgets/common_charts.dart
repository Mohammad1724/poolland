import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/format_utils.dart';
import '../../core/localization.dart';
import '../../core/jalali_utils.dart';
import '../../core/money.dart';
import '../../data/ledger.dart';

/// Monthly income and expense bar chart
class MonthlyBarChart extends StatelessWidget {
  const MonthlyBarChart({super.key, required this.points, this.height = 190});

  final List<MonthPoint> points;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final maxValue = points
        .expand((p) => [p.income, p.expense])
        .fold<double>(0, (a, b) => a > b ? a : b);
    final maxY = maxValue <= 0 ? 1000.0 : maxValue * 1.25;

    final chart = BarChart(
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
                    fontFamily: 'Vazirmatn',
                    color: Colors.white,
                    fontSize: 11,
                  ),
                ),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 46,
              getTitlesWidget: (value, meta) {
                if (value == 0) return const SizedBox.shrink();
                return Text(
                  _short(value),
                  style: TextStyle(
                    fontSize: 9.5,
                    color: onSurface.withValues(alpha: 0.55),
                  ),
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
                final j = J.of(points[i].monthStart);
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    Fmt.monthName(j.month),
                    style: TextStyle(
                      fontSize: 10,
                      color: onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (value) =>
              FlLine(color: onSurface.withValues(alpha: 0.08), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (var i = 0; i < points.length; i++)
            BarChartGroupData(
              x: i,
              barsSpace: 4,
              barRods: [
                BarChartRodData(
                  toY: points[i].income,
                  color: const Color(0xFF16A34A),
                  width: 11,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
                BarChartRodData(
                  toY: points[i].expense,
                  color: const Color(0xFFE11D48),
                  width: 11,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
    // Charts paint into their own layer: scrolling the surrounding page no
    // longer forces a full chart repaint.
    return RepaintBoundary(child: chart);
  }

  String _short(double v) {
    if (v >= 1000000000) return '${(v / 1000000000).toStringAsFixed(1)}B';
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }
}

/// Pie chart showing category shares
class CategoryPieChart extends StatelessWidget {
  const CategoryPieChart({super.key, required this.data, this.size = 170});

  final Map<String, double> data;
  final double size;

  static const _palette = [
    Color(0xFF0EA5A4),
    Color(0xFF6366F1),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF8B5CF6),
    Color(0xFF22C55E),
    Color(0xFF38BDF8),
    Color(0xFFF97316),
  ];

  @override
  Widget build(BuildContext context) {
    final entries = data.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return const SizedBox.shrink();
    final total = entries.fold<double>(0, (a, b) => a + b.value);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final chart = Row(
      children: [
        SizedBox(
          height: size,
          width: size,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: size * 0.22,
              sections: [
                for (var i = 0; i < entries.length; i++)
                  PieChartSectionData(
                    value: entries[i].value,
                    color: _palette[i % _palette.length],
                    radius: size * 0.2,
                    showTitle: entries[i].value / total > 0.08,
                    title: Fmt.percent(
                      entries[i].value / total,
                      persian: false,
                    ),
                    titleStyle: const TextStyle(
                      fontFamily: 'Vazirmatn',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < entries.length && i < 6; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: _palette[i % _palette.length],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          entries[i].key.tr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                      Text(
                        Money.text(
                          entries[i].value,
                          compact: true,
                          withSymbol: false,
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: onSurface.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
    // Painted on its own layer so page scrolling does not redraw the pie.
    return RepaintBoundary(child: chart);
  }
}
