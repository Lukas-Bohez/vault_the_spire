// ignore_for_file: use_build_context_synchronously
import 'dart:async';

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
  Timer? _typingTimer;
  ChatMessage? _replyTarget;
  @override
  void initState() {
    super.initState();
    _typingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {}); // refresh typing indicator
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    ChatService.instance.setTypingStatus(widget.user, false);
    _typingTimer?.cancel();
    _typingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });

    if (text.isEmpty) return;
    await ChatService.instance.sendMessage(
      '_dm',
      ChatService.dmChannelId(widget.user, widget.peer),
      widget.user,
      text,
      replyToMessageId: _replyTarget?.id,
    );
    _replyTarget = null;
    _controller.clear();

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
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.text,
                            style: TextStyle(
                              color: mentionsCurrent
                                  ? Colors.orangeAccent
                                  : null,
                            ),
                          ),
                          Wrap(
                            spacing: 4,
                            children: m.reactions.entries
                                .map(
                                  (entry) => Chip(
                                    label: Text('${entry.key} ${entry.value}'),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                      ),
                      onLongPress: () async {
                        final parentContext = context;
                        final action = await showModalBottomSheet<String>(
                          context: parentContext,
                          builder: (ctx) {
                            return Wrap(
                              spacing: 4,
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.emoji_emotions),
                                  title: const Text('React'),
                                  onTap: () => Navigator.of(ctx).pop('react'),
                                ),
                                ListTile(
                                  leading: const Icon(Icons.edit),
                                  title: const Text('Edit'),
                                  onTap: () => Navigator.of(ctx).pop('edit'),
                                ),
                                ListTile(
                                  leading: const Icon(Icons.repeat),
                                  title: const Text('Reply'),
                                  onTap: () => Navigator.of(ctx).pop('reply'),
                                ),
                                ListTile(
                                  leading: const Icon(Icons.delete),
                                  title: const Text('Delete'),
                                  onTap: () => Navigator.of(ctx).pop('delete'),
                                ),
                              ],
                            );
                          },
                        );
                        if (action == 'react') {
                          final emoji = await showModalBottomSheet<String>(
                            context: parentContext,
                            builder: (ctx) {
                              return Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: ['👍', '❤️', '😂', '😮', '😢', '🔥']
                                    .map(
                                      (e) => ChoiceChip(
                                        label: Text(e),
                                        selected: false,
                                        onSelected: (_) {
                                          Navigator.of(ctx).pop(e);
                                        },
                                      ),
                                    )
                                    .toList(),
                              );
                            },
                          );
                          if (emoji != null) {
                            await ChatService.instance.addReaction(m.id, emoji);
                            if (!mounted) return;
                            setState(() {});
                          }
                        } else if (action == 'reply') {
                          setState(() {
                            _replyTarget = m;
                          });
                        } else if (action == 'edit') {
                          final editController = TextEditingController(
                            text: m.text,
                          );
                          final edited = await showDialog<String>(
                            context: parentContext,
                            builder: (ctx) {
                              return AlertDialog(
                                title: const Text('Edit message'),
                                content: TextField(
                                  controller: editController,
                                  autofocus: true,
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.of(ctx).pop(),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.of(
                                      ctx,
                                    ).pop(editController.text.trim()),
                                    child: const Text('Save'),
                                  ),
                                ],
                              );
                            },
                          );
                          if (edited != null &&
                              edited.isNotEmpty &&
                              edited != m.text) {
                            await ChatService.instance.updateMessageText(
                              m.id,
                              edited,
                            );
                            if (!mounted) return;
                            setState(() {});
                          }
                        } else if (action == 'delete') {
                          final confirm = await showDialog<bool>(
                            context: parentContext,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete message?'),
                              content: const Text('This cannot be undone.'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await ChatService.instance.deleteMessage(m.id);
                            if (!mounted) return;
                            setState(() {});
                          }
                        }
                      },
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_replyTarget != null)
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _replyTarget = null;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 8,
                            ),
                            color: Colors.grey.shade200,
                            child: Text(
                              'Replying to ${_replyTarget!.author} • tap to cancel',
                            ),
                          ),
                        ),
                      TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: _replyTarget != null
                              ? 'Replying to ${_replyTarget!.author}'
                              : 'Type a direct message',
                        ),
                        onChanged: (value) {
                          ChatService.instance.setTypingStatus(
                            widget.user,
                            value.isNotEmpty,
                          );
                          if (value.isNotEmpty) {
                            _typingTimer?.cancel();
                            _typingTimer = Timer(
                              const Duration(seconds: 5),
                              () {
                                ChatService.instance.setTypingStatus(
                                  widget.user,
                                  false,
                                );
                                if (mounted) setState(() {});
                              },
                            );
                          }
                        },
                      ),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.send), onPressed: _send),
              ],
            ),
          ),
          if (ChatService.instance.isUserTyping(widget.peer))
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.more_horiz, size: 16),
                  const SizedBox(width: 4),
                  Text('${widget.peer} is typing...'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
