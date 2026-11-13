import 'package:flutter_test/flutter_test.dart';
import 'package:echo/models/chat_message.dart';
import 'package:echo/services/backup_service.dart';

void main() {
  group('buildBackupJson / parseBackup round trip', () {
    test('restores the same sessions, messages and personas', () {
      final sessions = [
        {'id': 's1', 'title': 'First chat', 'pinned': true},
      ];
      final messages = [
        {'id': 'm1', 'chatId': 's1', 'role': 'user', 'content': 'hello'},
        {'id': 'm2', 'chatId': 's1', 'role': 'assistant', 'content': 'hi'},
      ];
      final personas = [
        {'id': 'p1', 'name': 'Pirate'},
      ];

      final json = BackupService.buildBackupJson(
        sessions: sessions,
        messages: messages,
        personas: personas,
      );
      final parsed = BackupService.parseBackup(json);

      expect(parsed.sessions.length, 1);
      expect(parsed.sessions[0]['id'], 's1');
      expect(parsed.sessions[0]['title'], 'First chat');
      expect(parsed.sessions[0]['pinned'], isTrue);
      expect(parsed.messages.length, 2);
      expect(parsed.messages[1]['content'], 'hi');
      expect(parsed.personas.length, 1);
      expect(parsed.personas[0]['name'], 'Pirate');
    });

    test('empty backup round trips to empty lists', () {
      final json = BackupService.buildBackupJson(
        sessions: const [],
        messages: const [],
        personas: const [],
      );
      final parsed = BackupService.parseBackup(json);
      expect(parsed.sessions, isEmpty);
      expect(parsed.messages, isEmpty);
      expect(parsed.personas, isEmpty);
    });
  });

  group('parseBackup rejects bad files', () {
    test('rejects non-JSON', () {
      expect(() => BackupService.parseBackup('not json'),
          throwsFormatException);
    });

    test('rejects a JSON array', () {
      expect(() => BackupService.parseBackup('[1, 2]'),
          throwsFormatException);
    });

    test('rejects a backup from another app', () {
      expect(
        () => BackupService.parseBackup(
            '{"app": "other", "schema_version": "1.0"}'),
        throwsFormatException,
      );
    });

    test('rejects an unsupported schema version', () {
      expect(
        () => BackupService.parseBackup(
            '{"app": "echo", "schema_version": "2.0"}'),
        throwsFormatException,
      );
    });

    test('rejects a non-list sessions field', () {
      expect(
        () => BackupService.parseBackup(
            '{"app": "echo", "schema_version": "1.0", "sessions": {}}'),
        throwsFormatException,
      );
    });
  });

  group('file names', () {
    test('backup name is dated and ends in .json', () {
      final name = BackupService.backupFileName(DateTime(2026, 11, 14, 9, 5));
      expect(name, 'echo-backup-20261114-0905.json');
    });

    test('chat export name slugifies the title', () {
      final name = BackupService.chatExportFileName(
          'My First Chat!', DateTime(2026, 11, 14));
      expect(name, 'echo-my-first-chat-20261114.md');
    });

    test('chat export name falls back to "chat" for a blank title', () {
      final name = BackupService.chatExportFileName('!!!', DateTime(2026, 11, 14));
      expect(name, 'echo-chat-20261114.md');
    });
  });

  group('buildChatMarkdown', () {
    test('renders user and assistant turns with headers', () {
      final md = BackupService.buildChatMarkdown(
        title: 'Test chat',
        messages: [
          ChatMessage(
            id: 'm1',
            chatId: 's1',
            role: 'user',
            content: 'What is 2+2?',
            timestamp: DateTime(2026, 11, 14, 10, 0),
          ),
          ChatMessage(
            id: 'm2',
            chatId: 's1',
            role: 'assistant',
            content: 'It is 4.',
            timestamp: DateTime(2026, 11, 14, 10, 0),
          ),
        ],
      );
      expect(md, contains('# Test chat'));
      expect(md, contains('## You — 2026-11-14 10:00'));
      expect(md, contains('What is 2+2?'));
      expect(md, contains('## ECHO — 2026-11-14 10:00'));
      expect(md, contains('It is 4.'));
    });

    test('notes the attachment by name and keeps the visible text', () {
      final md = BackupService.buildChatMarkdown(
        title: 'Docs',
        messages: [
          ChatMessage(
            id: 'm1',
            chatId: 's1',
            role: 'user',
            content: 'Summarise this\n\nAttached file: report.pdf\n...',
            fileName: 'report.pdf',
            timestamp: DateTime(2026, 11, 14, 10, 0),
          ),
        ],
      );
      expect(md, contains('> Attached file: report.pdf'));
      expect(md, contains('Summarise this'));
      expect(md, isNot(contains('Attached file: report.pdf\n...')));
    });
  });
}
