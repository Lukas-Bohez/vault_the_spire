import 'dart:async';

/// Simplified P2P swarm emitter for DM/chat messages.
///
/// In a real production implementation this would use DHT discovery + peer wire
/// plus encryption ratchet for channel topics. For now it provides an in-memory
/// message bus that mirrors swarm behavior and is easy to replace with real
/// networking.
class VaultSwarm {
  VaultSwarm._();
  static final VaultSwarm instance = VaultSwarm._();

  final Set<String> _joinedTopics = <String>{};
  final StreamController<Map<String, dynamic>> _messageController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  Future<void> joinSwarm(String topic) async {
    _joinedTopics.add(topic);
    // TODO: real P2P join; add DHT peer discovery and swarm management.
  }

  bool isJoined(String topic) => _joinedTopics.contains(topic);

  Future<void> broadcastMessage(
    String topic,
    Map<String, dynamic> payload,
  ) async {
    if (!isJoined(topic)) {
      await joinSwarm(topic);
    }

    final event = <String, dynamic>{
      'topic': topic,
      'type': payload['type'] ?? 'chat',
      'payload': payload,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    _messageController.add(event);
  }

  void dispose() {
    _messageController.close();
  }
}
