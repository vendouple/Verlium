import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../api/models.dart';
import '../theme.dart';
import 'chart_view.dart';
import 'html_widget_view.dart';
import 'markdown.dart';

/// A piece of an assistant message: markdown text, display math, a chart, an interactive widget,
/// or a visual whose fence hasn't closed yet (still streaming).
sealed class Segment {}

class TextSeg extends Segment {
  final String text;
  TextSeg(this.text);
}

class MathSeg extends Segment {
  final String tex;
  MathSeg(this.tex);
}

class ChartSeg extends Segment {
  final String json;
  ChartSeg(this.json);
}

class WidgetSeg extends Segment {
  final String html;
  WidgetSeg(this.html);
}

class PendingSeg extends Segment {
  final String kind;
  final int chars;
  PendingSeg(this.kind, this.chars);
}

const _visualLangs = {'chart', 'widget', 'html', 'svg', 'math', 'latex', 'tex'};

// ```lang ... ```   |   $$ ... $$   |   \[ ... \]
final _blockRe = RegExp(r'```([\w-]*)[^\n]*\n([\s\S]*?)(?:```|$)|\$\$([\s\S]+?)\$\$|\\\[([\s\S]+?)\\\]');

List<Segment> splitSegments(String text) {
  final out = <Segment>[];
  var pos = 0;
  void addText(String t) {
    if (t.trim().isNotEmpty) out.add(TextSeg(t));
  }

  for (final m in _blockRe.allMatches(text)) {
    final full = m.group(0)!;
    final lang = (m.group(1) ?? '').toLowerCase();
    if (full.startsWith('```') && !_visualLangs.contains(lang)) continue; // ordinary code: leave to markdown
    addText(text.substring(pos, m.start));
    pos = m.end;
    if (full.startsWith('```')) {
      final body = m.group(2)!;
      final closed = full.trimRight().endsWith('```') && full.length > 6 + lang.length;
      if (!closed) {
        out.add(PendingSeg(lang, body.length));
      } else if (lang == 'chart') {
        out.add(ChartSeg(body));
      } else if (lang == 'math' || lang == 'latex' || lang == 'tex') {
        out.add(MathSeg(body.trim()));
      } else {
        out.add(WidgetSeg(body));
      }
    } else {
      out.add(MathSeg((m.group(3) ?? m.group(4))!.trim()));
    }
  }
  addText(text.substring(pos));
  // Ordinary code fences that were skipped above are still inside the text segments, intact.
  return _mergeText(out);
}

List<Segment> _mergeText(List<Segment> segs) {
  final out = <Segment>[];
  for (final s in segs) {
    if (s is TextSeg && out.isNotEmpty && out.last is TextSeg) {
      out[out.length - 1] = TextSeg((out.last as TextSeg).text + s.text);
    } else {
      out.add(s);
    }
  }
  return out;
}

/// Assistant message body: markdown + LaTeX + charts + interactive widgets.
class RichContent extends StatelessWidget {
  final String data;
  final List<Citation> citations;
  final void Function(Citation c)? onCitation;
  final double fontSize, lineHeight;
  const RichContent({
    super.key,
    required this.data,
    this.citations = const [],
    this.onCitation,
    this.fontSize = 17,
    this.lineHeight = 24,
  });

  @override
  Widget build(BuildContext context) {
    final segs = splitSegments(data);
    if (segs.length == 1 && segs.first is TextSeg) {
      return VMarkdown(data: data, citations: citations, onCitation: onCitation, fontSize: fontSize, lineHeight: lineHeight);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (i, s) in segs.indexed)
        switch (s) {
          TextSeg(:final text) => VMarkdown(
              data: text, citations: citations, onCitation: onCitation, fontSize: fontSize, lineHeight: lineHeight),
          MathSeg(:final tex) => DisplayMath(tex: tex, fontSize: fontSize + 2),
          ChartSeg(:final json) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ChartView(key: ValueKey('chart$i${json.hashCode}'), spec: json),
            ),
          WidgetSeg(:final html) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: HtmlWidgetView(key: ValueKey('w$i${html.hashCode}'), html: html),
            ),
          PendingSeg() => _Pending(seg: s),
        },
    ]);
  }
}

class DisplayMath extends StatelessWidget {
  final String tex;
  final double fontSize;
  const DisplayMath({super.key, required this.tex, this.fontSize = 19});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    // ChatGPT-style display maths: centred, a size up from body text, bright, with room above and below so
    // worked steps stand apart from the prose. Wide equations scroll sideways instead of overflowing.
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: c.maxWidth),
            child: Center(
              child: Math.tex(
                tex,
                mathStyle: MathStyle.display,
                textStyle: TextStyle(fontSize: fontSize * 1.18, color: v.textTitle),
                onErrorFallback: (e) => Text('\$\$$tex\$\$',
                    style: TextStyle(fontFamily: 'Consolas', fontSize: fontSize - 4, color: v.textMuted)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Pending extends StatelessWidget {
  final PendingSeg seg;
  const _Pending({required this.seg});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final what = switch (seg.kind) { 'chart' => 'Drawing chart', 'math' || 'latex' || 'tex' => 'Writing maths', _ => 'Building interactive visual' };
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      height: 120,
      decoration: BoxDecoration(
        color: v.tonal,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: v.outline),
      ),
      child: Center(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: v.primary)),
          const SizedBox(width: 12),
          Text('$what…', style: vText(14, 20, color: v.textStrong)),
          const SizedBox(width: 8),
          Text('${seg.chars} chars', style: vText(12, 16, color: v.textMuted)),
        ]),
      ),
    );
  }
}
