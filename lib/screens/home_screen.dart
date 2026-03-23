import 'package:flutter/material.dart';
import 'package:vault_the_spire/services/sound_service.dart';
import 'package:vault_the_spire/services/identity_service.dart';
import 'package:vault_the_spire/services/settings_service.dart';
import 'package:vault_the_spire/services/chat_service.dart';
import 'package:vault_the_spire/services/theme_service.dart';
import 'package:vault_the_spire/services/tray_service.dart';
import 'package:vault_the_spire/services/server_service.dart';
import 'package:vault_the_spire/models/server.dart';
import 'package:vault_the_spire/services/startup_service.dart';
import 'package:vault_the_spire/services/torrent_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum MainView { dashboard, torrents, messages, server }

class _HomeScreenState extends State<HomeScreen> {
  bool useSystemTray = false;
  bool minimizeToTrayOnClose = false;
  bool launchOnStartup = false;
  MainView _mainView = MainView.dashboard;
  ServerModel? selectedServer;
  String? selectedChannelId;
  int _mobileNavIndex = 0;
  String _selectedDmPeer = '';
  bool _inVoiceChannel = false;
  String _voiceChannelServer = '';
  final Set<String> _dmContacts = <String>{};
  final Map<String, int> _dmUnread = <String, int>{};
  final Map<String, bool> _voiceMuted = <String, bool>{};
  final TextEditingController _serverNameController = TextEditingController();
  final TextEditingController _inviteCodeController = TextEditingController();
  final TextEditingController _channelNameController = TextEditingController();
  final TextEditingController _dmPeerController = TextEditingController();
  final TextEditingController _dmMessageController = TextEditingController();
  final TextEditingController _inlineMessageController =
      TextEditingController();
  final ScrollController _serverChatScrollController = ScrollController();
  final ScrollController _dmChatScrollController = ScrollController();

  @override
  void dispose() {
    _serverNameController.dispose();
    _inviteCodeController.dispose();
    _channelNameController.dispose();
    _dmPeerController.dispose();
    _dmMessageController.dispose();
    _inlineMessageController.dispose();
    _serverChatScrollController.dispose();
    _dmChatScrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    useSystemTray = SettingsService.instance.useSystemTray;
    minimizeToTrayOnClose = SettingsService.instance.minimizeToTrayOnClose;
    launchOnStartup = SettingsService.instance.launchOnStartup;

    ServerService.instance.init().then((_) {
      setState(() {});
    });
  }

  Future<void> _toggleSystemTray(bool value) async {
    await SettingsService.instance.setUseSystemTray(value);
    setState(() {
      useSystemTray = value;
      if (value) {
        TrayService.shouldMinimiseToTrayOnClose = minimizeToTrayOnClose;
      }
    });
  }

  Future<void> _toggleMinimizeToTray(bool value) async {
    await SettingsService.instance.setMinimizeToTrayOnClose(value);
    setState(() {
      minimizeToTrayOnClose = value;
      TrayService.shouldMinimiseToTrayOnClose = value;
    });
  }

  Future<void> _toggleLaunchOnStartup(bool value) async {
    await SettingsService.instance.setLaunchOnStartup(value);
    if (value) {
      await StartupService.enable();
    } else {
      await StartupService.disable();
    }
    setState(() {
      launchOnStartup = value;
    });
  }

  void _scrollToEnd(ScrollController controller) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.hasClients) {
        controller.jumpTo(controller.position.maxScrollExtent);
      }
    });
  }

  void _markDmRead(String peer) {
    setState(() {
      _dmUnread[peer] = 0;
    });
  }

  Future<void> _toggleVoiceChannel(String serverId, String channelName) async {
    final joining = !_inVoiceChannel;
    setState(() {
      _inVoiceChannel = joining;
      _voiceChannelServer = joining ? '$channelName @ $serverId' : '';
    });
    if (joining) {
      _voiceMuted['you'] = false;
      await SoundService.instance.playNotification();
      await SoundService.instance.startVoiceSession();
    } else {
      _voiceMuted.clear();
      await SoundService.instance.playClick();
      await SoundService.instance.stopVoiceSession();
    }
  }

  Widget _buildServerPanel(ThemeData theme) {
    final identity = IdentityService.instance.identity;
    return Container(
      width: 260,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'VaultTheSpire',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: () => setState(() {
                    _mainView = MainView.dashboard;
                  }),
                  child: const Text('Dashboard'),
                ),
                ElevatedButton(
                  onPressed: () => setState(() {
                    _mainView = MainView.torrents;
                  }),
                  child: const Text('Torrents'),
                ),
                ElevatedButton(
                  onPressed: () => setState(() {
                    _mainView = MainView.messages;
                  }),
                  child: const Text('Messages'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Connected', style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            const Text(
              'quizthespire.com',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            Text('Identity', style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            Text(identity != null ? identity.nodeId : 'No node'),
            const SizedBox(height: 10),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'Servers',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...ServerService.instance.servers.map((server) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Text(server.icon),
                title: Text(server.name),
                subtitle: Text(
                  server.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                selected: selectedServer?.id == server.id,
                onTap: () async {
                  await SoundService.instance.playClick();
                  setState(() {
                    selectedServer = server;
                    selectedChannelId = server.channels.isNotEmpty
                        ? server.channels.first.id
                        : null;
                    _mainView = MainView.server;
                  });
                },
                trailing: PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'invite') {
                      final inviteCode = ServerService.instance.generateInvite(
                        server,
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Invite code: $inviteCode')),
                      );
                    }
                    if (value == 'delete') {
                      await ServerService.instance.removeServer(server.id);
                      if (selectedServer?.id == server.id) {
                        selectedServer = null;
                        selectedChannelId = null;
                      }
                      setState(() {});
                    }
                    if (value == 'rename') {
                      final newName = await showDialog<String>(
                        context: context,
                        builder: (context) {
                          final tmp = TextEditingController(text: server.name);
                          return AlertDialog(
                            title: const Text('Rename server'),
                            content: TextField(controller: tmp),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('Cancel'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(tmp.text.trim()),
                                child: const Text('Rename'),
                              ),
                            ],
                          );
                        },
                      );
                      if (newName != null && newName.isNotEmpty) {
                        await ServerService.instance.renameServer(
                          server.id,
                          newName,
                        );
                        if (selectedServer?.id == server.id)
                          selectedServer = server.copyWith(name: newName);
                        setState(() {});
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'invite',
                      child: Text('Copy invite code'),
                    ),
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            TextField(
              controller: _inviteCodeController,
              decoration: const InputDecoration(
                labelText: 'Invite code',
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                await SoundService.instance.playNotification();
                final success = await ServerService.instance.joinServer(
                  _inviteCodeController.text.trim(),
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success ? 'Joined server!' : 'Invalid invite code.',
                    ),
                  ),
                );
                if (success) {
                  _inviteCodeController.clear();
                  setState(() {});
                }
              },
              child: const Text('Join server'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _serverNameController,
              decoration: const InputDecoration(
                labelText: 'New server name',
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () async {
                await SoundService.instance.playNotification();
                if (_serverNameController.text.trim().isEmpty) return;
                final server = ServerService.instance.createServer(
                  name: _serverNameController.text.trim(),
                  description: 'Community server',
                );
                _serverNameController.clear();
                setState(() {
                  selectedServer = server;
                  selectedChannelId = server.channels.first.id;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Created server: ${server.name} (invite: ${server.id})',
                    ),
                  ),
                );
              },
              child: const Text('Create server'),
            ),
            const SizedBox(height: 8),
            if (selectedServer != null) ...[
              Card(
                color: _inVoiceChannel
                    ? theme.colorScheme.tertiaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                child: ListTile(
                  leading: const Icon(Icons.mic),
                  title: Text(
                    _inVoiceChannel
                        ? 'In voice in: $_voiceChannelServer'
                        : 'Not in voice channel',
                  ),
                  trailing: ElevatedButton(
                    onPressed: () {
                      if (selectedServer != null) {
                        _toggleVoiceChannel(
                          selectedServer!.id,
                          selectedServer!.name,
                        );
                      }
                    },
                    child: Text(_inVoiceChannel ? 'Leave' : 'Join'),
                  ),
                ),
              ),
              if (_inVoiceChannel)
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      final newPeer = 'friend${_voiceMuted.length + 1}';
                      _voiceMuted[newPeer] = false;
                    });
                    SoundService.instance.playNotification();
                  },
                  icon: const Icon(Icons.person_add),
                  label: const Text('Add participant'),
                ),
              const SizedBox(height: 10),
              const Text(
                'Create Channel',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _channelNameController,
                decoration: const InputDecoration(
                  labelText: 'New channel name',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 6),
              ElevatedButton(
                onPressed: () async {
                  await SoundService.instance.playClick();
                  final name = _channelNameController.text.trim();
                  if (name.isEmpty || selectedServer == null) return;
                  final updated = await ServerService.instance.addChannel(
                    selectedServer!.id,
                    name,
                  );
                  _channelNameController.clear();
                  setState(() {
                    selectedServer = updated;
                    selectedChannelId = updated.channels.last.id;
                  });
                },
                child: const Text('Add channel'),
              ),
            ],
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildTorrentsArea(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Torrents', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 10),
          FutureBuilder<List<dynamic>>(
            future: TorrentService.instance.allTorrents(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Text('Error loading torrents: ${snapshot.error}');
              }
              final torrents = snapshot.data ?? [];
              if (torrents.isEmpty) {
                return const Center(child: Text('No torrents yet.'));
              }
              return Expanded(
                child: ListView.builder(
                  itemCount: torrents.length,
                  itemBuilder: (context, index) {
                    final torrent = torrents[index];
                    return ListTile(
                      title: Text(torrent.name ?? 'Unnamed'),
                      subtitle: Text(torrent.status ?? 'unknown'),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesArea(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Direct Messages', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _dmPeerController,
                  decoration: const InputDecoration(
                    labelText: 'Peer username',
                    hintText: 'Enter username to chat with',
                    isDense: true,
                  ),
                  onChanged: (value) => setState(() {
                    _selectedDmPeer = value.trim();
                  }),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _selectedDmPeer.isEmpty
                    ? null
                    : () {
                        setState(() {
                          _dmContacts.add(_selectedDmPeer);
                          _dmUnread[_selectedDmPeer] = 0;
                        });
                      },
                child: const Text('Open'),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _selectedDmPeer.isEmpty
                    ? null
                    : () async {
                        final peer = _selectedDmPeer;
                        await ChatService.instance.sendDirectMessage(
                          peer,
                          'you',
                          'Hey from $peer (simulated)',
                        );
                        setState(() {
                          _dmContacts.add(peer);
                          if (_selectedDmPeer != peer) {
                            _dmUnread[peer] = (_dmUnread[peer] ?? 0) + 1;
                          }
                        });
                      },
                child: const Text('Simulate incoming'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_dmContacts.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _dmContacts.map((peer) {
                  final unread = _dmUnread[peer] ?? 0;
                  return ActionChip(
                    label: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(peer),
                        if (unread > 0) ...[
                          const SizedBox(width: 4),
                          CircleAvatar(
                            radius: 8,
                            backgroundColor: theme.colorScheme.primary,
                            child: Text(
                              '$unread',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedDmPeer = peer;
                        _markDmRead(peer);
                      });
                    },
                  );
                }).toList(),
              ),
            ),
          if (_selectedDmPeer.isEmpty)
            const Text('Select a peer to start a direct conversation.')
          else
            Expanded(
              child: FutureBuilder<List<dynamic>>(
                future: ChatService.instance.directMessagesBetween(
                  'you',
                  _selectedDmPeer,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Text('DM load error: ${snapshot.error}');
                  }
                  final messages = snapshot.data ?? [];
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _scrollToEnd(_dmChatScrollController);
                  });
                  if (messages.isEmpty) {
                    return const Center(child: Text('No direct messages yet.'));
                  }
                  return ListView.builder(
                    controller: _dmChatScrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final m = messages[index];
                      final isMe = m.author == 'you';
                      return Align(
                        alignment: isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Card(
                          color: isMe
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.secondaryContainer,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  m.author,
                                  style: theme.textTheme.labelSmall,
                                ),
                                const SizedBox(height: 4),
                                Text(m.text),
                                const SizedBox(height: 4),
                                Text(
                                  '${m.timestamp.hour.toString().padLeft(2, '0')}:${m.timestamp.minute.toString().padLeft(2, '0')}',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _dmMessageController,
                  decoration: const InputDecoration(
                    hintText: 'Message peer',
                    isDense: true,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: _selectedDmPeer.isEmpty
                    ? null
                    : () async {
                        final text = _dmMessageController.text.trim();
                        if (text.isEmpty) return;
                        await ChatService.instance.sendDirectMessage(
                          'you',
                          _selectedDmPeer,
                          text,
                        );
                        if (ChatService.instance.messageMentions(
                          _selectedDmPeer,
                          text,
                        )) {
                          await SoundService.instance.playMention();
                        } else {
                          await SoundService.instance.playSend();
                        }
                        _dmMessageController.clear();
                        setState(() {});
                        _scrollToEnd(_dmChatScrollController);
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildServerChatArea(ThemeData theme) {
    if (selectedServer == null || selectedChannelId == null) {
      return Center(
        child: Text(
          'Select a server/channel to start chatting',
          style: theme.textTheme.bodyLarge,
        ),
      );
    }

    final channel = selectedServer!.channels.firstWhere(
      (c) => c.id == selectedChannelId!,
      orElse: () => ChannelModel(id: '', name: 'unknown'),
    );

    return Column(
      children: [
        if (_inVoiceChannel)
          Container(
            width: double.infinity,
            color: theme.colorScheme.secondaryContainer,
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Voice chat active: $_voiceChannelServer',
                  style: theme.textTheme.bodyMedium,
                ),
                TextButton.icon(
                  onPressed: () {
                    _toggleVoiceChannel(
                      selectedServer!.id,
                      selectedServer!.name,
                    );
                  },
                  icon: const Icon(Icons.mic_off),
                  label: const Text('Leave voice'),
                ),
              ],
            ),
          ),
        if (_inVoiceChannel)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
            child: Wrap(
              spacing: 8,
              children: _voiceMuted.entries.map((entry) {
                return InputChip(
                  label: Text('${entry.key}${entry.value ? ' (muted)' : ''}'),
                  avatar: Icon(
                    entry.value ? Icons.volume_off : Icons.volume_up,
                    size: 16,
                  ),
                  onPressed: () {
                    setState(() {
                      _voiceMuted[entry.key] = !entry.value;
                    });
                  },
                  onDeleted: () {
                    setState(() {
                      _voiceMuted.remove(entry.key);
                    });
                  },
                  deleteIcon: const Icon(Icons.close, size: 16),
                );
              }).toList(),
            ),
          ),
        Container(
          color: theme.colorScheme.primaryContainer,
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${selectedServer!.name} / ${channel.name}',
                style: theme.textTheme.titleLarge,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () => setState(() {}),
              ),
            ],
          ),
        ),
        Expanded(
          child: FutureBuilder<List<dynamic>>(
            future: ChatService.instance.messagesFor(
              selectedServer!.id,
              selectedChannelId!,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Text('Chat load error: ${snapshot.error}');
              }
              final messages = snapshot.data ?? [];
              if (messages.isEmpty) {
                return const Center(
                  child: Text('No chat yet. Start typing below.'),
                );
              }
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _scrollToEnd(_serverChatScrollController);
              });
              return ListView.builder(
                controller: _serverChatScrollController,
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
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inlineMessageController,
                  decoration: const InputDecoration(
                    hintText: 'Type a message...',
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: () async {
                  final text = _inlineMessageController.text.trim();
                  if (text.isEmpty) return;
                  await ChatService.instance.sendMessage(
                    selectedServer!.id,
                    selectedChannelId!,
                    'you',
                    text,
                  );
                  if (ChatService.instance.messageMentions('you', text)) {
                    await SoundService.instance.playMention();
                  } else {
                    await SoundService.instance.playSend();
                  }
                  _inlineMessageController.clear();
                  setState(() {});
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMainArea(ThemeData theme) {
    switch (_mainView) {
      case MainView.torrents:
        return _buildTorrentsArea(theme);
      case MainView.messages:
        return _buildMessagesArea(theme);
      case MainView.server:
        return _buildServerChatArea(theme);
      case MainView.dashboard:
        return _buildDashboard(theme);
    }
  }

  Widget _buildDashboard(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Dashboard', style: theme.textTheme.headlineMedium),
            const SizedBox(height: 10),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quick actions',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.storage),
                          label: const Text('Torrents'),
                          onPressed: () => setState(() {
                            _mobileNavIndex = 1;
                          }),
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.chat),
                          label: const Text('Messaging'),
                          onPressed: () => setState(() {
                            _mobileNavIndex = 2;
                          }),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Desktop settings',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SwitchListTile(
                      title: const Text('Enable system tray icon'),
                      value: useSystemTray,
                      onChanged: _toggleSystemTray,
                    ),
                    SwitchListTile(
                      title: const Text('Minimize to tray on close'),
                      value: minimizeToTrayOnClose,
                      onChanged: useSystemTray ? _toggleMinimizeToTray : null,
                    ),
                    SwitchListTile(
                      title: const Text('Launch on startup'),
                      value: launchOnStartup,
                      onChanged: _toggleLaunchOnStartup,
                    ),
                    SwitchListTile(
                      title: const Text('Use dark theme'),
                      value: ThemeService.instance.themeMode == ThemeMode.dark,
                      onChanged: (dark) async {
                        await ThemeService.instance.setThemeMode(
                          dark ? ThemeMode.dark : ThemeMode.light,
                        );
                        setState(() {});
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Enable sound effects'),
                      value: SettingsService.instance.soundEffectsEnabled,
                      onChanged: (enabled) async {
                        await SettingsService.instance.setSoundEffectsEnabled(
                          enabled,
                        );
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Data status',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<int>(
                      future: TorrentService.instance.allTorrents().then(
                        (list) => list.length,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Text('Loading Torrent state...');
                        }
                        if (snapshot.hasError) {
                          return Text('DB error: ${snapshot.error}');
                        }
                        return Text('Torrents in DB: ${snapshot.data ?? 0}');
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Welcome to the VaultTheSpire full experience.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = MediaQuery.of(context).size.width < 760;

    if (isMobile) {
      final pages = [
        _buildMainArea(theme),
        _buildTorrentsArea(theme),
        _buildMessagesArea(theme),
        _buildServerPanel(theme),
      ];

      return Scaffold(
        body: SafeArea(child: pages[_mobileNavIndex]),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _mobileNavIndex,
          onTap: (value) => setState(() {
            _mobileNavIndex = value;
          }),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(
              icon: Icon(Icons.storage),
              label: 'Torrents',
            ),
            BottomNavigationBarItem(icon: Icon(Icons.chat), label: 'Messages'),
            BottomNavigationBarItem(icon: Icon(Icons.cloud), label: 'Servers'),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          _buildServerPanel(theme),
          Expanded(child: _buildMainArea(theme)),
        ],
      ),
    );
  }
}
