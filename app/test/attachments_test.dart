import 'package:flutter_test/flutter_test.dart';
import 'package:verlium/api/models.dart';
import 'package:verlium/state/notebook_store.dart';

void main() {
  test('attachment kinds by extension', () {
    expect(attachmentKind('photo.JPG'), 'image');
    expect(attachmentKind('clip.mov'), 'video');
    expect(attachmentKind('notes.pdf'), isNull);
  });

  test('messages parse attachments', () {
    final m = ChatMessage.fromJson({
      'id': '1', 'role': 'user', 'content': '',
      'attachments': [{'id': 'a', 'kind': 'video', 'mime': 'video/mp4', 'name': 'c.mp4', 'width': 640, 'height': 360, 'duration_s': 6}],
    });
    expect(m.attachments.single.isVideo, isTrue);
    expect(m.attachments.single.aspect, closeTo(16 / 9, 1e-9));
  });
}
