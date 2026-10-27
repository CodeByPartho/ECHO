import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../models/persona.dart';
import 'hive_service.dart';
import 'persona_codec.dart';

/// CRUD + import/export for personas.
///
/// Personas live in their own Hive box ([AppConstants.personasBox]); the
/// selected default for new chats is stored in the settings box under
/// [AppConstants.keyActivePersonaId]. Existing boxes are untouched.
class PersonaService extends GetxService {
  final HiveService _hive = Get.find<HiveService>();
  final _uuid = const Uuid();

  final codec = const PersonaCodec();

  final personas = <Persona>[].obs;
  final activePersonaId = ''.obs;

  PersonaService init() {
    _load();
    return this;
  }

  void _load() {
    final loaded = _hive.personasBox.values
        .whereType<Map>()
        .map((raw) => Persona.fromMap(raw))
        .where((p) => p.id.trim().isNotEmpty)
        .map((p) => p.withActive(p.id == _savedActiveId))
        .toList();
    loaded.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    personas.value = loaded;

    final active = _savedActiveId;
    activePersonaId.value =
        loaded.any((p) => p.id == active) ? active : '';
    if (activePersonaId.value != active) {
      _hive.setSetting(AppConstants.keyActivePersonaId, '');
    }
  }

  String get _savedActiveId =>
      _hive.getSetting<String>(AppConstants.keyActivePersonaId) ?? '';

  Persona? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final persona in personas) {
      if (persona.id == id) return persona;
    }
    return null;
  }

  Persona? get activePersona => byId(activePersonaId.value);

  /// Case-insensitive lookup by name or alias, used by imports and assistants
  /// that mention a persona by name.
  Persona? findByNameOrAlias(String value) {
    final needle = value.trim().toLowerCase();
    if (needle.isEmpty) return null;
    for (final persona in personas) {
      if (persona.name.toLowerCase() == needle ||
          persona.aliases.any((alias) => alias.toLowerCase() == needle)) {
        return persona;
      }
    }
    return null;
  }

  Future<Persona> save(Persona persona) async {
    var next = persona.id.trim().isEmpty
        ? persona.copyWith(id: _uuid.v4())
        : persona;
    if (next.name.trim().isEmpty) {
      next = next.copyWith(name: 'Untitled Persona');
    }
    next = next.withActive(next.id == activePersonaId.value);

    await _hive.personasBox.put(next.id, next.toMap());
    final index = personas.indexWhere((p) => p.id == next.id);
    if (index >= 0) {
      personas[index] = next;
    } else {
      personas.add(next);
    }
    personas.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return next;
  }

  Future<Persona> create({
    String name = 'New Persona',
    String systemPrompt = '',
  }) {
    return save(Persona(id: '', name: name, systemPrompt: systemPrompt));
  }

  Future<Persona?> duplicate(String id) async {
    final source = byId(id);
    if (source == null) return null;
    final copy = source.copyWith(
      id: _uuid.v4(),
      name: '${source.name} copy',
      isActive: false,
    );
    return save(copy);
  }

  Future<void> delete(String id) async {
    await _hive.personasBox.delete(id);
    personas.removeWhere((p) => p.id == id);
    if (activePersonaId.value == id) {
      await setActive(null);
    }
  }

  /// Sets the persona bound to new chats (`null`/empty selects "No persona").
  Future<void> setActive(String? id) async {
    final next = (id == null || id.isEmpty) ? '' : id;
    if (next.isNotEmpty && byId(next) == null) return;

    activePersonaId.value = next;
    await _hive.setSetting(AppConstants.keyActivePersonaId, next);

    final updated = personas
        .map((p) => p.withActive(p.id == next))
        .toList();
    personas.value = updated;
  }

  /// Imports personas from JSON. Existing ids are regenerated so an import
  /// can never overwrite an unrelated persona.
  Future<List<Persona>> importJson(String source) async {
    final decoded = codec.decodeAll(source);
    if (decoded.isEmpty) {
      throw const PersonaFormatException('No persona found in the JSON file.');
    }

    final imported = <Persona>[];
    for (final raw in decoded) {
      final id = raw.id.trim();
      final collides = id.isNotEmpty && byId(id) != null;
      final persona = raw.copyWith(
        id: (id.isEmpty || collides) ? _uuid.v4() : id,
        name: raw.name.trim().isEmpty ? 'Untitled Persona' : raw.name,
      );
      imported.add(await save(persona));
    }
    return imported;
  }

  String exportJson(Persona persona, {bool pretty = true}) =>
      codec.encode(persona, pretty: pretty);

  /// Copies a picked avatar into app documents so it survives cache cleanup.
  Future<String?> persistAvatar(String personaId, String sourcePath) async {
    if (kIsWeb || sourcePath.trim().isEmpty) return null;
    try {
      final source = File(sourcePath);
      if (!await source.exists()) return null;
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/personas');
      if (!await folder.exists()) await folder.create(recursive: true);
      final extension = sourcePath.contains('.')
          ? sourcePath.substring(sourcePath.lastIndexOf('.'))
          : '.png';
      final target = '${folder.path}/$personaId$extension';
      await source.copy(target);
      return target;
    } catch (_) {
      return null;
    }
  }
}

extension _ActiveFlag on Persona {
  Persona withActive(bool value) =>
      isActive == value ? this : copyWith(isActive: value);
}
