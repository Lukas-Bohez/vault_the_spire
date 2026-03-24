import 'dart:async';

import 'package:uuid/uuid.dart';
import 'package:vault_the_spire/db/chat_dao.dart';
import 'package:vault_the_spire/models/chat_message.dart';
import 'package:vault_the_spire/vault_swarm/vault_swarm.dart';

class ChatService {
  ChatService._() {
    _listenForSwarmMessages();
  }
  static final ChatService instance = ChatService._();

  final _uuid = const Uuid();
  StreamSubscription<Map<String, dynamic>>? _swarmSubscription;

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

  static String dmSwarmTopic(String userA, String userB) {
    final sorted = [userA.trim(), userB.trim()]..sort();
    return 'dm:${sorted[0]}_${sorted[1]}';
  }

  Future<void> _listenForSwarmMessages() async {
    _swarmSubscription ??= VaultSwarm.instance.messageStream.listen((
      event,
    ) async {
      final type = event['type'] as String?;
      final topic = event['topic'] as String?;
      final payload = event['payload'] as Map<String, dynamic>?;
      if (type == 'typing' && payload != null && topic != null) {
        final userId = payload['userId'] as String?;
        final isTyping = payload['isTyping'] as bool?;
        final ts = payload['timestamp'] as int?;
        if (userId != null && isTyping != null && ts != null) {
          if (isTyping) {
            _typingStatus[userId] = DateTime.fromMillisecondsSinceEpoch(ts);
          } else {
            _typingStatus.remove(userId);
          }
        }
      } else if (type == 'chat' && payload != null && topic != null) {
        final messageMap = payload['message'] as Map<String, dynamic>?;
        if (messageMap != null) {
          try {
            final message = ChatMessage.fromMap(messageMap);
            await ChatDao.instance.insertChatMessage(message);
          } catch (_) {
            // ignore malformed message event
          }
        }
      }
    });
  }

  void broadcastTypingStatus(
    String channelOrDmTopic,
    String userId,
    bool isTyping,
  ) {
    if (isTyping) {
      _typingStatus[userId] = DateTime.now();
    } else {
      _typingStatus.remove(userId);
    }

    VaultSwarm.instance.broadcastMessage(channelOrDmTopic, {
      'type': 'typing',
      'userId': userId,
      'isTyping': isTyping,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<ChatMessage>> directMessagesBetween(
    String userA,
    String userB,
  ) async {
    final topic = dmSwarmTopic(userA, userB);
    final channel = dmChannelId(userA, userB);
    await VaultSwarm.instance.joinSwarm(topic);
    _listenForSwarmMessages();
    return await ChatDao.instance.getMessagesFor(topic, channel);
  }

  Future<void> sendDirectMessage(
    String from,
    String to,
    String text, {
    String? replyToMessageId,
  }) async {
    final topic = dmSwarmTopic(from, to);
    final channel = dmChannelId(from, to);

    await VaultSwarm.instance.joinSwarm(topic);
    _listenForSwarmMessages();

    final message = ChatMessage(
      id: _uuid.v4(),
      serverId: topic,
      channelId: channel,
      author: from,
      text: text,
      timestamp: DateTime.now(),
      replyToMessageId: replyToMessageId,
      reactions: {},
    );

    await ChatDao.instance.insertChatMessage(message);

    // Broadcast into the swarm for peers to sync.
    await VaultSwarm.instance.broadcastMessage(topic, {
      'type': 'chat',
      'message': message.toMap(),
    });
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
