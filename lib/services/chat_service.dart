import 'package:uuid/uuid.dart';
import 'package:vault_the_spire/db/chat_dao.dart';
import 'package:vault_the_spire/models/chat_message.dart';

class ChatService {
  ChatService._();
  static final ChatService instance = ChatService._();

  final _uuid = const Uuid();

  Future<List<ChatMessage>> messagesFor(
    String serverId,
    String channelId,
  ) async {
    return await ChatDao.instance.getMessagesFor(serverId, channelId);
  }

  Future<void> sendMessage(
    String serverId,
    String channelId,
    String author,
    String text,
  ) async {
    final msg = ChatMessage(
      id: _uuid.v4(),
      serverId: serverId,
      channelId: channelId,
      author: author,
      text: text,
      timestamp: DateTime.now(),
    );
    await ChatDao.instance.insertChatMessage(msg);
  }
}
