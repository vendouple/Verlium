import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:url_launcher/url_launcher.dart';

import '../api/models.dart';
import '../theme.dart';

/// Markdown with inline citation chips: "[3]" in the text becomes a 22×22 circle (UI-SPEC §3.4).
class VMarkdown extends StatelessWidget {
  final String data;
  final List<Citation> citations;
  final void Function(Citation c)? onCitation;
  final double fontSize, lineHeight;
  const VMarkdown({
    super.key,
    required this.data,
    this.citations = const [],
    this.onCitation,
    this.fontSize = 17,
    this.lineHeight = 24,
  });

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final body = vText(fontSize, lineHeight, color: v.text);
    final byN = {for (final c in citations) c.n: c};
    return MarkdownBody(
      data: data,
      selectable: false,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      inlineSyntaxes: [_MathSyntax(), _CiteSyntax()],
      builders: {'cite': _CiteBuilder(byN, onCitation), 'math': _MathBuilder(fontSize, v.textStrong)},
      onTapLink: (text, href, title) {
        if (href != null) launchUrl(Uri.parse(href));
      },
      styleSheet: MarkdownStyleSheet(
        p: body,
        strong: TextStyle(fontWeight: FontWeight.w600, color: v.textStrong),
        listBullet: body,
        h1: vText(fontSize + 7, lineHeight + 8, color: v.textTitle),
        h2: vText(fontSize + 4, lineHeight + 4, color: v.textTitle),
        h3: vText(fontSize + 1, lineHeight, weight: FontWeight.w600, color: v.textTitle),
        a: TextStyle(color: v.link),
        code: TextStyle(fontFamily: 'Consolas', fontSize: fontSize - 2, backgroundColor: v.tonal),
        codeblockDecoration: BoxDecoration(color: v.tonal, borderRadius: BorderRadius.circular(12)),
        blockquoteDecoration: BoxDecoration(border: Border(left: BorderSide(color: v.divider, width: 3))),
        tableBorder: TableBorder.all(color: v.divider),
        pPadding: const EdgeInsets.only(bottom: 8),
      ),
    );
  }
}

/// Inline LaTeX: $x^2$ or \(x^2\). "$5 and $10" stays text: no space just inside the dollars, no digit after.
class _MathSyntax extends md.InlineSyntax {
  _MathSyntax() : super(r'\$(?=[^\s$])((?:\\\$|[^$\n])+?)(?<=[^\s\\])\$(?!\d)|\\\((.+?)\\\)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('math', (match[1] ?? match[2])!));
    return true;
  }
}

class _MathBuilder extends MarkdownElementBuilder {
  final double fontSize;
  final Color color;
  _MathBuilder(this.fontSize, this.color);

  @override
  bool isBlockElement() => false;

  @override
  Widget? visitElementAfterWithContext(
      BuildContext context, md.Element element, TextStyle? preferredStyle, TextStyle? parentStyle) {
    final tex = element.textContent;
    return Math.tex(
      tex,
      mathStyle: MathStyle.text,
      textStyle: TextStyle(fontSize: fontSize, color: color),
      onErrorFallback: (_) => Text('\$$tex\$', style: TextStyle(fontSize: fontSize, color: color)),
    );
  }
}

class _CiteSyntax extends md.InlineSyntax {
  _CiteSyntax() : super(r'\[(\d{1,3})\](?!\()');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(md.Element.text('cite', match[1]!));
    return true;
  }
}

class _CiteBuilder extends MarkdownElementBuilder {
  final Map<int, Citation> byN;
  final void Function(Citation c)? onTap;
  _CiteBuilder(this.byN, this.onTap);

  @override
  bool isBlockElement() => false;

  @override
  Widget? visitElementAfterWithContext(
      BuildContext context, md.Element element, TextStyle? preferredStyle, TextStyle? parentStyle) {
    final n = int.parse(element.textContent);
    final c = byN[n];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: CitationChip(n: n, citation: c, onTap: c == null || onTap == null ? null : () => onTap!(c)),
    );
  }
}

class CitationChip extends StatelessWidget {
  final int n;
  final Citation? citation;
  final VoidCallback? onTap;
  const CitationChip({super.key, required this.n, this.citation, this.onTap});

  @override
  Widget build(BuildContext context) {
    final v = context.v;
    final chip = Material(
      color: v.citationBg,
      shape: CircleBorder(side: BorderSide(color: v.divider)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 22,
          height: 22,
          child: Center(
            child: Text('$n', style: vText(11, 16, weight: FontWeight.w500, color: v.citationText)),
          ),
        ),
      ),
    );
    if (citation == null) return chip;
    return Tooltip(
      richMessage: TextSpan(children: [
        TextSpan(text: '${citation!.sourceTitle}\n', style: const TextStyle(fontWeight: FontWeight.w600)),
        TextSpan(text: citation!.quote.length > 400 ? '${citation!.quote.substring(0, 400)}…' : citation!.quote),
      ]),
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: v.panel,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Color(0x47000000), blurRadius: 20)],
      ),
      textStyle: vText(13, 20, color: v.text),
      waitDuration: const Duration(milliseconds: 250),
      child: chip,
    );
  }
}
