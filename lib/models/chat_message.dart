class ChatMessage {
  final String id;
  final String serverId;
  final String channelId;
  final String author;
  final String text;
  final DateTime timestamp;

  ChatMessage({
    required this.id,
    required this.serverId,
    required this.channelId,
    required this.author,
    required this.text,
    required this.timestamp,
  });
}
