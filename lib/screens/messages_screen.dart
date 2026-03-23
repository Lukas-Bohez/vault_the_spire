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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reloadMessages();
  }

  Future<void> _reloadMessages() async {
    setState(() => _loading = true);
    _messages = await MessageService.instance.getMessages();
    setState(() => _loading = false);
  }

  Future<void> _sendMessage() async {
    final recipient = _recipientController.text.trim();
    final body = _bodyController.text.trim();
    if (recipient.isEmpty || body.isEmpty) return;

    await MessageService.instance.sendLocalMessage(
      sender: 'me',
      recipient: recipient,
      body: body,
    );

    _recipientController.clear();
    _bodyController.clear();
    await _reloadMessages();
  }

  @override
  void dispose() {
    _recipientController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Special Messaging')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _recipientController,
              decoration: const InputDecoration(labelText: 'Recipient'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bodyController,
              decoration: const InputDecoration(labelText: 'Message'),
              minLines: 2,
              maxLines: 5,
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.send),
              label: const Text('Send Message'),
              onPressed: _sendMessage,
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_messages.isEmpty)
              const Text('No messages yet. Send one!')
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final m = _messages[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text(m.recipient),
                        subtitle: Text(m.body),
                        trailing: Text(
                          m.isSent ? 'sent' : 'draft',
                          style: TextStyle(
                            color: m.isSent ? Colors.green : Colors.orange,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
