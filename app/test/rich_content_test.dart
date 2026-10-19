import 'package:flutter_test/flutter_test.dart';
import 'package:math_expressions/math_expressions.dart';
import 'package:verlium/widgets/chart_view.dart';
import 'package:verlium/widgets/rich_content.dart';

void main() {
  test('splits text, display math, charts, widgets; keeps ordinary code in markdown', () {
    const msg = 'Intro \$x^2\$ here.\n\n\$\$\int_0^1 x\,dx\$\$\n\n```python\nprint(1)\n```\n'
        '```chart\n{"type":"line","series":[{"fn":"x^2"}]}\n```\nMid\n```widget\n<h3>Hi</h3>\n```\nEnd';
    final s = splitSegments(msg);
    expect(s.map((e) => e.runtimeType.toString()).toList(),
        ['TextSeg', 'MathSeg', 'TextSeg', 'ChartSeg', 'TextSeg', 'WidgetSeg', 'TextSeg']);
    expect((s[2] as TextSeg).text, contains('```python'));
  });

  test('unclosed visual fence while streaming is pending', () {
    final s = splitSegments('Look:\n```widget\n<div>partial');
    expect(s.last, isA<PendingSeg>());
  });

  test('function parser handles implicit multiplication and aliases', () {
    double at(String f, double x) =>
        RealEvaluator(ContextModel()..bindVariableName('x', Number(x))).evaluate(parseFn(f)).toDouble();
    expect(at('y = 2x^2 + 1', 3), 19);
    expect(at('abs(x)', -0.7), closeTo(.7, 1e-9));
    expect(at('exp(0) + log(100)', 0), closeTo(3, 1e-9));
    expect(at('(x+1)(x-1)', 3), 8);
  });

  test('lenient chart JSON', () {
    final spec = parseChartSpec('{\n // comment\n "type": "bar", "series": [{"data": [1,2,],},],\n}');
    expect(spec['type'], 'bar');
  });
}
