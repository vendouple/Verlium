import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:verlium/api/models.dart';
import 'package:verlium/state/notebook_store.dart';
import 'package:verlium/theme.dart';
import 'package:verlium/widgets/chat_panel.dart';

void main() {
  testWidgets('chat header icons are right-aligned', (tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = NotebookStore('nb')
      ..loading = false
      ..notebook = Notebook.fromJson({'id': 'nb', 'title': 'Test'});
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(body: ChatPanel(store: store)),
    ));
    final more = tester.getCenter(find.byIcon(Icons.more_vert));
    final incog = tester.getCenter(find.byIcon(Icons.visibility_off_outlined));
    final title = tester.getTopLeft(find.text('New chat'));
    expect(more.dx, greaterThan(950));
    expect(incog.dx, greaterThan(850));
    expect(title.dx, lessThan(40));
  });
}
