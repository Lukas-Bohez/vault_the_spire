import 'package:flutter/material.dart';
import 'package:vault_the_spire/models/chat_message.dart';
import 'package:vault_the_spire/services/chat_service.dart';
import 'package:vault_the_spire/services/sound_service.dart';

class DMScreen extends StatefulWidget {
  final String user;
  final String peer;

  const DMScreen({super.key, required this.user, required this.peer});

  @override
  State<DMScreen> createState() => _DMScreenState();
}

class _DMScreenState extends State<DMScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    await ChatService.instance.sendDirectMessage(
      widget.user,
      widget.peer,
      text,
    );
    if (ChatService.instance.messageMentions(widget.user, text) ||
        ChatService.instance.messageMentions(widget.peer, text)) {
      await SoundService.instance.playMention();
    } else {
      await SoundService.instance.playSend();
    }
    _controller.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('DM: ${widget.user} ↔ ${widget.peer}')),
      body: Column(
        children: [
          Expanded(
            child: FutureBuilder<List<ChatMessage>>(
              future: ChatService.instance.directMessagesBetween(
                widget.user,
                widget.peer,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
                }
                final messages = snapshot.data ?? [];
                if (messages.isEmpty) {
                  return const Center(
                    child: Text('No DMs yet. Start the conversation.'),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final m = messages[index];
                    final mentionsCurrent = ChatService.instance
                        .messageMentions(widget.user, m.text);
                    return ListTile(
                      title: Text(
                        '${m.author} • ${m.timestamp.hour}:${m.timestamp.minute.toString().padLeft(2, '0')}',
                      ),
                      subtitle: Text(
                        m.text,
                        style: TextStyle(
                          color: mentionsCurrent ? Colors.orangeAccent : null,
                        ),
                      ),
                    );
                  },
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
                      hintText: 'Type a direct message',
                    ),
                  ),
                ),
                IconButton(icon: const Icon(Icons.send), onPressed: _send),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
