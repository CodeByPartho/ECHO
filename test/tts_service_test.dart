import 'package:flutter_test/flutter_test.dart';
import 'package:echo/services/tts_service.dart';

void main() {
  group('stripForSpeech', () {
    test('plain text passes through', () {
      expect(TtsService.stripForSpeech('Hello, world.'),
          'Hello, world.');
    });

    test('drops thought blocks, including an unclosed one', () {
      expect(
        TtsService.stripForSpeech(
            '<think>Let me think about this.</think>The answer is 4.'),
        'The answer is 4.',
      );
      expect(
        TtsService.stripForSpeech('<think>Still thinking...'),
        isEmpty,
        reason: 'An unclosed think block means the answer has not started '
            'yet, so there is nothing speakable.',
      );
    });

    test('replaces fenced code blocks with a short note', () {
      expect(
        TtsService.stripForSpeech(
            'Here is the code:\n```dart\nvoid main() {}\n```\nDone.'),
        'Here is the code: code block. Done.',
      );
    });

    test('keeps inline code words, drops the backticks', () {
      expect(TtsService.stripForSpeech('Use `print` to log.'),
          'Use print to log.');
    });

    test('drops images, keeps link labels, drops bare URLs', () {
      expect(
        TtsService.stripForSpeech(
            '![a cat](https://example.com/cat.png) See [the docs](https://example.com) or https://example.com/raw.'),
        // The bare URL takes its trailing period with it; for speech the
        // sentence end is not needed.
        'See the docs or',
      );
    });

    test('strips markdown marks, headings, quotes and list markers', () {
      expect(
        TtsService.stripForSpeech(
            '# Title\n\n**Bold** and *italic* text.\n> Quoted line\n- item one\n1. first step'),
        'Title Bold and italic text. Quoted line item one first step',
      );
    });

    test('drops model control tokens and stray tags', () {
      expect(
        TtsService.stripForSpeech(
            'Hello <|endoftext|> world <b>bold</b> <|im_end|>'),
        'Hello world bold',
      );
    });

    test('collapses whitespace and trims', () {
      expect(
        TtsService.stripForSpeech('  Hello\n\n\n   world   '),
        'Hello world',
      );
    });

    test('a message that is only markup becomes empty', () {
      expect(TtsService.stripForSpeech('```\ncode\n```'), 'code block.');
      expect(TtsService.stripForSpeech('![x](y.png)'), isEmpty);
    });
  });
}
