import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../core/fmt.dart';
import '../core/money.dart';
import '../core/theme.dart';
import '../logic/forecast.dart';

FlTitlesData _titles(TT t, {Widget Function(double, TitleMeta)? bottom, double bottomSize = 24, bool left = true, double? leftInterval}) => FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: left,
          reservedSize: 44,
          interval: leftInterval,
          getTitlesWidget: (v, m) => v == m.max || v == m.min && v != 0
              ? const SizedBox.shrink()
              : SideTitleWidget(meta: m, child: Text(fCompact((v * 100).round()), style: TextStyle(fontSize: 10.5, color: t.dim))),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(showTitles: bottom != null, reservedSize: bottomSize, getTitlesWidget: bottom ?? (_, _) => const SizedBox.shrink()),
      ),
    );

FlGridData _grid(TT t) => FlGridData(
      show: true,
      drawVerticalLine: false,
      getDrawingHorizontalLine: (_) => FlLine(color: t.line, strokeWidth: 1, dashArray: [3, 4]),
    );

double _niceInterval(double span) {
  if (span <= 0) return 1;
  final raw = span / 4;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  final n = raw / mag;
  final step = n < 1.5 ? 1 : (n < 3 ? 2 : (n < 7 ? 5 : 10));
  return step * mag;
}

/// Andamento mensile del patrimonio (euro, non centesimi, sull'asse).
class NetWorthChart extends StatelessWidget {
  final List<(String, int)> points; // (mese, centesimi)
  final double height;
  const NetWorthChart({super.key, required this.points, this.height = 170});

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    if (points.length < 2) {
      return SizedBox(
        height: 70,
        child: Center(child: Text('Il grafico si riempie mese dopo mese.', style: TS.muted(t, 12.5))),
      );
    }
    final spots = [for (var i = 0; i < points.length; i++) FlSpot(i.toDouble(), points[i].$2 / 100)];
    final ys = spots.map((s) => s.y);
    final lo = ys.reduce(math.min), hi = ys.reduce(math.max);
    final pad = math.max((hi - lo) * 0.15, 50.0);
    return SizedBox(
      height: height,
      child: LineChart(LineChartData(
        minY: lo - pad,
        maxY: hi + pad,
        gridData: _grid(t),
        borderData: FlBorderData(show: false),
        titlesData: _titles(t,
            leftInterval: _niceInterval(hi - lo + 2 * pad),
            bottom: (v, m) {
              final i = v.round();
              if (i < 0 || i >= points.length || v != i.toDouble()) return const SizedBox.shrink();
              final step = math.max(1, (points.length / 6).ceil());
              if (i % step != 0 && i != points.length - 1) return const SizedBox.shrink();
              final d = fromKey('${points[i].$1}-01');
              return SideTitleWidget(meta: m, child: Text(mesiBrevi[d.month - 1], style: TextStyle(fontSize: 10.5, color: t.dim)));
            }),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => t.surf2,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem('${monthLabel(points[s.x.round()].$1)}\n${fEuro((s.y * 100).round())}', TextStyle(color: t.ink, fontSize: 12, fontFamily: 'Sora')),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: TC.accent,
            barWidth: 2.6,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [TC.accent.withValues(alpha: 0.28), TC.accent.withValues(alpha: 0.0)],
              ),
            ),
          ),
        ],
      )),
    );
  }
}

/// Proiezione negli anni: una linea per scenario e l'obiettivo tratteggiato.
class ProjectionChart extends StatelessWidget {
  final List<List<int>> series; // centesimi per anno, per scenario
  final List<String> labels;
  final int? target;
  final double height;
  const ProjectionChart({super.key, required this.series, required this.labels, this.target, this.height = 220});

  static const colors = [Color(0xFF8592B0), TC.accent, TC.pos];

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    if (series.isEmpty || series.first.length < 2) return SizedBox(height: height);
    final years = series.first.length - 1;
    var hi = series.expand((s) => s).fold<int>(0, math.max).toDouble() / 100;
    if (target != null) hi = math.max(hi, target! / 100 * 1.05);
    final lo = math.min(0.0, series.expand((s) => s).fold<int>(0, math.min) / 100);
    final now = DateTime.now().year;
    return SizedBox(
      height: height,
      child: LineChart(LineChartData(
        minY: lo,
        maxY: hi * 1.05,
        gridData: _grid(t),
        borderData: FlBorderData(show: false),
        titlesData: _titles(t, leftInterval: _niceInterval(hi - lo), bottom: (v, m) {
          final y = v.round();
          if (v != y.toDouble()) return const SizedBox.shrink();
          final step = years <= 10 ? 2 : (years <= 20 ? 5 : 10);
          if (y % step != 0) return const SizedBox.shrink();
          return SideTitleWidget(meta: m, child: Text('${now + y}', style: TextStyle(fontSize: 10.5, color: t.dim)));
        }),
        extraLinesData: ExtraLinesData(horizontalLines: [
          if (target != null)
            HorizontalLine(
              y: target! / 100,
              color: TC.warn.withValues(alpha: 0.8),
              strokeWidth: 1.4,
              dashArray: [6, 4],
              label: HorizontalLineLabel(
                show: true,
                alignment: Alignment.topLeft,
                style: const TextStyle(fontSize: 10.5, color: TC.warn, fontWeight: FontWeight.w600),
                labelResolver: (_) => 'obiettivo ${fCompact(target!)}',
              ),
            ),
        ]),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => t.surf2,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${s.barIndex == 0 ? '${now + s.x.round()}\n' : ''}${labels[s.barIndex]}: ${fCompact((s.y * 100).round())}',
                  TextStyle(color: colors[s.barIndex % colors.length], fontSize: 11.5, fontFamily: 'Sora', fontWeight: FontWeight.w600),
                ),
            ],
          ),
        ),
        lineBarsData: [
          for (var i = 0; i < series.length; i++)
            LineChartBarData(
              spots: [for (var y = 0; y < series[i].length; y++) FlSpot(y.toDouble(), series[i][y] / 100)],
              isCurved: true,
              curveSmoothness: 0.2,
              color: colors[i % colors.length],
              barWidth: i == 1 ? 3 : 2,
              dashArray: i == 1 ? null : [5, 4],
              dotData: const FlDotData(show: false),
            ),
        ],
      )),
    );
  }
}

/// Ciambella con legenda (categorie, allocazione).
class Donut extends StatelessWidget {
  final List<(String, int, Color)> items;
  final double size;
  final String? centerTop;
  final String? centerBottom;
  const Donut({super.key, required this.items, this.size = 150, this.centerTop, this.centerBottom});

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final total = items.fold(0, (a, b) => a + math.max(0, b.$2));
    final chart = SizedBox(
      width: size,
      height: size,
      child: Stack(alignment: Alignment.center, children: [
        PieChart(PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: size * 0.33,
          startDegreeOffset: -90,
          sections: [
            if (total == 0) PieChartSectionData(value: 1, color: t.surf2, radius: size * 0.15, showTitle: false),
            for (final it in items)
              if (it.$2 > 0) PieChartSectionData(value: it.$2.toDouble(), color: it.$3, radius: size * 0.15, showTitle: false),
          ],
        )),
        if (centerTop != null)
          Column(mainAxisSize: MainAxisSize.min, children: [
            Text(centerTop!, style: TS.num(t, 15, w: FontWeight.w700)),
            if (centerBottom != null) Text(centerBottom!, style: TS.muted(t, 11)),
          ]),
      ]),
    );
    final legend = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final it in items.take(8))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3.5),
          child: Row(children: [
            Container(width: 9, height: 9, decoration: BoxDecoration(color: it.$3, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 8),
            Expanded(child: Text(it.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: TS.soft(t, 12.5))),
            Text(total > 0 ? fPct(it.$2 / total, 0) : '', style: TS.num(t, 12.5, color: t.dim)),
          ]),
        ),
    ]);
    return Row(children: [chart, const SizedBox(width: 18), Expanded(child: legend)]);
  }
}

/// Entrate e uscite degli ultimi mesi.
class MonthBars extends StatelessWidget {
  final List<(String, int, int)> months; // (mese, entrate, uscite) in centesimi
  final double height;
  const MonthBars({super.key, required this.months, this.height = 170});

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final hi = months.fold<int>(0, (m, e) => math.max(m, math.max(e.$2, e.$3))) / 100;
    return SizedBox(
      height: height,
      child: BarChart(BarChartData(
        maxY: hi <= 0 ? 100 : hi * 1.1,
        gridData: _grid(t),
        borderData: FlBorderData(show: false),
        titlesData: _titles(t, leftInterval: _niceInterval(hi), bottom: (v, m) {
          final i = v.round();
          if (i < 0 || i >= months.length) return const SizedBox.shrink();
          final d = fromKey('${months[i].$1}-01');
          return SideTitleWidget(meta: m, child: Text(mesiBrevi[d.month - 1], style: TextStyle(fontSize: 10.5, color: t.dim)));
        }),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => t.surf2,
            getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(
              '${ri == 0 ? 'Entrate' : 'Uscite'} ${fEuro((rod.toY * 100).round())}',
              TextStyle(color: ri == 0 ? TC.pos : t.ink, fontSize: 11.5, fontFamily: 'Sora'),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < months.length; i++)
            BarChartGroupData(x: i, barsSpace: 3, barRods: [
              BarChartRodData(toY: months[i].$2 / 100, color: TC.pos, width: 8, borderRadius: BorderRadius.circular(3)),
              BarChartRodData(toY: months[i].$3 / 100, color: TC.accent, width: 8, borderRadius: BorderRadius.circular(3)),
            ]),
        ],
      )),
    );
  }
}

/// Saldo previsto di un conto nei prossimi giorni (a gradini).
class ForecastChart extends StatelessWidget {
  final AccountForecast f;
  final int days;
  final double height;
  const ForecastChart({super.key, required this.f, this.days = 90, this.height = 150});

  @override
  Widget build(BuildContext context) {
    final t = context.tt;
    final start = today();
    final spots = <FlSpot>[FlSpot(0, f.start / 100)];
    var last = f.start;
    for (final p in f.points) {
      final x = daysBetween(start, fromKey(p.date)).toDouble();
      spots.add(FlSpot(x, last / 100));
      spots.add(FlSpot(x, p.balance / 100));
      last = p.balance;
    }
    spots.add(FlSpot(days.toDouble(), last / 100));
    final ys = spots.map((s) => s.y);
    final lo = math.min(0.0, ys.reduce(math.min)), hi = ys.reduce(math.max);
    final pad = math.max((hi - lo) * 0.12, 20.0);
    final red = f.firstNegative != null;
    return SizedBox(
      height: height,
      child: LineChart(LineChartData(
        minX: 0,
        maxX: days.toDouble(),
        minY: lo - (lo < 0 ? pad : 0),
        maxY: hi + pad,
        gridData: _grid(t),
        borderData: FlBorderData(show: false),
        titlesData: _titles(t, leftInterval: _niceInterval(hi - lo + pad), bottom: (v, m) {
          if (v % 30 != 0) return const SizedBox.shrink();
          final d = addDays(start, v.round());
          return SideTitleWidget(meta: m, child: Text(shortDate(d), style: TextStyle(fontSize: 10.5, color: t.dim)));
        }),
        extraLinesData: ExtraLinesData(horizontalLines: [
          HorizontalLine(y: 0, color: TC.neg.withValues(alpha: 0.6), strokeWidth: 1, dashArray: [4, 4]),
        ]),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => t.surf2,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem('${shortDate(addDays(start, s.x.round()))}\n${fEuro((s.y * 100).round())}', TextStyle(color: t.ink, fontSize: 11.5, fontFamily: 'Sora')),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: false,
            color: red ? TC.neg : TC.accent,
            barWidth: 2.2,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(show: true, color: (red ? TC.neg : TC.accent).withValues(alpha: 0.08)),
          ),
        ],
      )),
    );
  }
}
