import '../core/constants.dart';
import '../models/persona.dart';

/// Chat template families the app can render manually when the native
/// `generateChat()` path is unavailable.
enum ChatTemplate { chatml, llama3, gemma, phi }

/// The system prompt plus the message history for a local generation. The
/// engine appends the live user message itself, exactly as before.
class LocalPrompt {
  final String systemPrompt;
  final List<Map<String, String>> history;

  const LocalPrompt({required this.systemPrompt, required this.history});
}

/// Single place where persona prompts and few-shot examples are turned into
/// request payloads. Used by both [InferenceService] and [CloudService] so a
/// persona behaves the same on-device and in the cloud.
class PromptComposer {
  const PromptComposer();

  /// Resolves the system prompt. A non-empty persona prompt wins, then the
  /// caller's prompt (the existing Settings prompt), then the app default.
  String resolveSystemPrompt({
    Persona? persona,
    String? baseSystemPrompt,
  }) {
    final personaPrompt = persona?.systemPrompt.trim() ?? '';
    if (personaPrompt.isNotEmpty) return personaPrompt;

    final base = baseSystemPrompt?.trim() ?? '';
    if (base.isNotEmpty) return base;

    return AppConstants.systemPrompt;
  }

  /// Local path: system turn + few-shot pairs + prior turns. The trailing
  /// user message is removed when it duplicates [userMessage] because
  /// [InferenceService] passes the live prompt separately.
  LocalPrompt composeForLocal({
    Persona? persona,
    String? baseSystemPrompt,
    List<Map<String, String>> history = const [],
    String? userMessage,
  }) {
    final systemPrompt = resolveSystemPrompt(
      persona: persona,
      baseSystemPrompt: baseSystemPrompt,
    );

    final turns = _sanitize(history);
    final text = userMessage?.trim() ?? '';
    if (text.isNotEmpty &&
        turns.isNotEmpty &&
        turns.last['role'] == 'user' &&
        turns.last['content'] == userMessage) {
      turns.removeLast();
    }

    return LocalPrompt(
      systemPrompt: systemPrompt,
      history: [..._fewShotMessages(persona), ...turns],
    );
  }

  /// Cloud path: the existing message list already ends with the live user
  /// message. Without a persona it is returned untouched, preserving old
  /// conversations byte for byte. With a persona, the system entry is
  /// replaced and few-shot pairs are inserted directly after it.
  List<Map<String, String>> applyToCloud({
    Persona? persona,
    required List<Map<String, String>> messages,
    String? baseSystemPrompt,
  }) {
    if (persona == null) return List<Map<String, String>>.from(messages);

    final sanitized = _sanitize(messages);
    final existingSystem = messages
        .where((m) => m['role'] == 'system')
        .map((m) => m['content'] ?? '')
        .firstWhere((c) => c.trim().isNotEmpty, orElse: () => '');

    final systemPrompt = resolveSystemPrompt(
      persona: persona,
      baseSystemPrompt: baseSystemPrompt ?? existingSystem,
    );

    return [
      {'role': 'system', 'content': systemPrompt},
      ..._fewShotMessages(persona),
      ...sanitized,
    ];
  }

  /// Renders a flat prompt for the legacy `generate()` fallback. The system
  /// turn is inserted using the template's own conventions.
  String renderLocal({
    required ChatTemplate template,
    required String systemPrompt,
    required List<Map<String, String>> history,
    required String userMessage,
  }) {
    final turns = _sanitize(history);
    return switch (template) {
      ChatTemplate.chatml => _renderChatMl(systemPrompt, turns, userMessage),
      ChatTemplate.llama3 => _renderLlama3(systemPrompt, turns, userMessage),
      ChatTemplate.gemma => _renderGemma(systemPrompt, turns, userMessage),
      ChatTemplate.phi => _renderPhi(systemPrompt, turns, userMessage),
    };
  }

  /// Template detection shared by the fallback renderer and tests.
  ChatTemplate detectTemplate(String modelName) {
    final name = modelName.toLowerCase();
    if (name.contains('gemma')) return ChatTemplate.gemma;
    if (name.contains('llama-3') ||
        name.contains('llama3') ||
        name.contains('llama_3') ||
        name.contains('llama-4') ||
        name.contains('llama4')) {
      return ChatTemplate.llama3;
    }
    if (name.contains('phi')) return ChatTemplate.phi;
    return ChatTemplate.chatml;
  }

  // ── Internals ────────────────────────────────────────────────────────

  List<Map<String, String>> _fewShotMessages(Persona? persona) {
    final out = <Map<String, String>>[];
    if (persona == null) return out;
    for (final example in persona.fewShotExamples) {
      if (example.user.trim().isNotEmpty) {
        out.add({'role': 'user', 'content': example.user.trim()});
      }
      if (example.assistant.trim().isNotEmpty) {
        out.add({'role': 'assistant', 'content': example.assistant.trim()});
      }
    }
    return out;
  }

  List<Map<String, String>> _sanitize(List<Map<String, String>> messages) {
    final out = <Map<String, String>>[];
    for (final message in messages) {
      final role = message['role'];
      if (role != 'user' && role != 'assistant') continue;
      out.add({'role': role!, 'content': message['content'] ?? ''});
    }
    return out;
  }

  List<Map<String, String>> _recent(
      List<Map<String, String>> turns, int maxMessages) {
    if (maxMessages <= 0 || turns.length <= maxMessages) return turns;
    return turns.sublist(turns.length - maxMessages);
  }

  String _truncate(String content) =>
      content.length > 300 ? '${content.substring(0, 300)}...' : content;

  String _renderChatMl(String system, List<Map<String, String>> turns,
      String userMessage) {
    final buf = StringBuffer();
    if (system.trim().isNotEmpty) {
      buf.write('<|im_start|>system\n${system.trim()}<|im_end|>\n');
    }
    for (final turn in _recent(turns, 8)) {
      buf.write(
          '<|im_start|>${turn['role']}\n${_truncate(turn['content'] ?? '')}<|im_end|>\n');
    }
    buf.write('<|im_start|>user\n$userMessage<|im_end|>\n'
        '<|im_start|>assistant\n');
    return buf.toString();
  }

  String _renderLlama3(String system, List<Map<String, String>> turns,
      String userMessage) {
    final buf = StringBuffer('<|begin_of_text|>');
    if (system.trim().isNotEmpty) {
      buf.write('<|start_header_id|>system<|end_header_id|>\n\n'
          '${system.trim()}<|eot_id|>');
    }
    for (final turn in _recent(turns, 4)) {
      buf.write('<|start_header_id|>${turn['role']}<|end_header_id|>\n\n'
          '${_truncate(turn['content'] ?? '')}<|eot_id|>');
    }
    buf.write('<|start_header_id|>user<|end_header_id|>\n\n'
        '$userMessage<|eot_id|>'
        '<|start_header_id|>assistant<|end_header_id|>\n\n');
    return buf.toString();
  }

  String _renderGemma(String system, List<Map<String, String>> turns,
      String userMessage) {
    final buf = StringBuffer();
    // Gemma has no system role; the prompt is carried by a leading user turn
    // that the model acknowledges before the real conversation.
    if (system.trim().isNotEmpty) {
      buf.write('<start_of_turn>user\n${system.trim()}<end_of_turn>\n'
          '<start_of_turn>model\nUnderstood.<end_of_turn>\n');
    }
    for (final turn in _recent(turns, 4)) {
      final role = turn['role'] == 'assistant' ? 'model' : 'user';
      buf.write('<start_of_turn>$role\n'
          '${_truncate(turn['content'] ?? '')}<end_of_turn>\n');
    }
    buf.write('<start_of_turn>user\n$userMessage<end_of_turn>\n'
        '<start_of_turn>model\n');
    return buf.toString();
  }

  String _renderPhi(String system, List<Map<String, String>> turns,
      String userMessage) {
    final buf = StringBuffer();
    if (system.trim().isNotEmpty) {
      buf.write('<|system|>\n${system.trim()}<|end|>\n');
    }
    for (final turn in _recent(turns, 8)) {
      buf.write('<|${turn['role']}|>\n'
          '${_truncate(turn['content'] ?? '')}<|end|>\n');
    }
    buf.write('<|user|>\n$userMessage<|end|>\n<|assistant|>\n');
    return buf.toString();
  }
}
