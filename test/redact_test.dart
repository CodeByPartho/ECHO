import 'package:flutter_test/flutter_test.dart';
import 'package:echo/core/redact.dart';

void main() {
  group('redactSecrets', () {
    test('masks Gemini key in a ClientException-style URI', () {
      const input = 'ClientException: Failed host lookup, uri=https://'
          'generativelanguage.googleapis.com/v1beta/models?key=AIzaSyA1234567890abcdefghijk';
      final out = redactSecrets(input);
      expect(out, isNot(contains('AIzaSyA1234567890abcdefghijk')));
      expect(out, contains('?key=[REDACTED]'));
    });

    test('masks bearer tokens and header keys', () {
      final out = redactSecrets(
          'Authorization: Bearer abc.DEF-123_xyz x-api-key: secret123 '
          '{"x-goog-api-key": "AIzaSomething"}');
      expect(out, isNot(contains('abc.DEF-123_xyz')));
      expect(out, isNot(contains('secret123')));
      expect(out, isNot(contains('AIzaSomething')));
    });

    test('masks bare provider keys', () {
      final out = redactSecrets(
          'keys sk-or-v1-0123456789abcdef nvapi-ABCDEFGHIJ12 '
          'aichat_0123456789abcdef0123');
      expect(out, isNot(contains('0123456789abcdef')));
      expect(out, isNot(contains('ABCDEFGHIJ12')));
    });

    test('leaves ordinary text untouched', () {
      const input = 'Model failed to load: out of memory (task=sk)';
      expect(redactSecrets(input), input);
    });
  });
}
