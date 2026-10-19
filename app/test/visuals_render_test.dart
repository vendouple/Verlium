import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verlium/theme.dart';
import 'package:verlium/widgets/rich_content.dart';

Widget _wrap(Widget w) => MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(body: SingleChildScrollView(child: SizedBox(width: 700, child: w))),
    );

void main() {
  for (final spec in [
    '{"type":"line","title":"y = |x|","series":[{"name":"|x|","fn":"abs(x)","domain":[-1.5,1.5]},{"name":"tan","fn":"tan(x)"}]}',
    '{"type":"bar","labels":["Q1","Q2"],"series":[{"name":"A","data":[3,5]},{"name":"B","data":[2,4]}]}',
    '{"type":"pie","labels":["a","b","c"],"series":[{"data":[1,2,3]}]}',
    '{"type":"scatter","series":[{"data":[[0,1],[1,3],[2,2]]}]}',
  ]) {
    testWidgets('renders chart ${spec.substring(9, 15)}', (t) async {
      await t.pumpWidget(_wrap(RichContent(data: 'Here:\n```chart\n$spec\n```\nDone')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.textContaining('Couldn’t draw'), findsNothing);
      expect(find.byWidgetPredicate((w) => w is LineChart || w is BarChart || w is PieChart || w is ScatterChart),
          findsOneWidget);
    });
  }

  testWidgets('renders inline and display LaTeX', (t) async {
    await t.pumpWidget(_wrap(const RichContent(
        data: r'For $\epsilon > 0$ pick $\delta = \epsilon$, costs $5 and $10.' '\n\n' r'$$\lim_{x\to 0} |x| = 0$$')));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.byType(Math), findsNWidgets(3)); // two inline + one display; the dollar amounts stay text
  });
}
