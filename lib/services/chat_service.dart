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

  static String dmChannelId(String userA, String userB) {
    final sorted = [userA.trim(), userB.trim()]..sort();
    return 'dm-${sorted[0]}-${sorted[1]}';
  }

  Future<List<ChatMessage>> directMessagesBetween(
    String userA,
    String userB,
  ) async {
    final channel = dmChannelId(userA, userB);
    return await ChatDao.instance.getMessagesFor('_dm', channel);
  }

  Future<void> sendDirectMessage(String from, String to, String text) async {
    final channel = dmChannelId(from, to);
    await sendMessage('_dm', channel, from, text);
  }

  bool messageMentions(String userId, String text) {
    final mentionToken = '@${userId.trim()}';
    return text
        .split(RegExp(r'\s+'))
        .any((part) => part.trim() == mentionToken);
  }
}
