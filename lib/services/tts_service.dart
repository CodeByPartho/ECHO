import 'package:flutter_tts/flutter_tts.dart';

/// Read-aloud (text-to-speech) for ECHO answers.
///
/// Speech is produced by the Android system TTS engine on the device. No
/// audio is recorded and nothing is sent anywhere; the text never leaves
/// the phone. [stripForSpeech] is pure Dart so it can be unit tested
/// without a platform channel.
class TtsService {
  final FlutterTts _tts;
  bool _speaking = false;

  /// Called when the engine finishes speaking or is stopped.
  void Function()? onDone;

  TtsService({FlutterTts? tts}) : _tts = tts ?? FlutterTts() {
    _tts.setCompletionHandler(() {
      _speaking = false;
      onDone?.call();
    });
    _tts.setCancelHandler(() {
      _speaking = false;
      onDone?.call();
    });
    _tts.setErrorHandler((_) {
      _speaking = false;
      onDone?.call();
    });
  }

  bool get isSpeaking => _speaking;

  /// Speaks [text] after stripping markdown and other markup. Returns
  /// false when the text has nothing speakable in it.
  Future<bool> speak(String text) async {
    final clean = stripForSpeech(text);
    if (clean.isEmpty) return false;
    await _tts.stop();
    _speaking = true;
    final result = await _tts.speak(clean);
    // The platform channel reports 1 on success; anything else means the
    // engine refused the request, so do not leave the UI in a speaking state.
    if (result != 1) {
      _speaking = false;
      onDone?.call();
      return false;
    }
    return true;
  }

  Future<void> stop() async {
    await _tts.stop();
    _speaking = false;
  }

  /// Turns rendered answer text into plain speech text: drops thought
  /// blocks, code fences, images, links and formatting marks, and collapses
  /// whitespace. Assistant "thinking" text is never read aloud.
  static String stripForSpeech(String text) {
    var out = text;
    // Thought blocks (possibly unclosed while streaming).
    out = out.replaceAll(RegExp(r'<think>.*?(</think>|$)', dotAll: true), ' ');
    // Fenced code blocks become a short spoken note.
    out = out.replaceAll(
        RegExp(r'```[a-zA-Z]*\n?.*?```', dotAll: true), ' code block. ');
    // Inline code keeps its words, loses the backticks.
    out = out.replaceAll('`', '');
    // Images: drop entirely.
    out = out.replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), ' ');
    // Links keep their label.
    out = out.replaceAllMapped(
        RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m.group(1) ?? '');
    // Bare URLs are not speakable.
    out = out.replaceAll(RegExp(r'https?://\S+'), ' ');
    // Headings, bold, italics, strikethrough, blockquotes, list markers.
    // (Dart's replaceAll takes the replacement literally, so group
    // captures need replaceAllMapped, otherwise "$1" would be spoken.)
    out = out.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
    out = out.replaceAllMapped(
        RegExp(r'\*\*([^*]+)\*\*'), (m) => m.group(1) ?? '');
    out = out.replaceAllMapped(
        RegExp(r'__([^_]+)__'), (m) => m.group(1) ?? '');
    out = out.replaceAllMapped(
        RegExp(r'\*([^*]+)\*'), (m) => m.group(1) ?? '');
    out = out.replaceAllMapped(
        RegExp(r'_([^_]+)_'), (m) => m.group(1) ?? '');
    out = out.replaceAllMapped(
        RegExp(r'~~([^~]+)~~'), (m) => m.group(1) ?? '');
    out = out.replaceAll(RegExp(r'^>\s?', multiLine: true), '');
    out = out.replaceAll(RegExp(r'^\s*[-*+]\s+', multiLine: true), '');
    out = out.replaceAll(RegExp(r'^\s*\d+\.\s+', multiLine: true), '');
    // Model control tokens that sometimes leak into output.
    out = out.replaceAll('<|endoftext|>', ' ');
    out = out.replaceAll('<|im_end|>', ' ');
    out = out.replaceAll('<|end|>', ' ');
    // Any remaining HTML-ish tags.
    out = out.replaceAll(RegExp(r'<[^>]+>'), ' ');
    // Collapse whitespace and trim.
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    return out;
  }
}
