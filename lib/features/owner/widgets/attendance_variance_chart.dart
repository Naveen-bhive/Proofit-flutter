import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../models/attendance_analytics.dart';

/// Overtime (green, above zero) and deficit (red, below zero) per bar, in
/// hours. Scrolls sideways when the bars do not fit, and grows its axis
/// space with the text scale so labels stay readable on small phones.
class AttendanceVarianceChart extends StatelessWidget {
  final List<VariancePoint> points;
  final double height;
  const AttendanceVarianceChart(
      {super.key, required this.points, this.height = 190});

  static const _barWidth = 9.0;
  static const _slot = 30.0;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final labelSize = scaler.scale(10);
    final hasData =
        points.any((p) => p.overtimeMinutes > 0 || p.deficitMinutes > 0);
    final ot = points.fold<int>(0, (a, p) => a + p.overtimeMinutes);
    final deficit = points.fold<int>(0, (a, p) => a + p.deficitMinutes);

    final summary = Semantics(
      label: 'Overtime ${formatMinutes(ot)}, deficit ${formatMinutes(deficit)}',
      child: Wrap(spacing: 14, runSpacing: 6, children: [
        _legend(AppColors.green, 'Overtime', formatMinutes(ot)),
        _legend(AppColors.red, 'Deficit', formatMinutes(deficit)),
      ]),
    );

    if (!hasData) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        summary,
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 28),
          child: Center(
            child: Text('No overtime or deficit in this range',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.muted, fontSize: 13)),
          ),
        ),
      ]);
    }

    final maxUp =
        points.map((p) => p.overtimeMinutes).fold<int>(0, math.max) / 60;
    final maxDown =
        points.map((p) => p.deficitMinutes).fold<int>(0, math.max) / 60;
    final top = _niceCeil(maxUp);
    final bottom = -_niceCeil(maxDown);
    final interval = _interval(top - bottom);

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      summary,
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, constraints) {
        final leftReserved = math.max(30.0, labelSize * 3.4);
        final width = math.max(
            constraints.maxWidth, leftReserved + points.length * _slot);
        final chart = SizedBox(
          width: width,
          height: height + labelSize * 2,
          child: BarChart(
            BarChartData(
              minY: bottom,
              maxY: top,
              alignment: BarChartAlignment.spaceAround,
              barGroups: [
                for (var i = 0; i < points.length; i++)
                  BarChartGroupData(x: i, groupVertically: true, barRods: [
                    BarChartRodData(
                      fromY: 0,
                      toY: points[i].overtimeMinutes / 60,
                      width: _barWidth,
                      color: AppColors.green,
                      borderRadius: BorderRadius.circular(3),
                    ),
                    BarChartRodData(
                      fromY: -points[i].deficitMinutes / 60,
                      toY: 0,
                      width: _barWidth,
                      color: AppColors.red,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ]),
              ],
              gridData: FlGridData(
                drawVerticalLine: false,
                horizontalInterval: interval,
                getDrawingHorizontalLine: (v) => FlLine(
                  color: v == 0 ? AppColors.silver : AppColors.border,
                  strokeWidth: v == 0 ? 1.2 : 0.6,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: leftReserved,
                    interval: interval,
                    getTitlesWidget: (v, meta) => SideTitleWidget(
                      axisSide: meta.axisSide,
                      child: Text('${_trim(v)}h',
                          style: const TextStyle(
                              color: AppColors.muted, fontSize: 10)),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: labelSize * 2.2,
                    getTitlesWidget: (v, meta) {
                      final i = v.toInt();
                      if (i < 0 || i >= points.length) {
                        return const SizedBox.shrink();
                      }
                      return SideTitleWidget(
                        axisSide: meta.axisSide,
                        space: 4,
                        child: Text(points[i].label,
                            style: const TextStyle(
                                color: AppColors.silver, fontSize: 10)),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => AppColors.text,
                  fitInsideHorizontally: true,
                  fitInsideVertically: true,
                  getTooltipItem: (group, _, rod, rodIndex) {
                    if (rod.toY == rod.fromY) return null;
                    final p = points[group.x];
                    return BarTooltipItem(
                      '${p.label}\n${formatVariance(rodIndex == 0 ? p.overtimeMinutes : -p.deficitMinutes)}',
                      const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w700),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        return width > constraints.maxWidth
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal, child: chart)
            : chart;
      }),
    ]);
  }

  Widget _legend(Color color, String label, String value) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 6),
        Text('$label $value',
            style: const TextStyle(
                color: AppColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ]);

  static double _niceCeil(double hours) {
    if (hours <= 0) return 0.5;
    if (hours <= 1) return (hours * 4).ceilToDouble() / 4;
    return hours.ceilToDouble();
  }

  static double _interval(double span) {
    if (span <= 1) return 0.25;
    if (span <= 3) return 0.5;
    if (span <= 8) return 1;
    return (span / 6).ceilToDouble();
  }

  static String _trim(double v) => v == v.roundToDouble()
      ? v.toInt().toString()
      : v.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}
