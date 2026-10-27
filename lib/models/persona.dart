/// A persona: a reusable system prompt with optional few-shot examples and
/// generation settings. Stored in the `personas` Hive box, imported/exported
/// as JSON (see `docs/persona_schema.json`).
class Persona {
  final String id;
  final String name;
  final List<String> aliases;
  final String? avatarPath;
  final String systemPrompt;
  final String? greeting;
  final List<FewShotExample> fewShotExamples;
  final double? temperature;
  final double? topP;
  final int? maxTokens;
  final List<String> stopSequences;
  final bool isActive;
  final Map<String, dynamic> metadata;

  const Persona({
    required this.id,
    required this.name,
    this.aliases = const [],
    this.avatarPath,
    this.systemPrompt = '',
    this.greeting,
    this.fewShotExamples = const [],
    this.temperature,
    this.topP,
    this.maxTokens,
    this.stopSequences = const [],
    this.isActive = false,
    this.metadata = const {},
  });

  static const String schemaVersion = '1.0';

  Persona copyWith({
    String? id,
    String? name,
    List<String>? aliases,
    String? avatarPath,
    bool clearAvatar = false,
    String? systemPrompt,
    String? greeting,
    bool clearGreeting = false,
    List<FewShotExample>? fewShotExamples,
    double? temperature,
    bool clearTemperature = false,
    double? topP,
    bool clearTopP = false,
    int? maxTokens,
    bool clearMaxTokens = false,
    List<String>? stopSequences,
    bool? isActive,
    Map<String, dynamic>? metadata,
  }) {
    return Persona(
      id: id ?? this.id,
      name: name ?? this.name,
      aliases: aliases ?? this.aliases,
      avatarPath: clearAvatar ? null : (avatarPath ?? this.avatarPath),
      systemPrompt: systemPrompt ?? this.systemPrompt,
      greeting: clearGreeting ? null : (greeting ?? this.greeting),
      fewShotExamples: fewShotExamples ?? this.fewShotExamples,
      temperature: clearTemperature ? null : (temperature ?? this.temperature),
      topP: clearTopP ? null : (topP ?? this.topP),
      maxTokens: clearMaxTokens ? null : (maxTokens ?? this.maxTokens),
      stopSequences: stopSequences ?? this.stopSequences,
      isActive: isActive ?? this.isActive,
      metadata: metadata ?? this.metadata,
    );
  }

  /// Canonical JSON for export / Hive storage. Extra keys (avatar, greeting,
  /// is_active) are allowed by the schema contract.
  Map<String, dynamic> toJson() {
    final settings = <String, dynamic>{};
    if (temperature != null) settings['temperature'] = temperature;
    if (topP != null) settings['top_p'] = topP;
    if (maxTokens != null) settings['max_tokens'] = maxTokens;
    if (stopSequences.isNotEmpty) settings['stop'] = stopSequences;

    return {
      'schema_version': schemaVersion,
      'persona_id': id,
      'name': name,
      'aliases': aliases,
      'system_prompt': systemPrompt,
      if (avatarPath != null && avatarPath!.isNotEmpty)
        'avatar_path': avatarPath,
      if (greeting != null && greeting!.isNotEmpty) 'greeting': greeting,
      'few_shot_examples':
          fewShotExamples.map((e) => e.toJson()).toList(growable: false),
      'generation_settings': settings,
      'metadata': metadata,
      'is_active': isActive,
    };
  }

  Map<String, dynamic> toMap() => toJson();

  /// Tolerant decoder: unknown keys are ignored, missing fields fall back to
  /// safe defaults, and malformed values are skipped rather than thrown.
  factory Persona.fromJson(Map<dynamic, dynamic> json) {
    final settings = json['generation_settings'];
    final settingsMap = settings is Map ? settings : const {};

    final rawExamples = json['few_shot_examples'];
    final examples = <FewShotExample>[];
    if (rawExamples is List) {
      for (final raw in rawExamples) {
        if (raw is! Map) continue;
        final example = FewShotExample.fromJson(raw);
        if (example.isEmpty) continue;
        examples.add(example);
      }
    }

    return Persona(
      id: _asString(json['persona_id'] ?? json['id']).trim(),
      name: _asString(json['name']).trim(),
      aliases: _asStringList(json['aliases']),
      avatarPath: _asOptionalString(json['avatar_path'] ?? json['avatarPath']),
      systemPrompt: _asString(json['system_prompt'] ?? json['systemPrompt']),
      greeting: _asOptionalString(json['greeting']),
      fewShotExamples: examples,
      temperature: _clampDouble(
          _asDouble(settingsMap['temperature'] ?? json['temperature']), 0, 2),
      topP: _clampDouble(
          _asDouble(settingsMap['top_p'] ?? json['top_p']), 0, 1),
      maxTokens: _clampInt(
          _asInt(settingsMap['max_tokens'] ?? json['max_tokens']), 1, 32768),
      stopSequences: _asStopSequences(settingsMap['stop'] ?? json['stop']),
      isActive: json['is_active'] == true,
      metadata: _asMap(json['metadata']),
    );
  }

  factory Persona.fromMap(Map<dynamic, dynamic> map) => Persona.fromJson(map);

  static String _asString(dynamic value, [String fallback = '']) {
    if (value is String) return value;
    if (value == null) return fallback;
    return value.toString();
  }

  static String? _asOptionalString(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static List<String> _asStringList(dynamic value) {
    if (value is String) {
      final single = value.trim();
      return single.isEmpty ? const [] : [single];
    }
    if (value is! List) return const [];
    return value
        .whereType<String>()
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  static List<String> _asStopSequences(dynamic value) {
    if (value is String) {
      return value.isEmpty ? const [] : [value];
    }
    if (value is! List) return const [];
    return value
        .whereType<String>()
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  static double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  static int? _asInt(dynamic value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static double? _clampDouble(double? value, double min, double max) {
    if (value == null || value.isNaN || value.isInfinite) return null;
    return value.clamp(min, max).toDouble();
  }

  static int? _clampInt(int? value, int min, int max) {
    if (value == null) return null;
    return value.clamp(min, max);
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is! Map) return const {};
    return value.map((key, val) => MapEntry(key.toString(), val));
  }
}

class FewShotExample {
  final String user;
  final String assistant;

  const FewShotExample({required this.user, required this.assistant});

  bool get isEmpty => user.trim().isEmpty && assistant.trim().isEmpty;

  Map<String, dynamic> toJson() => {'user': user, 'assistant': assistant};

  factory FewShotExample.fromJson(Map<dynamic, dynamic> json) {
    final user = json['user'];
    final assistant = json['assistant'];
    return FewShotExample(
      user: user is String ? user : (user == null ? '' : user.toString()),
      assistant: assistant is String
          ? assistant
          : (assistant == null ? '' : assistant.toString()),
    );
  }
}
