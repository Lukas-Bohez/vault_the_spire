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
    String text, {
    String? replyToMessageId,
  }) async {
    final msg = ChatMessage(
      id: _uuid.v4(),
      serverId: serverId,
      channelId: channelId,
      author: author,
      text: text,
      timestamp: DateTime.now(),
      replyToMessageId: replyToMessageId,
      reactions: {},
    );
    await ChatDao.instance.insertChatMessage(msg);
  }

  static String dmChannelId(String userA, String userB) {
    final sorted = [userA.trim(), userB.trim()]..sort();
    return 'dm-${sorted[0]}-${sorted[1]}';
  }

  final Map<String, DateTime> _typingStatus = {};

  void setTypingStatus(String userId, bool isTyping) {
    if (isTyping) {
      _typingStatus[userId] = DateTime.now();
    } else {
      _typingStatus.remove(userId);
    }
  }

  bool isUserTyping(String userId) {
    final last = _typingStatus[userId];
    if (last == null) return false;
    return DateTime.now().difference(last).inSeconds < 5;
  }

  Future<List<ChatMessage>> directMessagesBetween(
    String userA,
    String userB,
  ) async {
    final channel = dmChannelId(userA, userB);
    return await ChatDao.instance.getMessagesFor('_dm', channel);
  }

  Future<void> sendDirectMessage(
    String from,
    String to,
    String text, {
    String? replyToMessageId,
  }) async {
    final channel = dmChannelId(from, to);
    await sendMessage(
      '_dm',
      channel,
      from,
      text,
      replyToMessageId: replyToMessageId,
    );
  }

  Future<void> addReaction(String messageId, String emoji) async {
    final msg = await ChatDao.instance.getMessageById(messageId);
    if (msg == null) return;
    final newReactions = Map<String, int>.from(msg.reactions);
    newReactions[emoji] = (newReactions[emoji] ?? 0) + 1;

    final updated = ChatMessage(
      id: msg.id,
      serverId: msg.serverId,
      channelId: msg.channelId,
      author: msg.author,
      text: msg.text,
      timestamp: msg.timestamp,
      replyToMessageId: msg.replyToMessageId,
      editedAt: DateTime.now(),
      reactions: newReactions,
    );
    await ChatDao.instance.updateMessage(updated);
  }

  Future<void> updateMessageText(String messageId, String newText) async {
    final msg = await ChatDao.instance.getMessageById(messageId);
    if (msg == null) return;

    final updated = ChatMessage(
      id: msg.id,
      serverId: msg.serverId,
      channelId: msg.channelId,
      author: msg.author,
      text: newText,
      timestamp: msg.timestamp,
      replyToMessageId: msg.replyToMessageId,
      editedAt: DateTime.now(),
      reactions: msg.reactions,
    );
    await ChatDao.instance.updateMessage(updated);
  }

  Future<void> deleteMessage(String messageId) async {
    await ChatDao.instance.deleteMessage(messageId);
  }

  bool messageMentions(String userId, String text) {
    final mentionToken = '@${userId.trim()}';
    return text
        .split(RegExp(r'\s+'))
        .any((part) => part.trim() == mentionToken);
  }
}
