import 'package:flutter/material.dart';
import 'package:vault_the_spire/models/server.dart';
import 'package:vault_the_spire/services/chat_service.dart';

class ChatScreen extends StatefulWidget {
  final ServerModel server;
  final String channelId;

  const ChatScreen({super.key, required this.server, required this.channelId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.server.channels.firstWhere(
      (c) => c.id == widget.channelId,
    );
    final messages = ChatService.instance.messagesFor(
      widget.server.id,
      widget.channelId,
    );

    return Scaffold(
      appBar: AppBar(title: Text('${widget.server.name} / ${channel.name}')),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final m = messages[index];
                return ListTile(
                  title: Text(m.author),
                  subtitle: Text(m.text),
                  trailing: Text(
                    '${m.timestamp.hour}:${m.timestamp.minute.toString().padLeft(2, '0')}',
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      hintText: 'Type a message',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () {
                    final text = _controller.text.trim();
                    if (text.isEmpty) return;
                    ChatService.instance.sendMessage(
                      widget.server.id,
                      widget.channelId,
                      'you',
                      text,
                    );
                    _controller.clear();
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
