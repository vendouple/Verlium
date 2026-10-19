import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:math_expressions/math_expressions.dart';

import '../theme.dart';

const _palette = [
  Color(0xFF4F8BFF), Color(0xFFF6A23A), Color(0xFF3DBE7A), Color(0xFFE5547A),
  Color(0xFFA77BFF), Color(0xFF2EC4D6), Color(0xFFF2D04B), Color(0xFF9AA0A6),
];

/// Lenient JSON: models sometimes add // comments or trailing commas.
Map<String, dynamic> parseChartSpec(String src) {
  var s = src.replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');
  s = s.replaceAll(RegExp(r'(?<=[\]\}"\d\w])\s*//[^\n"]*$', multiLine: true), '');
  s = s.replaceAllMapped(RegExp(r',\s*([\]\}])'), (m) => m[1]!);
  return jsonDecode(s) as Map<String, dynamic>;
}

/// Turns "2x^2 + sin(x)" style input into something math_expressions parses.
Expression parseFn(String src) {
  var s = src.trim().replaceAll(RegExp(r'^\s*(?:y|f\(x\))\s*=\s*'), '');
  s = s
      .replaceAll('**', '^')
      .replaceAll('π', 'pi')
      .replaceAllMapped(RegExp(r'\b(?:a(?:rc)?)(sin|cos|tan)\('), (m) => 'arc${m[1]}(')
      .replaceAll(RegExp(r'\bexp\('), 'e(')
      .replaceAll(RegExp(r'\blog10\('), '(1/ln(10))*ln(')
      .replaceAll(RegExp(r'\blog\('), '(1/ln(10))*ln(')
      .replaceAllMapped(RegExp(r'(\d)\s*([a-zA-Z(])'), (m) => '${m[1]}*${m[2]}') // 2x → 2*x
      .replaceAllMapped(RegExp(r'\)\s*([a-zA-Z(\d])'), (m) => ')*${m[1]}'); //  (x+1)(x-1)
  return GrammarParser().parse(s);
}

class _Series {
  final String name;
  final Color color;
  final List<FlSpot> spots; // FlSpot.nullSpot breaks the line (asymptotes)
  final List<double> values; // bar / pie
  final bool isFn;
  _Series(this.name, this.color, this.spots, this.values, this.isFn);
}

class ChartView extends StatefulWidget {
  final String spec;
  const ChartView({super.key, required this.spec});

  @override
  State<ChartView> createState() => _ChartViewState();
}

class _ChartViewState extends State<ChartView> {
  Map<String, dynamic>? _spec;
  String? _error;
  List<_Series> _series = const [];
  late double _minX, _maxX, _minY, _maxY;
  final Set<int> _hidden = {};
  bool _showSource = false;

  @override
  void initState() {
    super.initState();
    try {
      _spec = parseChartSpec(widget.spec);
      _build();
    } catch (e) {
      _error = 'Couldn’t draw this chart: $e';
    }
  }

  String get _type => (_spec?['type'] ?? 'line').toString().toLowerCase();
  List<double>? _range(String key) {
    final r = _spec?[key];
    return r is List && r.length == 2 ? [(r[0] as num).toDouble(), (r[1] as num).toDouble()] : null;
  }

  void _build() {
    final raw = List<Map>.from(_spec!['series'] ?? const []);
    final xr = _range('x_range');
    final out = <_Series>[];
    for (final (i, s) in raw.indexed) {
      final color = s['color'] is String ? _hex(s['color']) ?? _palette[i % 8] : _palette[i % 8];
      final name = (s['name'] ?? 'Series ${i + 1}').toString();
      if (s['fn'] != null) {
        final dom = s['domain'] is List ? List<num>.from(s['domain']) : (xr ?? [-5, 5]);
        out.add(_Series(name, color, _sample(s['fn'].toString(), dom[0].toDouble(), dom[1].toDouble()), const [], true));
        continue;
      }
      final data = List.from(s['data'] ?? const []);
      final spots = <FlSpot>[], values = <double>[];
      for (final (j, d) in data.indexed) {
        if (d is List && d.length >= 2) {
          spots.add(FlSpot((d[0] as num).toDouble(), (d[1] as num).toDouble()));
        } else if (d is Map && d['x'] != null) {
          spots.add(FlSpot((d['x'] as num).toDouble(), (d['y'] as num).toDouble()));
        } else if (d is num) {
          values.add(d.toDouble());
          spots.add(FlSpot(j.toDouble(), d.toDouble()));
        }
      }
      out.add(_Series(name, color, spots, values, false));
    }
    _series = out;
    _bounds();
  }

  List<FlSpot> _sample(String fn, double a, double b) {
    final exp = parseFn(fn);
    final cm = ContextModel();
    final ev = RealEvaluator(cm);
    const n = 400;
    final pts = <FlSpot>[];
    double? prev;
    for (var i = 0; i <= n; i++) {
      final x = a + (b - a) * i / n;
      cm.bindVariableName('x', Number(x));
      double y;
      try {
        y = ev.evaluate(exp).toDouble();
      } catch (_) {
        y = double.nan;
      }
      // Break the line at undefined points and vertical asymptotes (e.g. tan, 1/x).
      if (!y.isFinite || (prev != null && (y - prev).abs() > 1e3 && y.sign != prev.sign)) {
        if (pts.isNotEmpty && pts.last != FlSpot.nullSpot) pts.add(FlSpot.nullSpot);
        prev = y.isFinite ? y : null;
        if (!y.isFinite) continue;
      }
      pts.add(FlSpot(x, y));
      prev = y;
    }
    return pts;
  }

  void _bounds() {
    final xs = <double>[], ys = <double>[];
    var anyFn = false;
    for (final s in _series) {
      anyFn |= s.isFn;
      for (final p in s.spots) {
        if (p == FlSpot.nullSpot) continue;
        xs.add(p.x);
        ys.add(p.y);
      }
    }
    if (xs.isEmpty) xs.addAll([0, 1]);
    if (ys.isEmpty) ys.addAll([0, 1]);
    final xr = _range('x_range'), yr = _range('y_range');
    _minX = xr?[0] ?? xs.reduce(math.min);
    _maxX = xr?[1] ?? xs.reduce(math.max);
    if (yr != null) {
      _minY = yr[0];
      _maxY = yr[1];
    } else {
      // Functions with asymptotes would blow the scale up; use robust percentiles instead of min/max.
      final sorted = [...ys]..sort();
      double q(double p) => sorted[((sorted.length - 1) * p).round()];
      var lo = anyFn ? q(.02) : sorted.first, hi = anyFn ? q(.98) : sorted.last;
      if (_type == 'bar' || _type == 'area') lo = math.min(lo, 0);
      if (hi - lo < 1e-9) {
        lo -= 1;
        hi += 1;
      }
      final pad = (hi - lo) * .08;
      _minY = lo - pad;
      _maxY = hi + pad;
    }
    if (_maxX - _minX < 1e-9) _maxX = _minX + 1;
  }

  static Color? _hex(String s) {
    final h = s.replaceAll('#', '');
    if (h.length != 6) return null;
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(0xFF000000 | v);
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble() && v.abs() < 1e6) return v.toInt().toString();
    final a = v.abs();
    if (a >= 1e4 || a < 1e-2) return v.toStringAsExponential(1);
    return v.toStringAsFixed(a < 1 ? 2 : 1);
  }

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final title = _spec?['title']?.toString();
    return Container(
      decoration: BoxDecoration(
        color: v.tonal,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: v.outline),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(_type == 'pie' ? Icons.pie_chart_outline : (_type == 'bar' ? Icons.bar_chart : Icons.show_chart),
              size: 18, color: v.iconMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(title ?? 'Chart',
                style: vText(15, 22, weight: FontWeight.w600, color: v.textTitle),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ),
          IconButton(
            tooltip: _showSource ? 'Show chart' : 'Show data',
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _showSource = !_showSource),
            icon: Icon(_showSource ? Icons.insights : Icons.data_object, size: 18),
          ),
        ]),
        const SizedBox(height: 8),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(_error!, style: vText(13, 18, color: v.error)),
          ),
        if (_showSource || _error != null)
          Container(
            constraints: const BoxConstraints(maxHeight: 260),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: v.bg, borderRadius: BorderRadius.circular(8)),
            child: SingleChildScrollView(
              child: SelectableText(widget.spec.trim(),
                  style: TextStyle(fontFamily: 'Consolas', fontSize: 12, color: v.text)),
            ),
          )
        else ...[
          SizedBox(height: _type == 'pie' ? 240 : 300, child: _chart(context)),
          if (_series.length > 1 || _type == 'pie') ...[const SizedBox(height: 10), _legend(context)],
        ],
      ]),
    );
  }

  Widget _legend(BuildContext context) {
    final v = context.v;
    final labels = List.from(_spec?['labels'] ?? const []);
    final items = _type == 'pie' && _series.isNotEmpty
        ? [for (final (i, _) in _series.first.values.indexed) (i < labels.length ? '${labels[i]}' : '#${i + 1}', _palette[i % 8], i)]
        : [for (final (i, s) in _series.indexed) (s.name, s.color, i)];
    return Wrap(spacing: 14, runSpacing: 6, children: [
      for (final (name, color, i) in items)
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: _type == 'pie' ? null : () => setState(() => _hidden.contains(i) ? _hidden.remove(i) : _hidden.add(i)),
          child: Opacity(
            opacity: _hidden.contains(i) ? .35 : 1,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 6),
              Text(name, style: vText(12, 16, color: v.text)),
            ]),
          ),
        ),
    ]);
  }

  FlTitlesData _titles(BuildContext context, {List? xLabels}) {
    final v = context.v;
    final st = vText(11, 14, color: v.textMuted);
    final xl = _spec?['x_label']?.toString(), yl = _spec?['y_label']?.toString();
    return FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        axisNameWidget: xl == null ? null : Text(xl, style: vText(12, 16, color: v.text)),
        axisNameSize: xl == null ? 0 : 20,
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 24,
          interval: xLabels != null ? 1 : null,
          getTitlesWidget: (value, meta) {
            final label = xLabels != null
                ? (value.round() >= 0 && value.round() < xLabels.length ? '${xLabels[value.round()]}' : '')
                : (value == meta.min || value == meta.max ? '' : _fmt(value));
            return SideTitleWidget(meta: meta, child: Text(label, style: st));
          },
        ),
      ),
      leftTitles: AxisTitles(
        axisNameWidget: yl == null ? null : Text(yl, style: vText(12, 16, color: v.text)),
        axisNameSize: yl == null ? 0 : 20,
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 44,
          getTitlesWidget: (value, meta) => SideTitleWidget(
            meta: meta,
            child: Text(value == meta.min || value == meta.max ? '' : _fmt(value), style: st),
          ),
        ),
      ),
    );
  }

  Widget _chart(BuildContext context) {
    final v = context.v;
    final grid = FlGridData(
      getDrawingHorizontalLine: (_) => FlLine(color: v.outline, strokeWidth: 1),
      getDrawingVerticalLine: (_) => FlLine(color: v.outline, strokeWidth: 1),
    );
    final border = FlBorderData(show: false);
    final tip = v.panel;

    switch (_type) {
      case 'pie':
        final s = _series.isEmpty ? null : _series.first;
        final total = s?.values.fold<double>(0, (a, b) => a + b) ?? 0;
        return PieChart(PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: 48,
          sections: [
            for (final (i, val) in (s?.values ?? const <double>[]).indexed)
              PieChartSectionData(
                value: val,
                color: _palette[i % 8],
                radius: 64,
                title: total == 0 ? '' : '${(val / total * 100).toStringAsFixed(0)}%',
                titleStyle: vText(12, 16, weight: FontWeight.w600, color: Colors.white),
              ),
          ],
        ));
      case 'bar':
        final labels = List.from(_spec?['labels'] ?? const []);
        final n = _series.fold<int>(0, (a, s) => math.max(a, s.values.length));
        final shown = [for (final (i, s) in _series.indexed) if (!_hidden.contains(i)) s];
        return BarChart(BarChartData(
          minY: math.min(0, _minY),
          maxY: _maxY,
          gridData: grid.copyWith(drawVerticalLine: false),
          borderData: border,
          titlesData: _titles(context, xLabels: labels.isEmpty ? List.generate(n, (i) => '${i + 1}') : labels),
          barTouchData: BarTouchData(touchTooltipData: BarTouchTooltipData(getTooltipColor: (_) => tip)),
          barGroups: [
            for (var i = 0; i < n; i++)
              BarChartGroupData(x: i, barsSpace: 3, barRods: [
                for (final s in shown)
                  if (i < s.values.length)
                    BarChartRodData(
                      toY: s.values[i],
                      color: s.color,
                      width: math.max(6, 28 / math.max(1, shown.length)),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    ),
              ]),
          ],
        ));
      case 'scatter':
        return ScatterChart(ScatterChartData(
          minX: _minX,
          maxX: _maxX,
          minY: _minY,
          maxY: _maxY,
          gridData: grid,
          borderData: border,
          titlesData: _titles(context),
          scatterTouchData: ScatterTouchData(touchTooltipData: ScatterTouchTooltipData(getTooltipColor: (_) => tip)),
          scatterSpots: [
            for (final (i, s) in _series.indexed)
              if (!_hidden.contains(i))
                for (final p in s.spots)
                  if (p != FlSpot.nullSpot) ScatterSpot(p.x, p.y, dotPainter: FlDotCirclePainter(color: s.color, radius: 4)),
          ],
        ));
      default: // line / area / function plots
        final area = _type == 'area';
        return LineChart(LineChartData(
          minX: _minX,
          maxX: _maxX,
          minY: _minY,
          maxY: _maxY,
          clipData: const FlClipData.all(),
          gridData: grid,
          borderData: border,
          titlesData: _titles(context),
          // Draw the x and y axes when they're in view, like a maths graph.
          extraLinesData: ExtraLinesData(
            horizontalLines: [if (_minY < 0 && _maxY > 0) HorizontalLine(y: 0, color: v.iconMuted, strokeWidth: 1.2)],
            verticalLines: [if (_minX < 0 && _maxX > 0) VerticalLine(x: 0, color: v.iconMuted, strokeWidth: 1.2)],
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => tip,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem('(${_fmt(s.x)}, ${_fmt(s.y)})', vText(12, 16, color: s.bar.color ?? v.text)),
              ],
            ),
          ),
          lineBarsData: [
            for (final (i, s) in _series.indexed)
              if (!_hidden.contains(i))
                LineChartBarData(
                  spots: s.spots,
                  color: s.color,
                  barWidth: s.isFn ? 2.5 : 2,
                  isCurved: !s.isFn && s.spots.length < 60,
                  preventCurveOverShooting: true,
                  dotData: FlDotData(show: !s.isFn && s.spots.length <= 24),
                  belowBarData: BarAreaData(show: area, color: s.color.withValues(alpha: .18)),
                ),
          ],
        ));
    }
  }
}
