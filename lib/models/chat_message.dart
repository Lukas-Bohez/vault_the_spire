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

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'server_id': serverId,
      'channel_id': channelId,
      'author': author,
      'text': text,
      'timestamp': timestamp.millisecondsSinceEpoch,
    };
  }

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as String,
      serverId: map['server_id'] as String,
      channelId: map['channel_id'] as String,
      author: map['author'] as String,
      text: map['text'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
    );
  }
}
