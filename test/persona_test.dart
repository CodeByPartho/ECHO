import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:echo/core/constants.dart';
import 'package:echo/models/chat_session.dart';
import 'package:echo/models/persona.dart';
import 'package:echo/services/hive_service.dart';
import 'package:echo/services/persona_codec.dart';
import 'package:echo/services/persona_service.dart';
import 'package:echo/services/prompt_composer.dart';

void main() {
  const codec = PersonaCodec();

  group('Persona & PersonaCodec', () {
    test('round-trips schema v1.0 JSON with all fields', () {
      const rawJson = '''
{
  "schema_version": "1.0",
  "persona_id": "sherlock-v1",
  "name": "Sherlock Holmes",
  "aliases": ["Sherlock", "Consulting Detective"],
  "system_prompt": "You are Sherlock Holmes of 221B Baker Street.",
  "greeting": "The game is afoot.",
  "avatar_path": "/tmp/sherlock.png",
  "few_shot_examples": [
    {
      "user": "How did you know?",
      "assistant": "Elementary observation of your mud-splattered boots."
    }
  ],
  "generation_settings": {
    "temperature": 0.4,
    "top_p": 0.85,
    "max_tokens": 1024,
    "stop": ["\\nUser:", "<|end|>"]
  },
  "metadata": {
    "source": "privatelm-test"
  }
}
''';

      final persona = codec.decode(rawJson);
      expect(Persona.schemaVersion, '1.0');
      expect(persona.id, 'sherlock-v1');
      expect(persona.name, 'Sherlock Holmes');
      expect(persona.aliases, ['Sherlock', 'Consulting Detective']);
      expect(persona.systemPrompt,
          'You are Sherlock Holmes of 221B Baker Street.');
      expect(persona.greeting, 'The game is afoot.');
      expect(persona.avatarPath, '/tmp/sherlock.png');
      expect(persona.fewShotExamples.length, 1);
      expect(persona.fewShotExamples.first.user, 'How did you know?');
      expect(persona.fewShotExamples.first.assistant,
          'Elementary observation of your mud-splattered boots.');
      expect(persona.temperature, 0.4);
      expect(persona.topP, 0.85);
      expect(persona.maxTokens, 1024);
      expect(persona.stopSequences, ['\nUser:', '<|end|>']);
      expect(persona.metadata['source'], 'privatelm-test');

      final encoded = codec.encode(persona);
      final roundTripped = codec.decode(encoded);
      expect(roundTripped.id, persona.id);
      expect(roundTripped.name, persona.name);
      expect(roundTripped.systemPrompt, persona.systemPrompt);
      expect(roundTripped.fewShotExamples.length, 1);
      expect(roundTripped.temperature, 0.4);
      expect(roundTripped.topP, 0.85);
      expect(roundTripped.maxTokens, 1024);
      expect(roundTripped.stopSequences, ['\nUser:', '<|end|>']);
    });

    test('clamps out-of-range generation settings and ignores unknown keys', () {
      final map = {
        'schema_version': '1.0',
        'persona_id': 'clamp-test',
        'name': 'Clamp Test',
        'system_prompt': 'Be concise.',
        'future_unknown_field': {'nested': true},
        'generation_settings': {
          'temperature': 9.5,
          'top_p': -0.5,
          'max_tokens': 999999,
          'stop': ['STOP1', '', 42],
        },
      };

      final p = Persona.fromJson(map);
      expect(p.temperature, 2.0);
      expect(p.topP, 0.0);
      expect(p.maxTokens, 32768);
      expect(p.stopSequences, ['STOP1']);
    });

    test('decodeAll accepts both single object and list of personas', () {
      final listJson = jsonEncode([
        {
          'schema_version': '1.0',
          'persona_id': 'p1',
          'name': 'One',
          'system_prompt': 'Prompt 1',
        },
        {
          'schema_version': '1.0',
          'persona_id': 'p2',
          'name': 'Two',
          'system_prompt': 'Prompt 2',
        },
      ]);

      final decoded = codec.decodeAll(listJson);
      expect(decoded.map((p) => p.id).toList(), ['p1', 'p2']);
    });

    test('throws PersonaFormatException on missing required fields or bad JSON',
        () {
      expect(
        () => codec.decode('{"schema_version": "1.0"}'),
        throwsA(isA<PersonaFormatException>()),
      );
      expect(
        () => codec.decode('not json at all'),
        throwsA(isA<PersonaFormatException>()),
      );
    });
  });

  group('PromptComposer', () {
    const composer = PromptComposer();
    const samplePersona = Persona(
      id: 'pirate',
      name: 'Captain',
      systemPrompt: 'Speak like a 17th-century pirate captain.',
      fewShotExamples: [
        FewShotExample(user: 'Hello', assistant: 'Ahoy, matey!'),
      ],
    );

    test('resolveSystemPrompt respects persona > base > default precedence', () {
      expect(
        composer.resolveSystemPrompt(
          baseSystemPrompt: 'Global prompt',
          persona: samplePersona,
        ),
        'Speak like a 17th-century pirate captain.',
      );
      expect(
        composer.resolveSystemPrompt(
          baseSystemPrompt: 'Global prompt',
          persona: null,
        ),
        'Global prompt',
      );
      expect(
        composer.resolveSystemPrompt(
          baseSystemPrompt: '   ',
          persona: null,
        ),
        AppConstants.systemPrompt,
      );
    });

    test('applyToCloud preserves messages byte-for-byte when persona is null',
        () {
      final original = [
        {'role': 'system', 'content': 'Global system'},
        {'role': 'user', 'content': 'Hi there'},
      ];
      final result = composer.applyToCloud(messages: original, persona: null);
      expect(result, original);
    });

    test('applyToCloud injects persona system prompt and few-shot turns', () {
      final original = [
        {'role': 'system', 'content': 'Global system'},
        {'role': 'user', 'content': 'Where is the treasure?'},
      ];
      final result =
          composer.applyToCloud(messages: original, persona: samplePersona);
      expect(result.length, 4);
      expect(result[0], {
        'role': 'system',
        'content': 'Speak like a 17th-century pirate captain.',
      });
      expect(result[1], {'role': 'user', 'content': 'Hello'});
      expect(result[2], {'role': 'assistant', 'content': 'Ahoy, matey!'});
      expect(result[3], {'role': 'user', 'content': 'Where is the treasure?'});
    });

    test('composeForLocal injects few-shot and deduplicates trailing user turn',
        () {
      final composed = composer.composeForLocal(
        userMessage: 'What is our heading?',
        history: const [
          {'role': 'user', 'content': 'Set sail!'},
          {'role': 'assistant', 'content': 'Aye, anchors aweigh!'},
          {'role': 'user', 'content': 'What is our heading?'},
        ],
        baseSystemPrompt: 'Default',
        persona: samplePersona,
      );

      expect(composed.systemPrompt,
          'Speak like a 17th-century pirate captain.');
      expect(composed.history, [
        {'role': 'user', 'content': 'Hello'},
        {'role': 'assistant', 'content': 'Ahoy, matey!'},
        {'role': 'user', 'content': 'Set sail!'},
        {'role': 'assistant', 'content': 'Aye, anchors aweigh!'},
      ]);
    });

    test('detectTemplate and renderLocal format templates accurately', () {
      expect(
        composer.detectTemplate('Llama-3.2-3B-Instruct.gguf'),
        ChatTemplate.llama3,
      );
      expect(
        composer.detectTemplate('gemma-2-2b-it.gguf'),
        ChatTemplate.gemma,
      );
      expect(
        composer.detectTemplate('Phi-3.5-mini-instruct.gguf'),
        ChatTemplate.phi,
      );
      expect(
        composer.detectTemplate('Qwen2.5-7B-Instruct.gguf'),
        ChatTemplate.chatml,
      );

      final local = composer.composeForLocal(
        persona: samplePersona,
        baseSystemPrompt: 'Base',
        history: const [
          {'role': 'user', 'content': 'ExUser'},
          {'role': 'assistant', 'content': 'ExAssistant'},
        ],
        userMessage: 'Ping',
      );
      final chatml = composer.renderLocal(
        template: ChatTemplate.chatml,
        systemPrompt: local.systemPrompt,
        history: local.history,
        userMessage: 'Ping',
      );

      expect(
        chatml,
        '<|im_start|>system\nSpeak like a 17th-century pirate captain.<|im_end|>\n'
        '<|im_start|>user\nHello<|im_end|>\n'
        '<|im_start|>assistant\nAhoy, matey!<|im_end|>\n'
        '<|im_start|>user\nExUser<|im_end|>\n'
        '<|im_start|>assistant\nExAssistant<|im_end|>\n'
        '<|im_start|>user\nPing<|im_end|>\n'
        '<|im_start|>assistant\n',
      );
    });
  });

  group('PersonaService & ChatSession backward compatibility', () {
    late Directory dir;
    late HiveService hive;
    late PersonaService service;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('persona_service_test');
      Hive.init(dir.path);
      hive = await HiveService().init();
      Get.put(hive);
      service = PersonaService().init();
      Get.put(service);
    });

    tearDown(() async {
      Get.reset();
      await Hive.deleteFromDisk();
      await dir.delete(recursive: true);
    });

    test('saves, activates, imports with collision handling, and deletes',
        () async {
      const p = Persona(
        id: 'coder-1',
        name: 'Rustacean',
        systemPrompt: 'Write idiomatic Rust.',
      );
      await service.save(p);
      expect(service.personas.length, 1);
      expect(service.byId('coder-1')?.name, 'Rustacean');

      await service.setActive('coder-1');
      expect(service.activePersonaId.value, 'coder-1');
      expect(service.activePersona?.id, 'coder-1');
      expect(
        hive.getSetting<String>(AppConstants.keyActivePersonaId),
        'coder-1',
      );

      // Importing a persona with the same ID mints a fresh ID on collision
      final imported = await service.importJson(codec.encode(p));
      expect(imported.length, 1);
      expect(imported.first.id, isNot('coder-1'));
      expect(service.personas.length, 2);

      // Deleting the active persona falls back to "No persona"
      await service.delete('coder-1');
      expect(service.activePersonaId.value, isEmpty);
      expect(service.activePersona, isNull);
      expect(hive.getSetting<String>(AppConstants.keyActivePersonaId), '');
    });

    test('ChatSession serializes with and without personaId', () {
      final legacyMap = {
        'id': 's1',
        'title': 'Legacy Chat',
        'createdAt': '2026-01-01T00:00:00.000Z',
        'updatedAt': '2026-01-01T00:00:00.000Z',
        'modelUsed': 'qwen',
      };
      final legacy = ChatSession.fromMap(legacyMap);
      expect(legacy.personaId, isNull);

      final withPersona = legacy.copyWith(personaId: 'sherlock-v1');
      expect(withPersona.personaId, 'sherlock-v1');
      final serialized = withPersona.toMap();
      expect(serialized['personaId'], 'sherlock-v1');

      final cleared = withPersona.copyWith(clearPersonaId: true);
      expect(cleared.personaId, isNull);
    });
  });
}
