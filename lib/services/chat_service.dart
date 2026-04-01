import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:vault_the_spire/db/chat_dao.dart';
import 'package:vault_the_spire/db/conversation_dao.dart';
import 'package:vault_the_spire/db/dm_messages_dao.dart';
import 'package:vault_the_spire/db/users_dao.dart';
import 'package:vault_the_spire/models/chat_hub_entry.dart';
import 'package:vault_the_spire/models/chat_message.dart';
import 'package:vault_the_spire/services/server_service.dart';
import 'package:vault_the_spire/models/chat_user.dart';
import 'package:vault_the_spire/models/conversation.dart';
import 'package:vault_the_spire/models/dm_message.dart';
import 'package:vault_the_spire/vault_swarm/vault_swarm.dart';

class ChatService {
  ChatService._() {
    _listenForSwarmMessages();
  }

  static final ChatService instance = ChatService._();

  final _uuid = const Uuid();
  StreamSubscription<Map<String, dynamic>>? _swarmSubscription;

  final Map<String, DateTime> _typingStatus = {};
  final Map<String, UserStatus> _presence = {};

  Future<ChatUser> _ensureUserExists(String username) async {
    final safeName = username.trim();
    if (safeName.isEmpty) {
      throw ArgumentError('Username cannot be empty');
    }
    final existing = await UsersDao.instance.getUserByName(safeName);
    if (existing != null) return existing;

    final user = ChatUser(
      id: _uuid.v4(),
      username: safeName,
      status: UserStatus.offline,
      lastSeen: DateTime.now(),
    );
    await UsersDao.instance.insertUser(user);
    return user;
  }

  Future<ChatUser?> getUser(String username) async {
    return await UsersDao.instance.getUserByName(username.trim());
  }

  Future<void> setUserStatus(String username, UserStatus status) async {
    final user = await _ensureUserExists(username);
    final updated = user.copyWith(status: status, lastSeen: DateTime.now());
    await UsersDao.instance.insertUser(updated);
    _presence[username] = status;

    VaultSwarm.instance.broadcastMessage('presence', {
      'type': 'presence',
      'payload': {
        'userId': username,
        'status': status.name,
        'lastSeen': updated.lastSeen.millisecondsSinceEpoch,
      },
    });
  }

  bool isUserOnline(String username) {
    final status = _presence[username];
    return status == UserStatus.online;
  }

  Future<Conversation> getOrCreateConversation(String a, String b) async {
    if (a.trim().isEmpty || b.trim().isEmpty) {
      throw ArgumentError('Participant username cannot be empty');
    }

    final me = await _ensureUserExists(a);
    final peer = await _ensureUserExists(b);

    final existing = await ConversationDao.instance.findByParticipants(
      me.id,
      peer.id,
    );
    if (existing != null) return existing;

    final participants = [me.id, peer.id]..sort();
    final conversation = Conversation(
      id: _uuid.v4(),
      participant1Id: participants[0],
      participant2Id: participants[1],
      createdAt: DateTime.now(),
    );
    await ConversationDao.instance.insertConversation(conversation);
    return conversation;
  }

  Future<List<Conversation>> conversationsFor(String username) async {
    final user = await _ensureUserExists(username);
    return await ConversationDao.instance.getConversationsFor(user.id);
  }

  Future<List<DmMessage>> getConversationMessages(
    Conversation conversation, {
    int limit = 50,
    int offset = 0,
  }) async {
    return await DmMessagesDao.instance.getMessagesForConversation(
      conversation.id,
      limit: limit,
      offset: offset,
    );
  }

  Future<void> markConversationRead(
    String conversationId,
    String readerUsername,
  ) async {
    final reader = await _ensureUserExists(readerUsername);
    final conv = await ConversationDao.instance.getConversationById(
      conversationId,
    );
    if (conv == null) throw StateError('Conversation not found');
    if (!conv.involves(reader.id)) {
      throw StateError('User cannot mark this conversation as read');
    }
    await DmMessagesDao.instance.markConversationRead(
      conversationId,
      reader.id,
    );
  }

  Future<void> sendDirectMessage(
    String from,
    String to,
    String content, {
    String? replyToMessageId,
  }) async {
    final cleanText = _sanitize(content);
    if (cleanText.isEmpty) {
      throw ArgumentError('Message cannot be empty');
    }

    final sender = await _ensureUserExists(from);
    final recipient = await _ensureUserExists(to);

    final conversation = await getOrCreateConversation(from, to);

    final message = DmMessage(
      id: _uuid.v4(),
      conversationId: conversation.id,
      senderId: sender.id,
      content: cleanText,
      timestamp: DateTime.now(),
      isRead: false,
    );

    await DmMessagesDao.instance.insertMessage(message);

    // Broadcast to both participants via the swarm topic.
    final ids = [sender.id, recipient.id]..sort();
    final topic = 'dm:${ids.join('_')}';
    await VaultSwarm.instance.joinSwarm(topic);
    await VaultSwarm.instance.broadcastMessage(topic, {
      'type': 'dm_chat',
      'payload': {
        'conversationId': conversation.id,
        'message': message.toMap(),
      },
    });
  }

  void broadcastTypingStatus(
    String channelOrDmTopic,
    String userId,
    bool isTyping,
  ) {
    final now = DateTime.now();
    if (isTyping) {
      _typingStatus[userId] = now;
    } else {
      _typingStatus.remove(userId);
    }

    VaultSwarm.instance.broadcastMessage(channelOrDmTopic, {
      'type': 'typing',
      'payload': {
        'userId': userId,
        'isTyping': isTyping,
        'timestamp': now.millisecondsSinceEpoch,
      },
    });
  }

  bool isUserTyping(String userId) {
    final last = _typingStatus[userId];
    if (last == null) return false;
    return DateTime.now().difference(last).inSeconds < 5;
  }

  Future<List<DmMessage>> getUnreadMessages(String username) async {
    final user = await _ensureUserExists(username);
    return await DmMessagesDao.instance.getUnreadMessages(user.id);
  }

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
    final clean = _sanitize(text);
    if (clean.isEmpty) {
      throw ArgumentError('Cannot send empty message');
    }

    final message = ChatMessage(
      id: _uuid.v4(),
      serverId: serverId,
      channelId: channelId,
      author: author,
      text: clean,
      timestamp: DateTime.now(),
    );

    await ChatDao.instance.insertChatMessage(message);
  }

  Future<List<ChatMessage>> directMessagesBetween(
    String userA,
    String userB,
  ) async {
    final conversation = await getOrCreateConversation(userA, userB);
    final dmMessages = await DmMessagesDao.instance.getMessagesForConversation(
      conversation.id,
      limit: 500,
      offset: 0,
    );

    final userAInfo = await UsersDao.instance.getUserByName(userA);
    final userBInfo = await UsersDao.instance.getUserByName(userB);

    return dmMessages
        .map(
          (dm) => ChatMessage(
            id: dm.id,
            serverId: '',
            channelId: conversation.id,
            author: dm.senderId == userAInfo?.id ? userA : userB,
            text: dm.content,
            timestamp: dm.timestamp,
          ),
        )
        .toList();
  }

  Future<List<ChatHubEntry>> getChatHubEntries(String currentUser) async {
    final hub = <ChatHubEntry>[];

    final user = await _ensureUserExists(currentUser);
    final conversations = await conversationsFor(currentUser);

    for (final conv in conversations) {
      final peerId = conv.participant1Id == user.id
          ? conv.participant2Id
          : conv.participant1Id;
      final peerUser = await UsersDao.instance.getUserById(peerId);
      final peerName = peerUser?.username ?? 'Unknown';
      final unread = await DmMessagesDao.instance.getUnreadCountForConversation(
        conv.id,
        user.id,
      );
      final messages = await DmMessagesDao.instance.getMessagesForConversation(
        conv.id,
        limit: 1,
        offset: 0,
      );
      final latest = messages.isNotEmpty ? messages.last : null;
      hub.add(
        ChatHubEntry(
          id: conv.id,
          type: ChatHubEntryType.dm,
          title: peerName,
          subtitle: latest?.content ?? 'No messages yet',
          conversationId: conv.id,
          unread: unread,
          lastUpdated: latest?.timestamp ?? conv.createdAt,
        ),
      );
    }

    final servers = ServerService.instance.servers;
    for (final server in servers) {
      for (final channel in server.channels) {
        final messages = await ChatDao.instance.getMessagesFor(
          server.id,
          channel.id,
        );
        final latest = messages.isNotEmpty ? messages.last : null;
        hub.add(
          ChatHubEntry(
            id: '${server.id}:${channel.id}',
            type: ChatHubEntryType.serverChannel,
            title: '${server.name} / ${channel.name}',
            subtitle: latest?.text ?? 'No messages yet',
            serverId: server.id,
            channelId: channel.id,
            unread: 0,
            lastUpdated:
                latest?.timestamp ?? DateTime.fromMillisecondsSinceEpoch(0),
          ),
        );
      }
    }

    hub.sort((a, b) => b.lastUpdated.compareTo(a.lastUpdated));
    return hub;
  }

  Future<void> addReaction(String messageId, String emoji) async {
    // Reactions not persisted for DM messages in current schema, no-op for now.
    return;
  }

  Future<void> updateMessageText(String messageId, String updatedText) async {
    final dmMessage = await DmMessagesDao.instance.getMessageById(messageId);
    if (dmMessage != null) {
      await DmMessagesDao.instance.updateMessage(
        dmMessage.copyWith(content: updatedText),
      );
    }
  }

  Future<void> deleteMessage(String messageId) async {
    await DmMessagesDao.instance.deleteMessage(messageId);
  }

  static String dmChannelId(String userA, String userB) {
    final ids = [userA.trim(), userB.trim()]..sort();
    return 'dm-${ids[0]}-${ids[1]}';
  }

  static String dmSwarmTopic(String userA, String userB) {
    final ids = [userA.trim(), userB.trim()]..sort();
    return 'dm:${ids.join('_')}';
  }

  bool messageMentions(String userId, String text) {
    final mentionToken = '@${userId.trim()}';
    return text.split(RegExp(r'\s+')).contains(mentionToken);
  }

  String _sanitize(String text) {
    return text
        .trim()
        .replaceAll(RegExp(r"[\x00-\x1F]"), '')
        .replaceAll(RegExp(r'<[^>]*>'), '');
  }

  String _ensureString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is Uint8List) {
      try {
        return utf8.decode(value, allowMalformed: true);
      } catch (e) {
        debugPrint('ChatService._ensureString decode error: $e');
        return value.toString();
      }
    }
    try {
      return value.toString();
    } catch (e) {
      debugPrint('ChatService._ensureString toString error: $e');
      return '';
    }
  }

  Future<void> _listenForSwarmMessages() async {
    _swarmSubscription ??= VaultSwarm.instance.messageStream.listen((
      event,
    ) async {
      final type = event['type'] as String?;
      final payload = event['payload'] as Map<String, dynamic>?;

      if (type == 'presence' && payload != null) {
        final userId = payload['userId'] as String?;
        final status = payload['status'] as String?;
        if (userId != null && status != null) {
          _presence[userId] = userStatusFromString(status);
        }
      }

      if (type == 'typing' && payload != null) {
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
      }

      if (type == 'dm_chat' && payload != null) {
        final messageMap = payload['message'] as Map<String, dynamic>?;
        final conversationId = payload['conversationId'] as String?;
        if (messageMap != null && conversationId != null) {
          messageMap['content'] = _ensureString(messageMap['content']);
          messageMap['sender_id'] = _ensureString(messageMap['sender_id']);
          messageMap['conversation_id'] = _ensureString(
            messageMap['conversation_id'],
          );
          final mv = DmMessage.fromMap(messageMap);
          await DmMessagesDao.instance.insertMessage(mv);
        }
      }
    });
  }
}
