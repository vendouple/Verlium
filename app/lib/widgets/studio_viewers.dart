import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../state/notebook_store.dart';
import '../theme.dart';
import 'common.dart';
import 'rich_content.dart';
import 'studio_media_viewers.dart';

StudioType studioTypeOf(String t) => switch (t) {
      'audio' => StudioType.audio,
      'report' => StudioType.report,
      'flashcards' => StudioType.flashcards,
      'quiz' => StudioType.quiz,
      'mindmap' => StudioType.mindmap,
      'table' => StudioType.table,
      'slides' => StudioType.slides,
      'video' => StudioType.video,
      'infographic' => StudioType.infographic,
      _ => StudioType.report,
    };

/// Viewer chrome (UI-SPEC §3.7): breadcrumb, title, expand, prompt pill, body.
class StudioViewer extends StatelessWidget {
  final NotebookStore store;
  final StudioOutput output;
  final bool expanded;
  const StudioViewer({super.key, required this.store, required this.output, this.expanded = false});

  void _close(BuildContext context) => expanded ? Navigator.pop(context) : store.showOutput(null);

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final t = studioTypeOf(output.type);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 48,
        child: Row(children: [
          TextButton(
            onPressed: () => _close(context),
            child: Text('Studio  ›  ${t.label}', style: vText(14, 20, color: v.textMuted)),
          ),
          const Spacer(),
          if (!expanded)
            IconButton(
              tooltip: 'Expand',
              icon: Icon(Icons.open_in_full_rounded, size: 18, color: v.iconMuted),
              onPressed: () => showDialog(
                context: context,
                builder: (_) => Dialog(
                  insetPadding: const EdgeInsets.all(24),
                  child: SizedBox(
                    width: 1180,
                    height: 760,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: StudioViewer(store: store, output: output, expanded: true),
                    ),
                  ),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => _close(context),
            icon: Icon(Icons.close_fullscreen_rounded, size: 18, color: v.iconMuted),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Row(children: [
          Icon(t.icon, color: t.tint(context), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(output.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: vText(20, 26, color: v.textTitle)),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Align(alignment: Alignment.centerLeft, child: _PromptPill(store: store, output: output)),
      ),
      Expanded(child: _body()),
    ]);
  }

  Widget _body() => switch (output.type) {
        'report' => _ReportView(store: store, output: output),
        'flashcards' => _FlashcardsView(store: store, output: output),
        'quiz' => _QuizView(store: store, output: output),
        'mindmap' => _MindMapView(store: store, output: output),
        'table' => _TableView(output: output),
        'audio' => _AudioView(output: output),
        'slides' => SlidesView(output: output),
        'infographic' => InfographicView(output: output),
        'video' => VideoView(output: output),
        _ => const Center(child: Text('No viewer for this type yet')),
      };
}

class _PromptPill extends StatelessWidget {
  final NotebookStore store;
  final StudioOutput output;
  const _PromptPill({required this.store, required this.output});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final n = output.sourceIds.length;
    final opts = output.options.entries.map((e) => '${e.key}: ${e.value}').join(' · ');
    return PopupMenuButton<String>(
      tooltip: 'View prompt and sources',
      position: PopupMenuPosition.under,
      onSelected: (a) {
        if (a == 'retry') store.retryOutput(output);
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Prompt', style: vText(12, 16, color: v.textMuted)),
              const SizedBox(height: 4),
              Text(output.prompt.isEmpty ? '(no focus prompt)' : output.prompt, style: vText(14, 20, color: v.textStrong)),
              if (opts.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(opts, style: vText(12, 16, color: v.textMuted)),
              ],
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final s in store.sources.where((s) => output.sourceIds.contains(s.id)))
                  Chip(visualDensity: VisualDensity.compact, label: Text(s.title, style: vText(12, 16))),
              ]),
            ]),
          ),
        ),
        const PopupMenuItem(value: 'retry', child: MenuRow(Icons.refresh, 'Re-run with the same prompt')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: v.outline)),
        child: Text('View prompt and $n source${n == 1 ? '' : 's'}', style: vText(13, 18, color: v.textStrong)),
      ),
    );
  }
}

// ---- report ---------------------------------------------------------------------------------

class _ReportView extends StatelessWidget {
  final NotebookStore store;
  final StudioOutput output;
  const _ReportView({required this.store, required this.output});

  @override
  Widget build(BuildContext context) {
    final md = (output.content['markdown'] ?? '') as String;
    return Column(children: [
      Expanded(
        child: SelectionArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: RichContent(data: md, fontSize: 15, lineHeight: 24),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          OutlinedButton.icon(
            onPressed: () async {
              await store.createNote(title: output.title, content: md, kind: 'report');
              if (context.mounted) toast(context, 'Saved to notes');
            },
            icon: const Icon(Icons.push_pin_outlined, size: 16),
            label: const Text('Save to note'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: md));
              toast(context, 'Copied as Markdown');
            },
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copy'),
          ),
        ]),
      ),
    ]);
  }
}

// ---- flashcards -----------------------------------------------------------------------------

class _FlashcardsView extends StatefulWidget {
  final NotebookStore store;
  final StudioOutput output;
  const _FlashcardsView({required this.store, required this.output});

  @override
  State<_FlashcardsView> createState() => _FlashcardsViewState();
}

class _FlashcardsViewState extends State<_FlashcardsView> {
  int _i = 0, _right = 0, _wrong = 0;
  bool _back = false;
  final _focus = FocusNode();

  List<Map> get _cards => List<Map>.from(widget.output.content['cards'] ?? const []);

  void _go(int d) => setState(() {
        _i = (_i + d).clamp(0, _cards.length - 1);
        _back = false;
      });

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final cards = _cards;
    if (cards.isEmpty) return const Center(child: Text('No cards'));
    final c = cards[_i];
    final tint = StudioType.flashcards.tint(context);
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (_, e) {
        if (e is! KeyDownEvent) return KeyEventResult.ignored;
        if (e.logicalKey == LogicalKeyboardKey.space) {
          setState(() => _back = !_back);
        } else if (e.logicalKey == LogicalKeyboardKey.arrowRight) {
          _go(1);
        } else if (e.logicalKey == LogicalKeyboardKey.arrowLeft) {
          _go(-1);
        } else {
          return KeyEventResult.ignored;
        }
        return KeyEventResult.handled;
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text('Press "Space" to flip, "← / →" to navigate', style: vText(12, 16, color: v.textMuted)),
          const SizedBox(height: 12),
          Expanded(
            child: GestureDetector(
              onTap: () {
                _focus.requestFocus();
                setState(() => _back = !_back);
              },
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: _back ? 1 : 0),
                duration: const Duration(milliseconds: 320),
                builder: (context, t, _) {
                  final showBack = t > .5;
                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, .001)
                      ..rotateY(math.pi * t),
                    child: Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.identity()..rotateY(showBack ? math.pi : 0),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          color: v.tonal,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [BoxShadow(color: tint.withValues(alpha: .18), blurRadius: 40, spreadRadius: 2)],
                        ),
                        child: Center(
                          child: SingleChildScrollView(
                            child: Text(
                              (showBack ? c['back'] : c['front']).toString(),
                              textAlign: TextAlign.center,
                              style: vText(showBack ? 18 : 22, showBack ? 28 : 32, color: v.textTitle),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(onPressed: _i > 0 ? () => _go(-1) : null, icon: const Icon(Icons.arrow_back_rounded)),
            const SizedBox(width: 8),
            _countBtn(Icons.close_rounded, _wrong, v.error, () {
              setState(() => _wrong++);
              _go(1);
            }),
            const SizedBox(width: 12),
            Text('${_i + 1} / ${cards.length}', style: vText(14, 20, color: v.textStrong)),
            const SizedBox(width: 12),
            _countBtn(Icons.check_rounded, _right, v.success, () {
              setState(() => _right++);
              _go(1);
            }),
            const SizedBox(width: 8),
            IconButton(onPressed: _i < cards.length - 1 ? () => _go(1) : null, icon: const Icon(Icons.arrow_forward_rounded)),
          ]),
          TextButton.icon(
            onPressed: () => widget.store.ask('Explain this flashcard using the sources.\n'
                'Front: ${c['front']}\nBack: ${c['back']}'),
            icon: const Icon(Icons.chat_outlined, size: 16),
            label: const Text('Explain'),
          ),
        ]),
      ),
    );
  }

  Widget _countBtn(IconData icon, int n, Color color, VoidCallback onTap) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(foregroundColor: color, side: BorderSide(color: color.withValues(alpha: .5))),
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text('$n'),
      );
}

// ---- quiz -------------------------------------------------------------------------------------

class _QuizView extends StatefulWidget {
  final NotebookStore store;
  final StudioOutput output;
  const _QuizView({required this.store, required this.output});

  @override
  State<_QuizView> createState() => _QuizViewState();
}

class _QuizViewState extends State<_QuizView> {
  int _i = 0;
  final Map<int, int> _answers = {};
  bool _hint = false;

  List<Map> get _qs => List<Map>.from(widget.output.content['questions'] ?? const []);

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final qs = _qs;
    if (qs.isEmpty) return const Center(child: Text('No questions'));
    if (_i >= qs.length) return _summary(qs);
    final q = qs[_i];
    final opts = List<Map>.from(q['options'] ?? const []);
    final picked = _answers[_i];
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('${_i + 1} / ${qs.length}', style: vText(13, 18, color: v.textMuted)),
      const SizedBox(height: 8),
      Text(q['question'].toString(), style: vText(18, 26, color: v.textTitle)),
      const SizedBox(height: 16),
      for (var k = 0; k < opts.length; k++) _option(k, opts[k], picked),
      const SizedBox(height: 8),
      Row(children: [
        if (q['hint'] != null && picked == null)
          TextButton.icon(
            onPressed: () => setState(() => _hint = !_hint),
            icon: const Icon(Icons.lightbulb_outline, size: 16),
            label: const Text('Hint'),
          ),
        if (picked != null)
          TextButton.icon(
            onPressed: () => widget.store.ask('Explain this quiz question using the sources.\n'
                'Question: ${q['question']}\nCorrect answer: ${opts.firstWhere((o) => o['correct'] == true)['text']}'),
            icon: const Icon(Icons.chat_outlined, size: 16),
            label: const Text('Explain'),
          ),
        const Spacer(),
        if (_i > 0) TextButton(onPressed: () => setState(() => _i--), child: const Text('Previous')),
        FilledButton(
          onPressed: picked == null ? null : () => setState(() {
                _i++;
                _hint = false;
              }),
          child: Text(_i == qs.length - 1 ? 'Finish' : 'Next'),
        ),
      ]),
      if (_hint && picked == null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(q['hint'].toString(), style: vText(14, 20, color: v.textMuted)),
        ),
    ]);
  }

  Widget _option(int k, Map o, int? picked) {
    final v = context.v;
    final answered = picked != null;
    final correct = o['correct'] == true;
    final border = !answered
        ? v.outline
        : correct
            ? v.success
            : (picked == k ? v.error : v.outline);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: answered ? null : () => setState(() => _answers[_i] = k),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(border: Border.all(color: border, width: answered && border != v.outline ? 2 : 1), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${String.fromCharCode(65 + k)}.  ', style: vText(15, 22, weight: FontWeight.w600, color: v.textStrong)),
                Expanded(child: Text(o['text'].toString(), style: vText(15, 22, color: v.textStrong))),
              ]),
              if (answered && (correct || picked == k)) ...[
                const SizedBox(height: 6),
                Row(children: [
                  Icon(correct ? Icons.check_circle : Icons.cancel, size: 16, color: correct ? v.success : v.error),
                  const SizedBox(width: 6),
                  Text(correct ? 'Right answer' : 'Not quite', style: vText(13, 18, weight: FontWeight.w600, color: correct ? v.success : v.error)),
                ]),
              ],
              if (answered && o['rationale'] != null) ...[
                const SizedBox(height: 4),
                Text(o['rationale'].toString(), style: vText(13, 18, color: v.textMuted)),
              ],
            ]),
          ),
        ),
      ),
    );
  }

  Widget _summary(List<Map> qs) {
    final v = context.v;
    var score = 0;
    _answers.forEach((qi, oi) {
      final opts = List<Map>.from(qs[qi]['options'] ?? const []);
      if (oi < opts.length && opts[oi]['correct'] == true) score++;
    });
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('$score / ${qs.length}', style: vText(48, 56, weight: FontWeight.w300, color: v.textTitle)),
        const SizedBox(height: 8),
        Text(score == qs.length ? 'Perfect score!' : 'Nice work. Review the ones you missed.', style: vText(15, 22, color: v.textMuted)),
        const SizedBox(height: 16),
        FilledButton(onPressed: () => setState(() {
              _i = 0;
              _answers.clear();
            }), child: const Text('Retake quiz')),
      ]),
    );
  }
}

// ---- mind map --------------------------------------------------------------------------------

class _MNode {
  final String label;
  final List<_MNode> children;
  bool open;
  Offset pos = Offset.zero;
  Size size = Size.zero;
  _MNode(this.label, this.children, this.open);

  static _MNode from(Map j, int depth) => _MNode(
        (j['label'] ?? '').toString(),
        [for (final c in (j['children'] ?? const [])) from(Map.from(c), depth + 1)],
        depth < 1,
      );
}

class _MindMapView extends StatefulWidget {
  final NotebookStore store;
  final StudioOutput output;
  const _MindMapView({required this.store, required this.output});

  @override
  State<_MindMapView> createState() => _MindMapViewState();
}

class _MindMapViewState extends State<_MindMapView> {
  late _MNode _root = _MNode.from(Map.from(widget.output.content['root'] ?? {'label': widget.output.title}), 0);
  final _tc = TransformationController();
  static const _hGap = 56.0, _vGap = 10.0, _nodeH = 36.0;

  Size _measure(String text) {
    final tp = TextPainter(text: TextSpan(text: text, style: vText(13, 17)), textDirection: TextDirection.ltr, maxLines: 1)
      ..layout(maxWidth: 240);
    return Size(tp.width + 36 + 24, _nodeH);
  }

  /// Lays out the visible tree left→right; returns total height used.
  double _layout(_MNode n, double x, double y) {
    n.size = _measure(n.label);
    final kids = n.open ? n.children : const <_MNode>[];
    if (kids.isEmpty) {
      n.pos = Offset(x, y);
      return _nodeH + _vGap;
    }
    var h = 0.0;
    final childX = x + n.size.width + _hGap;
    for (final c in kids) {
      h += _layout(c, childX, y + h);
    }
    final first = kids.first.pos.dy, last = kids.last.pos.dy;
    n.pos = Offset(x, (first + last) / 2);
    return math.max(h, _nodeH + _vGap);
  }

  void _setAll(_MNode n, bool open) {
    n.open = open;
    for (final c in n.children) {
      _setAll(c, open);
    }
  }

  Iterable<_MNode> _visible(_MNode n) sync* {
    yield n;
    if (n.open) {
      for (final c in n.children) {
        yield* _visible(c);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final h = _layout(_root, 16, 16);
    final nodes = _visible(_root).toList();
    final w = nodes.map((n) => n.pos.dx + n.size.width).fold<double>(0, math.max) + 32;
    final tint = StudioType.mindmap.tint(context);
    return Stack(children: [
      InteractiveViewer(
        transformationController: _tc,
        constrained: false,
        boundaryMargin: const EdgeInsets.all(400),
        minScale: .3,
        maxScale: 2.5,
        child: SizedBox(
          width: w,
          height: h + 32,
          child: Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _EdgePainter(_root, v.divider))),
            for (final n in nodes)
              Positioned(
                left: n.pos.dx,
                top: n.pos.dy,
                child: _nodeWidget(n, n == _root, tint),
              ),
          ]),
        ),
      ),
      Positioned(
        right: 8,
        bottom: 8,
        child: Container(
          decoration: BoxDecoration(color: v.panel, borderRadius: BorderRadius.circular(999), border: Border.all(color: v.outline)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(tooltip: 'Expand all', icon: const Icon(Icons.unfold_more, size: 18), onPressed: () => setState(() => _setAll(_root, true))),
            IconButton(tooltip: 'Collapse all', icon: const Icon(Icons.unfold_less, size: 18), onPressed: () => setState(() {
                  _setAll(_root, false);
                  _root.open = true;
                })),
            IconButton(tooltip: 'Zoom in', icon: const Icon(Icons.add, size: 18), onPressed: () => _zoom(1.2)),
            IconButton(tooltip: 'Zoom out', icon: const Icon(Icons.remove, size: 18), onPressed: () => _zoom(1 / 1.2)),
            IconButton(tooltip: 'Reset view', icon: const Icon(Icons.center_focus_strong_outlined, size: 18), onPressed: () => _tc.value = Matrix4.identity()),
          ]),
        ),
      ),
    ]);
  }

  void _zoom(double f) => _tc.value = _tc.value.clone()..scaleByDouble(f, f, 1, 1);

  Widget _nodeWidget(_MNode n, bool root, Color tint) {
    final v = context.v;
    return SizedBox(
      width: n.size.width,
      height: _nodeH,
      child: Material(
        color: root ? tint.withValues(alpha: .25) : v.tonal,
        shape: StadiumBorder(side: BorderSide(color: tint.withValues(alpha: root ? .8 : .35))),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => widget.store.ask(
              'Discuss what these sources say about ${n.label}, in the larger context of ${_root.label}.'),
          child: Row(children: [
            const SizedBox(width: 14),
            Expanded(
              child: Text(n.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: vText(13, 17, color: v.textStrong)),
            ),
            if (n.children.isNotEmpty)
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setState(() => n.open = !n.open),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(n.open ? Icons.chevron_left : Icons.chevron_right, size: 18, color: v.iconMuted),
                ),
              )
            else
              const SizedBox(width: 12),
          ]),
        ),
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  final _MNode root;
  final Color color;
  _EdgePainter(this.root, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    void walk(_MNode n) {
      if (!n.open) return;
      final from = Offset(n.pos.dx + n.size.width, n.pos.dy + n.size.height / 2);
      for (final c in n.children) {
        final to = Offset(c.pos.dx, c.pos.dy + c.size.height / 2);
        final mid = (from.dx + to.dx) / 2;
        canvas.drawPath(Path()..moveTo(from.dx, from.dy)..cubicTo(mid, from.dy, mid, to.dy, to.dx, to.dy), p);
        walk(c);
      }
    }

    walk(root);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ---- data table --------------------------------------------------------------------------------

class _TableView extends StatelessWidget {
  final StudioOutput output;
  const _TableView({required this.output});

  String _csv(List cols, List rows) {
    String cell(Object? c) {
      final s = (c ?? '').toString();
      return s.contains(RegExp(r'[",\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    return [cols.map(cell).join(','), for (final r in rows) (r as List).map(cell).join(',')].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final cols = List.from(output.content['columns'] ?? const []);
    final rows = List.from(output.content['rows'] ?? const []);
    return Column(children: [
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingTextStyle: vText(14, 20, weight: FontWeight.w600, color: v.textStrong),
              dataTextStyle: vText(14, 20, color: v.text),
              dividerThickness: .6,
              dataRowMaxHeight: double.infinity,
              columns: [for (final c in cols) DataColumn(label: Text(c.toString()))],
              rows: [
                for (final r in rows)
                  DataRow(cells: [
                    for (final c in (r as List))
                      DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 280),
                        child: Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: SelectableText(c.toString())),
                      )),
                  ]),
              ],
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _csv(cols, rows)));
              toast(context, 'Copied as CSV, ready to paste into Excel or Sheets');
            },
            icon: const Icon(Icons.table_view_outlined, size: 16),
            label: const Text('Copy as CSV'),
          ),
        ),
      ),
    ]);
  }
}

// ---- audio --------------------------------------------------------------------------------------

class _AudioView extends StatefulWidget {
  final StudioOutput output;
  const _AudioView({required this.output});

  @override
  State<_AudioView> createState() => _AudioViewState();
}

class _AudioViewState extends State<_AudioView> {
  final _player = AudioPlayer();
  final _subs = <StreamSubscription>[];
  Duration _pos = Duration.zero, _dur = Duration.zero;
  bool _playing = false;
  double _speed = 1.0;
  final _scroll = ScrollController();
  int _line = -1;

  String get _url => Api.I.mediaUrl('/studio/${widget.output.id}/media');
  List<Map> get _lines => List<Map>.from(widget.output.content['transcript'] ?? const []);

  @override
  void initState() {
    super.initState();
    _dur = Duration(milliseconds: ((widget.output.durationS ?? 0) * 1000).round());
    _subs.addAll([
      _player.onPositionChanged.listen((p) {
        final lines = _lines;
        var idx = -1;
        for (var i = 0; i < lines.length; i++) {
          if ((lines[i]['start'] as num) * 1000 <= p.inMilliseconds) idx = i;
        }
        setState(() {
          _pos = p;
          if (idx != _line) _line = idx;
        });
      }),
      _player.onDurationChanged.listen((d) => setState(() => _dur = d)),
      _player.onPlayerStateChanged.listen((s) => setState(() => _playing = s == PlayerState.playing)),
    ]);
    _player.setSourceUrl(_url);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  Future<void> _seek(Duration d) => _player.seek(d < Duration.zero ? Duration.zero : (d > _dur ? _dur : d));

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final lines = _lines;
    final max = _dur.inMilliseconds.toDouble();
    return Column(children: [
      Expanded(
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: lines.length,
          itemBuilder: (context, i) {
            final l = lines[i];
            final active = i == _line;
            final b = l['speaker'].toString().toUpperCase().startsWith('B');
            return InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _seek(Duration(milliseconds: ((l['start'] as num) * 1000).round())),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: active ? v.tonal : null, borderRadius: BorderRadius.circular(12)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: (b ? const Color(0xFFF872B9) : const Color(0xFF76A0FF)).withValues(alpha: .25),
                    child: Text(b ? 'B' : 'A', style: vText(11, 14, weight: FontWeight.w600, color: v.textStrong)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(l['text'].toString(),
                        style: vText(14, 22, color: active ? v.textTitle : v.text)),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
      Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(color: v.tonal, borderRadius: BorderRadius.circular(20)),
        child: Column(children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6)),
            child: Slider(
              value: _pos.inMilliseconds.clamp(0, max <= 0 ? 0 : max).toDouble(),
              max: max <= 0 ? 1 : max,
              onChanged: (x) => _seek(Duration(milliseconds: x.round())),
            ),
          ),
          Row(children: [
            Text('${_fmt(_pos)} / ${_fmt(_dur)}', style: vText(12, 16, color: v.textMuted)),
            const Spacer(),
            IconButton(tooltip: 'Back 10s', onPressed: () => _seek(_pos - const Duration(seconds: 10)), icon: const Icon(Icons.replay_10_rounded)),
            SizedBox(
              width: 44,
              height: 44,
              child: IconButton.filled(
                style: IconButton.styleFrom(backgroundColor: v.primary, foregroundColor: Colors.white),
                onPressed: () => _playing ? _player.pause() : _player.resume(),
                icon: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
              ),
            ),
            IconButton(tooltip: 'Forward 10s', onPressed: () => _seek(_pos + const Duration(seconds: 10)), icon: const Icon(Icons.forward_10_rounded)),
            const Spacer(),
            PopupMenuButton<double>(
              tooltip: 'Playback speed',
              initialValue: _speed,
              onSelected: (s) {
                setState(() => _speed = s);
                _player.setPlaybackRate(s);
              },
              itemBuilder: (_) => [for (final s in const [0.5, 0.8, 1.0, 1.2, 1.5, 1.8, 2.0]) PopupMenuItem(value: s, child: Text('${s}x'))],
              child: Padding(padding: const EdgeInsets.all(8), child: Text('${_speed}x', style: vText(13, 18, color: v.textStrong))),
            ),
            IconButton(
              tooltip: 'Download',
              onPressed: () => launchUrl(Uri.parse(_url), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.download_rounded),
            ),
          ]),
        ]),
      ),
    ]);
  }
}
