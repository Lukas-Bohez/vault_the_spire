import 'package:flutter/material.dart';
import 'package:vault_the_spire/models/chat_message.dart';
import 'package:vault_the_spire/models/server.dart';
import 'package:vault_the_spire/services/chat_service.dart';
import 'package:vault_the_spire/services/sound_service.dart';

class ChatScreen extends StatefulWidget {
  final ServerModel server;
  final String channelId;

  const ChatScreen({super.key, required this.server, required this.channelId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  List<ChatMessage> _messages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    setState(() {
      _loading = true;
    });
    _messages = await ChatService.instance.messagesFor(
      widget.server.id,
      widget.channelId,
    );
    setState(() {
      _loading = false;
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    await ChatService.instance.sendMessage(
      widget.server.id,
      widget.channelId,
      'you',
      text,
    );
    if (ChatService.instance.messageMentions('you', text)) {
      await SoundService.instance.playMention();
    } else {
      await SoundService.instance.playSend();
    }
    _controller.clear();
    await _loadMessages();
  }

  @override
  Widget build(BuildContext context) {
    final channel = widget.server.channels.firstWhere(
      (c) => c.id == widget.channelId,
    );

    return Scaffold(
      appBar: AppBar(title: Text('${widget.server.name} / ${channel.name}')),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(child: Text('No messages yet.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final m = _messages[index];
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
                  onPressed: _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
