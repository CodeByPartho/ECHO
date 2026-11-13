class ChatSession {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? lastMessage;

  /// Persona bound to this conversation. Null means "No persona", which is
  /// how every session created before personas existed behaves.
  final String? personaId;

  /// Pinned chats sort to the top of the drawer. Defaults to false, so
  /// sessions saved before pinning existed behave exactly as before.
  final bool pinned;

  ChatSession({
    required this.id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.lastMessage,
    this.personaId,
    this.pinned = false,
  })  : title = title ?? 'New Chat',
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'lastMessage': lastMessage,
        if (personaId != null) 'personaId': personaId,
        'pinned': pinned,
      };

  factory ChatSession.fromMap(Map<dynamic, dynamic> map) => ChatSession(
        id: map['id'] ?? '',
        title: map['title'] ?? 'New Chat',
        createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(map['updatedAt'] ?? '') ?? DateTime.now(),
        lastMessage: map['lastMessage'],
        personaId: _personaId(map['personaId']),
        pinned: map['pinned'] == true,
      );

  static String? _personaId(dynamic value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  ChatSession copyWith({
    String? title,
    DateTime? updatedAt,
    String? lastMessage,
    String? personaId,
    bool? pinned,
    bool clearPersona = false,
    bool clearPersonaId = false,
  }) =>
      ChatSession(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
        lastMessage: lastMessage ?? this.lastMessage,
        personaId: (clearPersona || clearPersonaId)
            ? null
            : (personaId ?? this.personaId),
        pinned: pinned ?? this.pinned,
      );
}
