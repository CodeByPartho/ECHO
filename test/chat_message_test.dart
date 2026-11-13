import 'package:flutter_test/flutter_test.dart';
import 'package:echo/models/chat_message.dart';

ChatMessage msg({String content = 'hello', String? fileName}) => ChatMessage(
      id: 'm1',
      chatId: 's1',
      role: 'user',
      content: content,
      fileName: fileName,
    );

void main() {
  group('visibleText', () {
    test('plain message returns its content', () {
      expect(msg(content: 'Hello there').visibleText, 'Hello there');
    });

    test('message with an attachment returns only the typed text', () {
      expect(
        msg(
          content: 'Summarise this\n\nAttached file: report.pdf\n...',
          fileName: 'report.pdf',
        ).visibleText,
        'Summarise this',
      );
    });

    test('message that is only an attachment returns empty text', () {
      expect(
        msg(
          content: '\n\nAttached file: photo.png',
          fileName: 'photo.png',
        ).visibleText,
        '',
      );
    });
  });

  group('withVisibleText', () {
    test('replaces the text of a plain message', () {
      final edited = msg(content: 'old text').withVisibleText('new text');
      expect(edited.content, 'new text');
      expect(edited.id, 'm1');
    });

    test('keeps the attachment block when editing', () {
      final edited = msg(
        content: 'Old question\n\nAttached file: report.pdf\n...',
        fileName: 'report.pdf',
      ).withVisibleText('New question');
      expect(
        edited.content,
        'New question\n\nAttached file: report.pdf\n...',
      );
      expect(edited.fileName, 'report.pdf');
    });
  });

  group('copyWith', () {
    test('changes only the given fields', () {
      final copy = msg(content: 'a').copyWith(content: 'b');
      expect(copy.content, 'b');
      expect(copy.id, 'm1');
      expect(copy.role, 'user');
    });
  });
}
