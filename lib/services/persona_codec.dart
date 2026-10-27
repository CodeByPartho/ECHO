import 'dart:convert';

import '../models/persona.dart';

/// Pure JSON encode/decode for personas. Kept separate from [PersonaService]
/// so import/export rules can be unit tested without Hive.
class PersonaCodec {
  const PersonaCodec();

  /// Decodes one persona object or a JSON array of persona objects.
  ///
  /// Unknown top-level keys are ignored. Malformed entries are skipped; the
  /// caller decides whether an empty result is an error.
  List<Persona> decodeAll(String source) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw PersonaFormatException('Not valid JSON: ${e.message}');
    }

    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map((raw) => Persona.fromJson(raw))
          .where((p) => p.name.isNotEmpty || p.systemPrompt.isNotEmpty)
          .toList(growable: false);
    }
    if (decoded is Map) {
      final persona = Persona.fromJson(decoded);
      if (persona.name.isEmpty && persona.systemPrompt.isEmpty) {
        return const [];
      }
      return [persona];
    }
    throw const PersonaFormatException(
        'Expected a JSON object (or array of objects) at the top level.');
  }

  Persona decode(String source) {
    final all = decodeAll(source);
    if (all.isEmpty) {
      throw const PersonaFormatException('No persona found in the JSON file.');
    }
    return all.first;
  }

  String encode(Persona persona, {bool pretty = true}) {
    const json = JsonEncoder.withIndent('  ');
    return pretty ? json.convert(persona.toJson()) : jsonEncode(persona.toJson());
  }
}

class PersonaFormatException implements Exception {
  final String message;
  const PersonaFormatException(this.message);

  @override
  String toString() => message;
}
