class AiChatEntry {
  final String id;
  final String role;
  final String content;
  final DateTime createdAt;
  final bool isAuto;
  final bool isStreaming;

  const AiChatEntry({
    required this.id,
    required this.role,
    required this.content,
    required this.createdAt,
    this.isAuto = false,
    this.isStreaming = false,
  });

  AiChatEntry copyWith({
    String? content,
    bool? isStreaming,
  }) {
    return AiChatEntry(
      id: id,
      role: role,
      content: content ?? this.content,
      createdAt: createdAt,
      isAuto: isAuto,
      isStreaming: isStreaming ?? this.isStreaming,
    );
  }
}
