from pathlib import Path
path = Path('lib/screens/home_screen.dart')
text = path.read_text()
start_marker = 'Widget _buildMessagesArea(ThemeData theme) {'
end_marker = 'Widget _buildServerChatArea(ThemeData theme) {'
start = text.find(start_marker)
if start == -1:
    raise RuntimeError('start marker not found')
end = text.find(end_marker, start)
if end == -1:
    raise RuntimeError('end marker not found')

new_method = '''  Widget _buildMessagesArea(ThemeData theme) {
    final isPeerTyping = _selectedConversationId != null &&
        ChatService.instance.isUserTyping(
          _peerNameForConversation(
            _dmConversations.firstWhere(
              (c) => c.id == _selectedConversationId!,
              orElse: () => Conversation(
                id: '',
                participant1Id: '',
                participant2Id: '',
                createdAt: DateTime.now(),
              ),
            ),
          ),
        );

    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Direct Messages', style: theme.textTheme.headlineMedium),
              ),
              IconButton(
                tooltip: 'Start new DM',
                onPressed: () async {
                  final username = await showDialog<String>(
                    context: context,
                    builder: (context) {
                      final controller = TextEditingController();
                      return AlertDialog(
                        title: const Text('New direct message'),
                        content: TextFormField(
                          controller: controller,
                          decoration: const InputDecoration(
                            labelText: 'Peer username',
                            hintText: 'Enter peer username',
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () {
                              if (controller.text.trim().isNotEmpty) {
                                Navigator.of(context).pop(controller.text.trim());
                              }
                            },
                            child: const Text('Create'),
                          ),
                        ],
                      );
                    },
                  );
                  if (username != null && username.isNotEmpty) {
                    try {
                      final conversation = await ChatService.instance.getOrCreateConversation(_currentUser, username);
                      await _loadDmConversations();
                      _selectConversation(conversation);
                    } catch (error) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to start DM: $error')));
                    }
                  }
                },
                icon: const Icon(Icons.add),
              ),
              Text('You: $_currentUser', style: theme.textTheme.bodySmall),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 260,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _dmPeerController,
                      decoration: const InputDecoration(
                        labelText: 'Peer username',
                        hintText: 'Enter username',
                        isDense: true,
                      ),
                      onChanged: (value) => setState(() {
                        _selectedDmPeer = value.trim();
                      }),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _selectedDmPeer.isEmpty
                          ? null
                          : () async {
                              _currentUser = _currentUser.trim();
                              final peerName = _selectedDmPeer.trim();
                              if (peerName.isEmpty) return;
                              final conversation = await ChatService.instance.getOrCreateConversation(_currentUser, peerName);
                              await _loadDmConversations();
                              _selectConversation(conversation);
                            },
                      child: const Text('Open Conversation'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Search',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) => setState(() {
                        _dmSearchQuery = value.toLowerCase();
                      }),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: _dmConversations.isEmpty
                          ? const Center(child: Text('No conversations yet'))
                          : ListView.builder(
                              itemCount: _dmConversations.length,
                              itemBuilder: (context, index) {
                                final conversation = _dmConversations[index];
                                final peer = _peerNameForConversation(conversation);
                                if (_dmSearchQuery.isNotEmpty && !peer.toLowerCase().contains(_dmSearchQuery)) {
                                  return const SizedBox.shrink();
                                }
                                final unread = _dmUnread[conversation.id] ?? 0;
                                final isSelected = conversation.id == _selectedConversationId;
                                final isOnline = ChatService.instance.isUserOnline(peer);
                                return ListTile(
                                  selected: isSelected,
                                  selectedTileColor: theme.colorScheme.primaryContainer,
                                  leading: CircleAvatar(child: Text(peer.isNotEmpty ? peer[0].toUpperCase() : '?')),
                                  title: Text(peer),
                                  subtitle: Text(isOnline ? 'online' : 'offline'),
                                  trailing: unread > 0
                                      ? CircleAvatar(
                                          radius: 10,
                                          backgroundColor: Colors.red,
                                          child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 12)),
                                        )
                                      : null,
                                  onTap: () => _selectConversation(conversation),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _buildDmConversationPane(theme)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDmConversationPane(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _selectedConversationId == null
              ? Center(child: Text('Pick a conversation on left', style: theme.textTheme.bodyMedium))
              : FutureBuilder<List<DmMessage>>(
                  future: _loadSelectedConversationMessages().then((_) => _dmMessages),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text('Unable to load messages: ${snapshot.error}'));
                    }
                    final messages = snapshot.data ?? [];
                    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd(_dmChatScrollController, animate: true));
                    if (messages.isEmpty) {
                      return const Center(child: Text('No messages yet. Start the conversation.'));
                    }

                    return ListView.builder(
                      controller: _dmChatScrollController,
                      padding: const EdgeInsets.all(10),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final m = messages[index];
                        final sender = _dmUserNames[m.senderId] ?? m.senderId;
                        final isMe = m.senderId == _currentUserId;
                        return Align(
                          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 520),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isMe ? theme.colorScheme.primaryContainer : theme.colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(sender, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text(m.content),
                                const SizedBox(height: 6),
                                Text('${m.timestamp.hour.toString().padLeft(2, "0")}:${m.timestamp.minute.toString().padLeft(2, "0")}',
                                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 10)),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
        if (isPeerTyping)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('${_peerNameForConversation(_dmConversations.firstWhere((c) => c.id == _selectedConversationId!))} is typing...', style: const TextStyle(color: Colors.green)),
          ),
        const SizedBox(height: 8),
        RawKeyboardListener(
          focusNode: _dmMessageFocusNode,
          onKey: (event) async {
            if (event is RawKeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
              if (event.isShiftPressed) {
                final selection = _dmMessageController.selection;
                final text = _dmMessageController.text;
                final result = text.replaceRange(selection.start, selection.end, '\n');
                _dmMessageController.value = TextEditingValue(
                  text: result,
                  selection: TextSelection.collapsed(offset: selection.start + 1),
                );
              } else {
                await _sendDmMessage();
              }
            }
          },
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  focusNode: _dmMessageFocusNode,
                  controller: _dmMessageController,
                  decoration: const InputDecoration(
                    hintText: 'Type a message',
                    border: OutlineInputBorder(),
                  ),
                  minLines: 1,
                  maxLines: 6,
                  keyboardType: TextInputType.multiline,
                  onChanged: (value) {
                    if (_selectedConversationId != null) {
                      final peer = _peerNameForConversation(
                        _dmConversations.firstWhere((c) => c.id == _selectedConversationId!),
                      );
                      final topic = ChatService.dmSwarmTopic(_currentUser, peer);
                      ChatService.instance.broadcastTypingStatus(topic, _currentUser, value.isNotEmpty);
                    }
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: _selectedConversationId == null ? null : _sendDmMessage,
              ),
            ],
          ),
        ),
      ],
    );
  }
'''

# Perform replacement
text = text[:start] + new_method + text[end:]
path.write_text(text)
print('Replaced method contents')
PY