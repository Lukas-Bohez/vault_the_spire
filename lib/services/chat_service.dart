import 'package:uuid/uuid.dart';
import 'package:vault_the_spire/models/chat_message.dart';

class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  final _uuid = const Uuid();
  final List<ChatMessage> _messages = [];

  List<ChatMessage> messagesFor(String serverId, String channelId) {
    return _messages
        .where((m) => m.serverId == serverId && m.channelId == channelId)
        .toList();
  }

  void sendMessage(
    String serverId,
    String channelId,
    String author,
    String text,
  ) {
    final msg = ChatMessage(
      id: _uuid.v4(),
      serverId: serverId,
      channelId: channelId,
      author: author,
      text: text,
      timestamp: DateTime.now(),
    );
    _messages.add(msg);
  }
}
