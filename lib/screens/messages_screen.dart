import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vault_the_spire/models/message.dart';
import 'package:vault_the_spire/services/message_service.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  final _recipientController = TextEditingController();
  final _bodyController = TextEditingController();
  List<MessageModel> _messages = [];
  List<String> _conversationRecipients = [];
  String? _selectedRecipient;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reloadMessages();
  }

  Future<void> _reloadMessages() async {
    setState(() => _loading = true);
    _messages = await MessageService.instance.getMessages();

    final recipients = <String>{};
    for (final m in _messages) {
      if (m.sender == 'me') {
        if (m.recipient.isNotEmpty) recipients.add(m.recipient);
      } else {
        recipients.add(m.sender);
      }
    }

    _conversationRecipients = recipients.toList()..sort();
    if (_selectedRecipient == null && _conversationRecipients.isNotEmpty) {
      _selectedRecipient = _conversationRecipients.first;
      _recipientController.text = _selectedRecipient ?? '';
    }

    setState(() => _loading = false);
  }

  Future<void> _selectConversation(String peer) async {
    if (!mounted) return;
    _selectedRecipient = peer;
    _recipientController.text = peer;
    setState(() {});
  }

  Future<void> _sendMessage() async {
    final recipient = (_recipientController.text.trim().isNotEmpty)
        ? _recipientController.text.trim()
        : _selectedRecipient;
    final body = _bodyController.text.trim();

    if (recipient == null || recipient.isEmpty || body.isEmpty) return;

    await MessageService.instance.sendLocalMessage(
      sender: 'me',
      recipient: recipient,
      body: body,
    );

    _bodyController.clear();
    _selectedRecipient = recipient;
    await _reloadMessages();
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  List<MessageModel> _conversationMessages() {
    if (_selectedRecipient == null) return [];
    return _messages
        .where(
          (m) =>
              (m.sender == 'me' && m.recipient == _selectedRecipient) ||
              (m.sender == _selectedRecipient && m.recipient == 'me'),
        )
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  String _formatTimestamp(int millis) {
    final dt = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
    final now = DateTime.now();
    final isToday =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    if (isToday) return '$hour:$minute';
    return '${dt.day}/${dt.month} $hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final conversations = _conversationRecipients;
    final selectedMessages = _conversationMessages();

    return Scaffold(
      appBar: AppBar(title: const Text('Secure Messaging')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 260,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colors.surface.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Conversations',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  Expanded(
                    child: conversations.isEmpty
                        ? const Center(child: Text('No conversations yet'))
                        : ListView.builder(
                            itemCount: conversations.length,
                            itemBuilder: (context, index) {
                              final peer = conversations[index];
                              final unreadCount = _messages
                                  .where(
                                    (m) =>
                                        m.sender == peer &&
                                        !m.isSent &&
                                        m.recipient == 'me',
                                  )
                                  .length;
                              return ListTile(
                                title: Text(peer),
                                trailing: unreadCount > 0
                                    ? CircleAvatar(
                                        radius: 10,
                                        backgroundColor: colors.error,
                                        child: Text(
                                          unreadCount.toString(),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: colors.onError,
                                          ),
                                        ),
                                      )
                                    : null,
                                selected: _selectedRecipient == peer,
                                selectedTileColor: colors.primary.withValues(
                                  alpha: 0.16,
                                ),
                                onTap: () => _selectConversation(peer),
                              );
                            },
                          ),
                  ),
                  TextField(
                    controller: _recipientController,
                    decoration: const InputDecoration(
                      labelText: 'Peer username',
                      hintText: 'Enter peer username',
                    ),
                    onSubmitted: (text) {
                      if (text.isNotEmpty) {
                        _selectConversation(text);
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  if (kDebugMode)
                    ElevatedButton.icon(
                      icon: const Icon(Icons.bug_report),
                      label: const Text('Simulate incoming'),
                      onPressed: () async {
                        final target = _selectedRecipient ?? 'test-peer';
                        await MessageService.instance.sendLocalMessage(
                          sender: target,
                          recipient: 'me',
                          body: 'Sample debug inbound message',
                        );
                        await _reloadMessages();
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_selectedRecipient == null)
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.chat_bubble_outline,
                                size: 72,
                                color: colors.onSurfaceVariant,
                              ),
                              SizedBox(height: 12),
                              Text(
                                'Select a peer or enter a username to start messaging',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else ...[
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedRecipient!,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  'Last activity: ${selectedMessages.isEmpty ? '—' : _formatTimestamp(selectedMessages.last.createdAt)}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: _loading
                            ? const Center(child: CircularProgressIndicator())
                            : ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: selectedMessages.length,
                                itemBuilder: (context, index) {
                                  final message = selectedMessages[index];
                                  final isMine = message.sender == 'me';
                                  return Align(
                                    alignment: isMine
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                        vertical: 4,
                                      ),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: isMine
                                            ? colors.primaryContainer
                                            : colors.surface.withValues(
                                                alpha: 0.88,
                                              ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            message.body,
                                            style: TextStyle(
                                              color: isMine
                                                  ? colors.onPrimaryContainer
                                                  : colors.onSurface,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            _formatTimestamp(message.createdAt),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: isMine
                                                  ? colors.onPrimaryContainer
                                                        .withValues(alpha: 0.72)
                                                  : colors.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _bodyController,
                                textInputAction: TextInputAction.send,
                                onSubmitted: (_) => _sendMessage(),
                                decoration: const InputDecoration(
                                  hintText: 'Type your message',
                                  border: OutlineInputBorder(),
                                ),
                                minLines: 1,
                                maxLines: 3,
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _sendMessage,
                              child: const Icon(Icons.send),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
