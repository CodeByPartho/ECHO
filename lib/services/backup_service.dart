import 'dart:convert';

import '../models/chat_message.dart';

/// On-device backup and export helpers for ECHO chats.
///
/// Everything here is pure Dart: no Hive, no GetX, no platform channels, so
/// it is fully unit testable. The backup file is a plain JSON document the
/// user owns; nothing leaves the device except through the share sheet the
/// user explicitly opens.
class BackupService {
  static const String schemaVersion = '1.0';
  static const String appId = 'echo';

  /// Builds a backup document from raw Hive maps.
  ///
  /// [sessions] and [messages] are the maps exactly as stored in Hive;
  /// [personas] are the raw persona maps. Nothing is transformed, so a
  /// restore reproduces the same records.
  static String buildBackupJson({
    required List<Map<dynamic, dynamic>> sessions,
    required List<Map<dynamic, dynamic>> messages,
    required List<Map<dynamic, dynamic>> personas,
  }) {
    final doc = <String, dynamic>{
      'schema_version': schemaVersion,
      'app': appId,
      'exported_at': DateTime.now().toIso8601String(),
      'sessions': sessions
          .map((m) => Map<String, dynamic>.from(m))
          .toList(growable: false),
      'messages': messages
          .map((m) => Map<String, dynamic>.from(m))
          .toList(growable: false),
      'personas': personas
          .map((m) => Map<String, dynamic>.from(m))
          .toList(growable: false),
    };
    return const JsonEncoder.withIndent('  ').convert(doc);
  }

  /// Parses a backup document. Throws [FormatException] on anything that
  /// is not an ECHO backup of a supported schema version.
  static BackupData parseBackup(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Backup file is not a JSON object');
    }
    if (decoded['app'] != appId) {
      throw const FormatException('Not an ECHO backup file');
    }
    final version = decoded['schema_version'];
    if (version != schemaVersion) {
      throw FormatException(
          'Unsupported backup version: $version (expected $schemaVersion)');
    }
    List<Map<String, dynamic>> readList(String key) {
      final value = decoded[key];
      if (value == null) return const [];
      if (value is! List) {
        throw FormatException('Backup field "$key" is not a list');
      }
      return value
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
    }

    return BackupData(
      sessions: readList('sessions'),
      messages: readList('messages'),
      personas: readList('personas'),
    );
  }

  /// Suggested file name for a backup exported right now.
  static String backupFileName([DateTime? now]) {
    final t = now ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return 'echo-backup-${t.year}${two(t.month)}${two(t.day)}-'
        '${two(t.hour)}${two(t.minute)}.json';
  }

  /// Suggested file name for a single-chat export.
  static String chatExportFileName(String title, [DateTime? now]) {
    final t = now ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final base = slug.isEmpty ? 'chat' : slug;
    return 'echo-$base-${t.year}${two(t.month)}${two(t.day)}.md';
  }

  /// Renders one chat as Markdown, newest last. Attachments are noted by
  /// name; the attached text itself is part of the user message content.
  static String buildChatMarkdown({
    required String title,
    required List<ChatMessage> messages,
  }) {
    final out = StringBuffer();
    out.writeln('# $title');
    out.writeln();
    out.writeln('_Exported from ECHO on ${_formatDate(DateTime.now())}._');
    out.writeln();
    for (final m in messages) {
      final who = m.role == 'user' ? 'You' : 'ECHO';
      final when = _formatDateTime(m.timestamp);
      out.writeln('## $who — $when');
      out.writeln();
      var body = m.content;
      if (m.fileName != null) {
        body = body.split('\n\nAttached file:').first;
        out.writeln('> Attached file: ${m.fileName}');
        out.writeln();
      }
      out.writeln(body.trim());
      out.writeln();
    }
    return out.toString();
  }

  static String _formatDate(DateTime t) {
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}';
  }

  static String _formatDateTime(DateTime t) {
    return '${_formatDate(t)} '
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }
}

class BackupData {
  final List<Map<String, dynamic>> sessions;
  final List<Map<String, dynamic>> messages;
  final List<Map<String, dynamic>> personas;

  const BackupData({
    required this.sessions,
    required this.messages,
    required this.personas,
  });
}
