import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verlium/api/models.dart';
import 'package:verlium/theme.dart';
import 'package:verlium/widgets/markdown.dart';

void main() {
  test('models parse server JSON', () {
    final s = Source.fromJson({
      'id': 'a',
      'notebook_id': 'n',
      'kind': 'pdf',
      'title': 'Doc',
      'status': 'processing',
      'selected': 1,
      'key_topics': ['x'],
    });
    expect(s.busy, isTrue);
    expect(s.selected, isTrue);
    expect(s.keyTopics, ['x']);
  });

  testWidgets('answers render citation chips', (tester) async {
    final cite = Citation.fromJson({
      'n': 1,
      'chunk_id': 'c',
      'source_id': 's',
      'source_title': 'Doc',
      'quote': 'quoted text',
      'char_start': 0,
      'char_end': 10,
    });
    Citation? tapped;
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
        body: VMarkdown(data: 'Chlorophyll is **green** [1].', citations: [cite], onCitation: (c) => tapped = c),
      ),
    ));
    expect(find.byType(CitationChip), findsOneWidget);
    await tester.tap(find.byType(CitationChip));
    expect(tapped?.sourceId, 's');
  });
}
