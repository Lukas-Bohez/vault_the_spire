import 'package:flutter_test/flutter_test.dart';
import 'package:vault_the_spire/services/chat_service.dart';

void main() {
  test('dm channel id is deterministic irrespective of input order', () {
    final id1 = ChatService.dmChannelId('alice', 'bob');
    final id2 = ChatService.dmChannelId('bob', 'alice');

    expect(id1, equals(id2));
    expect(id1, startsWith('dm-'));
  });

  test('message mentions detects @user properly', () {
    final service = ChatService.instance;

    expect(service.messageMentions('bob', 'hello @bob'), isTrue);
    expect(service.messageMentions('bob', 'hello @bob!'), isFalse);
    expect(service.messageMentions('bob', 'hello @bob from @alice'), isTrue);
    expect(service.messageMentions('bob', 'hello bob'), isFalse);
    expect(service.messageMentions('bob', '@bob'), isTrue);
  });

  test('typing broadcast updates remote typing state', () async {
    final topic = ChatService.dmTopic('alice', 'bob');
    final service = ChatService.instance;

    expect(service.isUserTyping('alice'), isFalse);

    service.broadcastTypingStatus(topic, 'alice', true);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(service.isUserTyping('alice'), isTrue);

    service.broadcastTypingStatus(topic, 'alice', false);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(service.isUserTyping('alice'), isFalse);
  });
}
