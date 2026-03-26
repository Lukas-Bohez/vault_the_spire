import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vault_the_spire/services/sound_service.dart';
import 'package:vault_the_spire/services/identity_service.dart';
import 'package:vault_the_spire/services/settings_service.dart';
import 'package:vault_the_spire/services/chat_service.dart';
import 'package:vault_the_spire/services/theme_service.dart';
import 'package:vault_the_spire/services/tray_service.dart';
import 'package:vault_the_spire/services/server_service.dart';
import 'package:vault_the_spire/models/chat_message.dart';
import 'package:vault_the_spire/models/conversation.dart';
import 'package:vault_the_spire/models/dm_message.dart';
import 'package:vault_the_spire/models/chat_user.dart';
import 'package:vault_the_spire/models/server.dart';
import 'package:vault_the_spire/models/torrent.dart';
import 'package:vault_the_spire/db/dm_messages_dao.dart';
import 'package:vault_the_spire/db/users_dao.dart';
import 'package:vault_the_spire/services/startup_service.dart';
import 'package:vault_the_spire/constants.dart';
import 'package:vault_the_spire/services/torrent_engine_service.dart';
import 'package:vault_the_spire/services/torrent_service.dart';
import 'package:vault_the_spire/screens/about_screen.dart';
import 'package:vault_the_spire/screens/browser_screen.dart';
import 'package:vault_the_spire/screens/settings_screen.dart';
import 'package:vault_the_spire/screens/torrent_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum MainView { dashboard, torrents, messages, server, browser }

enum TorrentSortMode { reputation, seeders, leechers }

class _HomeScreenState extends State<HomeScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  bool useSystemTray = false;
  bool minimizeToTrayOnClose = false;
  bool launchOnStartup = false;
  bool usePersistentSidebar = false;
  MainView _mainView = MainView.dashboard;
  ServerModel? selectedServer;
  String? selectedChannelId;
  int _mobileNavIndex = 0;
  String _currentUser = 'you';
  String? _currentUserId;
  String? _selectedConversationId;
  String _selectedDmPeer = '';
  String _dmSearchQuery = '';
  String _selectedThreadMessageId = '';
  ChatMessage? _dmReplyTarget;
  bool _inVoiceChannel = false;
  String _voiceChannelServer = '';

  String _downloadDestination = '';
  TorrentSortMode _sortMode = TorrentSortMode.reputation;
  final Map<String, TorrentEngineStatus> _engineStatuses = {};
  StreamSubscription<TorrentEngineStatus>? _engineSubscription;
  final List<Conversation> _dmConversations = [];
  final List<DmMessage> _dmMessages = [];
  final Map<String, String> _conversationPeer = {};
  final Map<String, String> _dmUserNames = {};
  final Map<String, int> _dmUnread = <String, int>{};
  final Map<String, bool> _voiceMuted = <String, bool>{};
  final TextEditingController _serverNameController = TextEditingController();
  final TextEditingController _inviteCodeController = TextEditingController();
  final TextEditingController _channelNameController = TextEditingController();
  final TextEditingController _torrentInputController = TextEditingController();
  final TextEditingController _dmPeerController = TextEditingController();
  final FocusNode _hotkeyFocusNode = FocusNode();
  final FocusNode _dmMessageFocusNode = FocusNode();
  final FocusNode _serverMessageFocusNode = FocusNode();
  final TextEditingController _dmMessageController = TextEditingController();
  final TextEditingController _inlineMessageController =
      TextEditingController();
  final TextEditingController _identityNameController = TextEditingController();
  final ScrollController _serverChatScrollController = ScrollController();
  final ScrollController _dmChatScrollController = ScrollController();

  @override
  void dispose() {
    _serverNameController.dispose();
    _inviteCodeController.dispose();
    _channelNameController.dispose();
    _torrentInputController.dispose();
    _dmPeerController.dispose();
    _dmMessageController.dispose();
    _inlineMessageController.dispose();
    _identityNameController.dispose();
    _serverChatScrollController.dispose();
    _dmChatScrollController.dispose();
    _hotkeyFocusNode.dispose();
    _dmMessageFocusNode.dispose();
    _serverMessageFocusNode.dispose();
    if (_currentUser.isNotEmpty) {
      ChatService.instance.setUserStatus(_currentUser, UserStatus.offline);
    }
    _engineSubscription?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    useSystemTray = SettingsService.instance.useSystemTray;
    minimizeToTrayOnClose = SettingsService.instance.minimizeToTrayOnClose;
    launchOnStartup = SettingsService.instance.launchOnStartup;
    usePersistentSidebar = SettingsService.instance.usePersistentSidebar;
    _downloadDestination = SettingsService.instance.downloadDestination;

    _sortMode =
        TorrentSortMode.values[SettingsService.instance.torrentSortMode.clamp(
          0,
          TorrentSortMode.values.length - 1,
        )];

    if (IdentityService.instance.identity != null) {
      _identityNameController.text =
          IdentityService.instance.identity?.displayName ?? '';
    }

    ServerService.instance.init().then((_) {
      setState(() {});
    });

    _engineSubscription = TorrentEngineService.instance.statusStream.listen((
      status,
    ) {
      if (!mounted) return;
      setState(() {
        _engineStatuses[status.torrentId] = status;
      });
    });

    _loadDmConversations();
  }

  Future<void> _loadDmConversations() async {
    final displayName = IdentityService.instance.identity?.displayName?.trim();
    _currentUser = (displayName == null || displayName.isEmpty)
        ? 'you'
        : displayName;

    await ChatService.instance.setUserStatus(_currentUser, UserStatus.online);

    final currentUser = await UsersDao.instance.getUserByName(_currentUser);
    if (currentUser == null) {
      // should not happen, but ensure user exists.
      await ChatService.instance.setUserStatus(_currentUser, UserStatus.online);
    }

    final convos = await ChatService.instance.conversationsFor(_currentUser);
    final peerMap = <String, String>{};
    final unreadMap = <String, int>{};
    final currentUserInfo = await UsersDao.instance.getUserByName(_currentUser);
    _currentUserId = currentUserInfo?.id;

    for (final c in convos) {
      final peerId = c.participant1Id == currentUserInfo?.id
          ? c.participant2Id
          : c.participant1Id;
      final peer = await UsersDao.instance.getUserById(peerId);
      peerMap[c.id] = peer?.username ?? '?';
      if (peer != null) {
        _dmUserNames[peer.id] = peer.username;
      }

      if (currentUserInfo != null) {
        _dmUserNames[currentUserInfo.id] = currentUserInfo.username;
      }

      final unread = await DmMessagesDao.instance.getUnreadCountForConversation(
        c.id,
        currentUserInfo?.id ?? '',
      );
      unreadMap[c.id] = unread;
    }

    if (!mounted) return;
    setState(() {
      _dmConversations.clear();
      _dmConversations.addAll(convos);
      _conversationPeer
        ..clear()
        ..addAll(peerMap);
      _dmUnread
        ..clear()
        ..addAll(unreadMap);
      if (_selectedConversationId == null && _dmConversations.isNotEmpty) {
        _selectedConversationId = _dmConversations.first.id;
        _selectedDmPeer = _conversationPeer[_selectedConversationId] ?? '';
      }
    });
  }

  Future<void> _loadSelectedConversationMessages() async {
    if (_selectedConversationId == null) return;
    final convo = _dmConversations.firstWhere(
      (c) => c.id == _selectedConversationId,
      orElse: () => throw StateError('Selected conversation not found'),
    );

    final messages = await ChatService.instance.getConversationMessages(
      convo,
      limit: 100,
    );
    await ChatService.instance.markConversationRead(convo.id, _currentUser);

    if (!mounted) return;
    setState(() {
      _dmMessages.clear();
      _dmMessages.addAll(messages);
      _dmUnread[convo.id] = 0;
    });
    _scrollToEnd(_dmChatScrollController, animate: true);
  }

  void _selectConversation(Conversation convo) async {
    _selectedConversationId = convo.id;
    _selectedDmPeer = _conversationPeer[convo.id] ?? '';
    await ChatService.instance.markConversationRead(convo.id, _currentUser);
    await _loadDmConversations();
    await _loadSelectedConversationMessages();
  }

  String _peerNameForConversation(Conversation convo) {
    return _conversationPeer[convo.id] ?? '?';
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

  Future<void> _renameServer(BuildContext context, ServerModel server) async {
    final messenger = ScaffoldMessenger.of(context);
    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final tmp = TextEditingController(text: server.name);
        return AlertDialog(
          title: const Text('Rename server'),
          content: TextField(controller: tmp),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(tmp.text.trim()),
              child: const Text('Rename'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;

    if (newName != null && newName.isNotEmpty) {
      try {
        await ServerService.instance.renameServer(server.id, newName);
        if (selectedServer?.id == server.id) {
          selectedServer = server.copyWith(name: newName);
        }
        setState(() {});
        messenger.showSnackBar(
          SnackBar(content: Text('Server renamed to: $newName')),
        );
      } catch (error) {
        messenger.showSnackBar(
          SnackBar(content: Text('Failed to rename server: $error')),
        );
      }
    }
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

  Future<void> _togglePersistentSidebar(bool value) async {
    await SettingsService.instance.setUsePersistentSidebar(value);
    setState(() {
      usePersistentSidebar = value;
    });
  }

  Future<void> _saveIdentityName() async {
    final messenger = ScaffoldMessenger.of(context);
    final trimmed = _identityNameController.text.trim();
    final newName = trimmed.isEmpty ? 'You' : trimmed;
    await IdentityService.instance.setDisplayName(newName);
    if (!mounted) return;
    setState(() {});
    messenger.showSnackBar(
      const SnackBar(content: Text('Identity name updated')),
    );
  }

  Future<void> _copyToClipboard(
    String text,
    String message,
    BuildContext ctx,
  ) async {
    final messenger = ScaffoldMessenger.of(ctx);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _chooseDownloadDirectory() async {
    try {
      final result = await FilePicker.platform.getDirectoryPath();
      if (result != null && result.isNotEmpty) {
        setState(() {
          _downloadDestination = result;
        });
        await SettingsService.instance.setDownloadDestination(result);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Destination set: $_downloadDestination')),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Destination selection failed: $error')),
      );
    }
  }

  Future<void> _exportIdentity() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final jsonString = await IdentityService.instance.exportIdentity();
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Export Identity'),
            content: SelectableText(jsonString),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Close'),
              ),
              TextButton(
                onPressed: () {
                  _copyToClipboard(jsonString, 'Identity JSON copied', context);
                  Navigator.of(context).pop();
                },
                child: const Text('Copy'),
              ),
            ],
          );
        },
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Export failed: $error')));
    }
  }

  Future<void> _importIdentity() async {
    final result = await showDialog<String?>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Import Identity JSON'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Paste identity JSON here',
            ),
            maxLines: 6,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(controller.text.trim());
              },
              child: const Text('Import'),
            ),
          ],
        );
      },
    );

    if (result == null || result.isEmpty) return;

    try {
      await IdentityService.instance.importIdentity(result);
      if (!mounted) return;
      _identityNameController.text =
          IdentityService.instance.identity?.displayName ?? 'You';
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Identity imported successfully')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $error')));
    }
  }

  void _scrollToEnd(ScrollController controller, {bool animate = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!controller.hasClients) return;
      if (animate) {
        controller.animateTo(
          controller.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else {
        controller.jumpTo(controller.position.maxScrollExtent);
      }
    });
  }

  Future<void> _sendDmMessage() async {
    if (_selectedConversationId == null) return;
    final text = _dmMessageController.text.trim();
    if (text.isEmpty) return;
    final conversation = _dmConversations.firstWhere(
      (c) => c.id == _selectedConversationId,
      orElse: () => throw StateError('Selected conversation not found'),
    );
    final peer = _peerNameForConversation(conversation);

    try {
      await ChatService.instance.sendDirectMessage(_currentUser, peer, text);
      await _loadDmConversations();
      await _loadSelectedConversationMessages();
      _dmMessageController.clear();
      _dmMessageFocusNode.requestFocus();
      _scrollToEnd(_dmChatScrollController, animate: true);
      if (!mounted) return;
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('DM send failed: $error')));
    }
  }

  Future<void> _sendServerMessage() async {
    if (selectedServer == null || selectedChannelId == null) return;
    final text = _inlineMessageController.text.trim();
    if (text.isEmpty) return;

    try {
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
      _serverMessageFocusNode.requestFocus();
      _scrollToEnd(_serverChatScrollController, animate: true);
      if (!mounted) return;
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Send failed: $error')));
    }
  }

  void _markDmRead(String peer) {
    setState(() {
      _dmUnread[peer] = 0;
    });
  }

  Widget _buildModuleNav(ThemeData theme) {
    final tabs = [
      {
        'icon': Icons.dashboard,
        'label': 'Dashboard',
        'view': MainView.dashboard,
      },
      {'icon': Icons.storage, 'label': 'Torrents', 'view': MainView.torrents},
      {'icon': Icons.chat, 'label': 'Messages', 'view': MainView.messages},
      {'icon': Icons.cloud, 'label': 'Servers', 'view': MainView.server},
      {'icon': Icons.web, 'label': 'Browser', 'view': MainView.browser},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.onSurface.withAlpha((0.08 * 255).round()),
          ),
        ),
      ),
      child: Row(
        children: tabs.map((tab) {
          final view = tab['view'] as MainView;
          final selected = _mainView == view;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                elevation: selected ? 0 : 0,
                backgroundColor: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surface,
                foregroundColor: selected
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onSurface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                side: BorderSide(
                  color: selected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurface.withAlpha(
                          (0.15 * 255).round(),
                        ),
                ),
              ),
              icon: Icon(tab['icon'] as IconData, size: 18),
              label: Text(tab['label'] as String),
              onPressed: () => setState(() {
                _mainView = view;
              }),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMainContent(ThemeData theme) {
    // IndexedStack keeps every tab widget alive in the tree even when not
    // visible — the BrowserScreen (WebView) is never torn down when the user
    // switches away, so it stays exactly on the page they left.
    final views = MainView.values;
    return IndexedStack(
      index: views.indexOf(_mainView),
      children: [
        _buildDashboard(theme),
        _buildTorrentsArea(theme),
        _buildMessagesArea(theme),
        _buildServerChatArea(theme),
        _buildBrowserArea(theme),
      ],
    );
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

  Future<void> _showCreateTorrentSourceDialog() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Create torrent from'),
          content: const Text('Choose a file or directory to create torrent.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('file'),
              child: const Text('File'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('directory'),
              child: const Text('Folder'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
    if (choice == 'file') {
      await _pickFileAndCreateTorrent();
    } else if (choice == 'directory') {
      await _pickDirectoryAndCreateTorrent();
    }
  }

  Future<void> _pickFileAndCreateTorrent() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

    try {
      await TorrentService.instance.addTorrentFromPath(path);
      await _refreshLocalTorrents();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Torrent created from file and added.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to create torrent: $e')));
    }
  }

  Future<void> _pickDirectoryAndCreateTorrent() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null || path.isEmpty) return;

    try {
      await TorrentService.instance.addTorrentFromPath(path);
      await _refreshLocalTorrents();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Torrent created from folder and added.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to create torrent: $e')));
    }
  }

  Future<void> _addTorrentFromInput() async {
    final text = _torrentInputController.text.trim();
    if (text.isEmpty) return;

    try {
      if (text.startsWith('magnet:')) {
        await TorrentService.instance.addTorrentFromMagnetLink(text);
      } else if (text.toLowerCase().endsWith('.torrent')) {
        await TorrentService.instance.addTorrentFromTorrentFile(text);
      } else {
        // If path exists, add from directory or file path.
        final path = text;
        if (await File(path).exists() || await Directory(path).exists()) {
          await TorrentService.instance.addTorrentFromPath(path);
        } else {
          throw FormatException(
            'Invalid torrent input. Use magnet link or existing path',
          );
        }
      }

      _torrentInputController.clear();
      await SoundService.instance.playNotification();
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Torrent added successfully')),
      );
    } on TorrentAlreadyExistsException catch (error) {
      final existing = await TorrentService.instance.getTorrentById(
        error.torrentId,
      );
      if (!mounted) return;

      if (existing != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Torrent already exists. Refreshing and opening details.',
            ),
          ),
        );
        await TorrentEngineService.instance.forceRefresh(existing.id);
        try {
          Navigator.of(
            context,
          ).pushNamed('/torrent_detail', arguments: existing);
        } catch (_) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => TorrentDetailScreen(torrent: existing),
            ),
          );
        }
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Torrent exists but could not open: ${error.torrentId}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add torrent: $error')));
    }
  }

  Future<void> _showSeedingSettings() async {
    final messenger = ScaffoldMessenger.of(context);
    final torrents = await TorrentService.instance.allTorrents();
    if (!mounted) return;
    if (torrents.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No torrents to configure yet')),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Seeding Settings'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: torrents.map((torrent) {
                  final ratioController = TextEditingController(
                    text: torrent.maxSeedRatio?.toStringAsFixed(2) ?? '',
                  );
                  bool deleteAfter = torrent.deleteAfterRatioReached;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            torrent.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: ratioController,
                            decoration: const InputDecoration(
                              labelText: 'Max seed ratio (e.g., 2.0)',
                              isDense: true,
                            ),
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            onSubmitted: (value) async {
                              final ratio = double.tryParse(value);
                              if (ratio == null) return;
                              await TorrentService.instance.setSeedRatioLimit(
                                torrent.id,
                                ratio,
                              );
                              setState(() {});
                            },
                          ),
                          Row(
                            children: [
                              Checkbox(
                                value: deleteAfter,
                                onChanged: (value) async {
                                  if (value == null) return;
                                  await TorrentService.instance
                                      .setDeleteAfterRatioReached(
                                        torrent.id,
                                        value,
                                      );
                                  setState(() {});
                                },
                              ),
                              const Text('Delete after reaching ratio'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildServerPanel(ThemeData theme, {bool inDrawer = false}) {
    final identity = IdentityService.instance.identity;
    return Container(
      width: inDrawer ? null : 320,
      constraints: inDrawer
          ? const BoxConstraints(minWidth: 280, maxWidth: 520)
          : const BoxConstraints(
              minWidth: 320,
              maxWidth: 320,
              minHeight: double.infinity,
            ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: inDrawer
            ? null
            : Border(
                right: BorderSide(
                  color: theme.colorScheme.outline.withAlpha(
                    (0.15 * 255).round(),
                  ),
                  width: 1.2,
                ),
              ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Image.asset(
                  kAppFavicon192,
                  width: 38,
                  height: 38,
                  fit: BoxFit.cover,
                ),
                const SizedBox(width: 8),
                Text(
                  'VaultTheSpire',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Navigate via top tabs',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 12),
            Text('Connected', style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            const Text(
              'quizthespire.com',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 14),
            Text('Identity', style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    identity != null ? identity.nodeId : 'No node',
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy identity',
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: identity == null
                      ? null
                      : () {
                          _copyToClipboard(
                            identity.nodeId,
                            'Identity copied',
                            context,
                          );
                        },
                ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: identity == null
                  ? null
                  : () {
                      _copyToClipboard(
                        identity.nodeId,
                        'Identity shared to clipboard',
                        context,
                      );
                    },
              icon: const Icon(Icons.share),
              label: const Text('Share identity'),
            ),
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
                    final messenger = ScaffoldMessenger.of(context);
                    if (value == 'invite') {
                      final inviteCode = ServerService.instance.generateInvite(
                        server,
                      );
                      messenger.showSnackBar(
                        SnackBar(content: Text('Invite code: $inviteCode')),
                      );
                    } else if (value == 'delete') {
                      await ServerService.instance.removeServer(server.id);
                      if (selectedServer?.id == server.id) {
                        selectedServer = null;
                        selectedChannelId = null;
                      }
                      setState(() {});
                    } else if (value == 'rename') {
                      await _renameServer(context, server);
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
            if (selectedServer != null) ...[
              Text('Invite code', style: theme.textTheme.labelMedium),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      ServerService.instance.generateInvite(selectedServer!),
                      style: const TextStyle(fontFamily: 'monospace'),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: 'Copy invite code',
                    onPressed: () {
                      final inviteCode = ServerService.instance.generateInvite(
                        selectedServer!,
                      );
                      Clipboard.setData(ClipboardData(text: inviteCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Invite code copied to clipboard!'),
                          behavior: SnackBarBehavior.floating,
                          duration: Duration(milliseconds: 1200),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
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
                if (!mounted) return;
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
                elevation: 2,
                color: _inVoiceChannel
                    ? theme.colorScheme.tertiaryContainer
                    : theme.colorScheme.surfaceContainerHighest,
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.mic, size: 22),
                  title: Text(
                    _inVoiceChannel ? 'Voice channel active' : 'Voice chat',
                    style: theme.textTheme.titleSmall,
                  ),
                  subtitle: Text(
                    _inVoiceChannel
                        ? _voiceChannelServer
                        : 'Not in voice channel',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: ElevatedButton(
                    onPressed: () {
                      _toggleVoiceChannel(
                        selectedServer!.id,
                        selectedServer!.name,
                      );
                    },
                    child: Text(_inVoiceChannel ? 'Leave' : 'Join'),
                  ),
                ),
              ),
              if (_inVoiceChannel) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: _voiceMuted.entries.map((entry) {
                    return InputChip(
                      label: Text(
                        '${entry.key}${entry.value ? ' (muted)' : ''}',
                      ),
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
                const SizedBox(height: 6),
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
              ],
            ],
            const SizedBox(height: 10),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.privacy_tip),
              title: const Text('Privacy Policy'),
              subtitle: const Text(kPrivacyPolicyUrl),
              trailing: IconButton(
                icon: const Icon(Icons.copy),
                tooltip: 'Copy privacy policy URL',
                onPressed: () {
                  Clipboard.setData(
                    const ClipboardData(text: kPrivacyPolicyUrl),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Privacy policy URL copied')),
                  );
                },
              ),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const AboutScreen()),
                );
              },
            ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const AboutScreen()),
                );
              },
              icon: const Icon(Icons.info_outline),
              label: const Text('Open About / Data Safety'),
            ),
            // Removed integrated browser quick action (now in dedicated tab)
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildTorrentsArea(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('My Torrents', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Expanded(child: _buildLocalTorrentTab(theme)),
        ],
      ),
    );
  }

  Future<void> _refreshLocalTorrents() async {
    setState(() {});
  }

  String _formatBytes(int? bytes) {
    if (bytes == null || bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    double size = bytes.toDouble();
    int index = 0;
    while (size >= 1024 && index < suffixes.length - 1) {
      size /= 1024;
      index++;
    }
    return '${size.toStringAsFixed(1)} ${suffixes[index]}';
  }

  Widget _buildDownloadDestinationCard(ThemeData theme) {
    return Card(
      elevation: 1,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _downloadDestination.isEmpty
                    ? 'No download destination selected'
                    : 'Download destination: $_downloadDestination',
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _chooseDownloadDirectory,
              child: const Text('Choose folder'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocalTorrentTab(ThemeData theme) {
    return FutureBuilder<List<dynamic>>(
      future: TorrentService.instance.allTorrents(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Text('Error loading torrents: ${snapshot.error}');
        }
        final torrents = snapshot.data ?? [];

        final sortedTorrents = List<TorrentModel>.from(torrents);
        sortedTorrents.sort((a, b) {
          switch (_sortMode) {
            case TorrentSortMode.seeders:
              return b.seeders.compareTo(a.seeders);
            case TorrentSortMode.leechers:
              return b.leechers.compareTo(a.leechers);
            case TorrentSortMode.reputation:
              return b.reputation.compareTo(a.reputation);
          }
        });

        return RefreshIndicator(
          onRefresh: _refreshLocalTorrents,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: _buildDownloadDestinationCard(theme),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _torrentInputController,
                        decoration: const InputDecoration(
                          hintText: 'Magnet link or file path',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _addTorrentFromInput,
                      child: const Text('Add'),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.create_new_folder),
                  label: const Text('Create torrent from file/folder'),
                  onPressed: _showCreateTorrentSourceDialog,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Text('Sort by:'),
                    const SizedBox(width: 8),
                    DropdownButton<TorrentSortMode>(
                      value: _sortMode,
                      onChanged: (value) {
                        if (value != null) {
                          setState(() {
                            _sortMode = value;
                          });
                          SettingsService.instance.setTorrentSortMode(
                            TorrentSortMode.values.indexOf(value),
                          );
                        }
                      },
                      items: TorrentSortMode.values
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item.toString().split('.').last),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text('Total torrents: ${sortedTorrents.length}'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: torrents.isEmpty
                    ? const Center(child: Text('No torrents yet.'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: torrents.length,
                        itemBuilder: (context, index) {
                          final torrent = torrents[index];
                          final progress =
                              (torrent.totalSize != null &&
                                  torrent.totalSize! > 0)
                              ? (torrent.bytesDown / torrent.totalSize!).clamp(
                                  0.0,
                                  1.0,
                                )
                              : 0.0;
                          final engineStatus = _engineStatuses[torrent.id];

                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            child: ListTile(
                              title: Text(torrent.name ?? 'Unnamed'),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${torrent.status ?? 'unknown'} • ${torrent.totalSize != null ? '${(progress * 100).toStringAsFixed(1)}%' : 'No size'}',
                                  ),
                                  if (torrent.totalSize != null)
                                    LinearProgressIndicator(value: progress),
                                  Text(
                                    'Size: ${_formatBytes(torrent.totalSize)}',
                                  ),
                                  Text(
                                    'Seeders: ${engineStatus?.seeders ?? torrent.seeders}, '
                                    'Leechers: ${engineStatus?.leechers ?? torrent.leechers}, '
                                    'Connected: ${engineStatus?.peers ?? 0}',
                                  ),
                                  if (engineStatus != null) ...[
                                    Text(
                                      'Status: ${engineStatus.statusMessage}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      'DL: ${engineStatus.downloadSpeed.toStringAsFixed(1)} B/s • UL: ${engineStatus.uploadSpeed.toStringAsFixed(1)} B/s • Peer progress: ${(engineStatus.progress * 100).toStringAsFixed(1)}%',
                                    ),
                                  ],
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (torrent.status != 'downloading' &&
                                      torrent.status != 'completed')
                                    IconButton(
                                      icon: const Icon(Icons.play_arrow),
                                      onPressed: () async {
                                        final messenger = ScaffoldMessenger.of(
                                          context,
                                        );
                                        if (_downloadDestination.isEmpty) {
                                          await _chooseDownloadDirectory();
                                          if (_downloadDestination.isEmpty)
                                            return;
                                        }
                                        try {
                                          await TorrentService.instance
                                              .downloadTorrent(
                                                torrent.id,
                                                _downloadDestination,
                                              );
                                        } catch (e, st) {
                                          if (!mounted) return;
                                          debugPrint(
                                            'Download failed stack (play): $st',
                                          );
                                          messenger.showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Download failed: $e',
                                              ),
                                            ),
                                          );
                                        }
                                        setState(() {});
                                      },
                                    ),
                                  if (torrent.status == 'downloading') ...[
                                    IconButton(
                                      icon: const Icon(Icons.pause),
                                      tooltip: 'Pause',
                                      onPressed: () async {
                                        TorrentEngineService.instance
                                            .stopTorrent(torrent.id);
                                        await TorrentService.instance
                                            .updateTorrentStatus(
                                              torrent.id,
                                              'paused',
                                            );
                                        setState(() {});
                                      },
                                    ),
                                    const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ],
                                  if (torrent.status == 'paused' ||
                                      torrent.status == 'queued')
                                    IconButton(
                                      icon: const Icon(Icons.play_arrow),
                                      tooltip: 'Resume',
                                      onPressed: () async {
                                        final messenger = ScaffoldMessenger.of(
                                          context,
                                        );
                                        if (_downloadDestination.isEmpty) {
                                          await _chooseDownloadDirectory();
                                          if (_downloadDestination.isEmpty)
                                            return;
                                        }
                                        try {
                                          await TorrentService.instance
                                              .downloadTorrent(
                                                torrent.id,
                                                _downloadDestination,
                                              );
                                        } catch (e, st) {
                                          if (!mounted) return;
                                          debugPrint(
                                            'Download failed stack (resume): $st',
                                          );
                                          messenger.showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Download failed: $e',
                                              ),
                                            ),
                                          );
                                        }
                                        setState(() {});
                                      },
                                    ),
                                  IconButton(
                                    icon: const Icon(Icons.delete),
                                    tooltip: 'Remove torrent',
                                    onPressed: () async {
                                      await TorrentService.instance
                                          .removeTorrent(torrent.id);
                                      setState(() {
                                        // Optionally remove from local list if present
                                      });
                                    },
                                  ),
                                  if (torrent.status == 'completed')
                                    const Icon(
                                      Icons.check_circle,
                                      color: Colors.green,
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMessagesArea(ThemeData theme) {
    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Direct Messages',
                  style: theme.textTheme.headlineMedium,
                ),
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
                                Navigator.of(
                                  context,
                                ).pop(controller.text.trim());
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
                      final conversation = await ChatService.instance
                          .getOrCreateConversation(_currentUser, username);
                      await _loadDmConversations();
                      _selectConversation(conversation);
                    } catch (error) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to start DM: $error')),
                      );
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
                              final conversation = await ChatService.instance
                                  .getOrCreateConversation(
                                    _currentUser,
                                    peerName,
                                  );
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
                                final peer = _peerNameForConversation(
                                  conversation,
                                );
                                if (_dmSearchQuery.isNotEmpty &&
                                    !peer.toLowerCase().contains(
                                      _dmSearchQuery,
                                    )) {
                                  return const SizedBox.shrink();
                                }
                                final unread = _dmUnread[conversation.id] ?? 0;
                                final isSelected =
                                    conversation.id == _selectedConversationId;
                                final isOnline = ChatService.instance
                                    .isUserOnline(peer);
                                return ListTile(
                                  selected: isSelected,
                                  selectedTileColor:
                                      theme.colorScheme.primaryContainer,
                                  leading: CircleAvatar(
                                    child: Text(
                                      peer.isNotEmpty
                                          ? peer[0].toUpperCase()
                                          : '?',
                                    ),
                                  ),
                                  title: Text(peer),
                                  subtitle: Text(
                                    isOnline ? 'online' : 'offline',
                                  ),
                                  trailing: unread > 0
                                      ? CircleAvatar(
                                          radius: 10,
                                          backgroundColor: Colors.red,
                                          child: Text(
                                            '$unread',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                            ),
                                          ),
                                        )
                                      : null,
                                  onTap: () =>
                                      _selectConversation(conversation),
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
    final isPeerTyping =
        _selectedConversationId != null &&
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _selectedConversationId == null
              ? Center(
                  child: Text(
                    'Pick a conversation on left',
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              : FutureBuilder<List<DmMessage>>(
                  future: _loadSelectedConversationMessages().then(
                    (_) => _dmMessages,
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Unable to load messages: ${snapshot.error}',
                        ),
                      );
                    }
                    final messages = snapshot.data ?? [];
                    WidgetsBinding.instance.addPostFrameCallback(
                      (_) =>
                          _scrollToEnd(_dmChatScrollController, animate: true),
                    );
                    if (messages.isEmpty) {
                      return const Center(
                        child: Text('No messages yet. Start the conversation.'),
                      );
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
                          alignment: isMe
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            constraints: const BoxConstraints(maxWidth: 520),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isMe
                                  ? theme.colorScheme.primaryContainer
                                  : theme.colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  sender,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(m.content),
                                const SizedBox(height: 6),
                                Text(
                                  '${m.timestamp.hour.toString().padLeft(2, "0")}:${m.timestamp.minute.toString().padLeft(2, "0")}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 10,
                                  ),
                                ),
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
            child: Text(
              '${_peerNameForConversation(_dmConversations.firstWhere((c) => c.id == _selectedConversationId!))} is typing...',
              style: const TextStyle(color: Colors.green),
            ),
          ),
        const SizedBox(height: 8),
        RawKeyboardListener(
          focusNode: _dmMessageFocusNode,
          onKey: (event) async {
            if (event is RawKeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.enter) {
              if (event.isShiftPressed) {
                final selection = _dmMessageController.selection;
                final text = _dmMessageController.text;
                final result = text.replaceRange(
                  selection.start,
                  selection.end,
                  '\\n',
                );
                _dmMessageController.value = TextEditingValue(
                  text: result,
                  selection: TextSelection.collapsed(
                    offset: selection.start + 1,
                  ),
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
                        _dmConversations.firstWhere(
                          (c) => c.id == _selectedConversationId!,
                        ),
                      );
                      final topic = ChatService.dmSwarmTopic(
                        _currentUser,
                        peer,
                      );
                      ChatService.instance.broadcastTypingStatus(
                        topic,
                        _currentUser,
                        value.isNotEmpty,
                      );
                    }
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.send),
                onPressed: _selectedConversationId == null
                    ? null
                    : _sendDmMessage,
              ),
            ],
          ),
        ),
      ],
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
              children: [
                Expanded(
                  child: Text(
                    'Voice chat active: $_voiceChannelServer',
                    style: theme.textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
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
              Expanded(
                child: Text(
                  '${selectedServer!.name} / ${channel.name}',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Create channel',
                    icon: const Icon(Icons.add),
                    onPressed: () async {
                      final channelName = await showDialog<String>(
                        context: context,
                        builder: (context) {
                          final controller = TextEditingController();
                          return AlertDialog(
                            title: const Text('New channel'),
                            content: TextFormField(
                              controller: controller,
                              decoration: const InputDecoration(
                                labelText: 'Channel name',
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
                                    Navigator.of(
                                      context,
                                    ).pop(controller.text.trim());
                                  }
                                },
                                child: const Text('Create'),
                              ),
                            ],
                          );
                        },
                      );

                      if (channelName != null && channelName.isNotEmpty) {
                        try {
                          final updated = await ServerService.instance
                              .addChannel(selectedServer!.id, channelName);
                          setState(() {
                            selectedServer = updated;
                            selectedChannelId = updated.channels.last.id;
                          });
                        } catch (exception) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Failed to create channel: $exception',
                              ),
                            ),
                          );
                        }
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => setState(() {}),
                  ),
                ],
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
                  final isMe = m.author == _currentUser;
                  final timestamp = m.timestamp is DateTime
                      ? m.timestamp as DateTime
                      : DateTime.tryParse(m.timestamp.toString()) ??
                            DateTime.now();

                  return Align(
                    alignment: isMe
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 520),
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isMe
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.surfaceVariant,
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(12),
                          topRight: const Radius.circular(12),
                          bottomLeft: Radius.circular(isMe ? 12 : 2),
                          bottomRight: Radius.circular(isMe ? 2 : 12),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.author,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(m.text),
                          const SizedBox(height: 6),
                          Text(
                            '${timestamp.hour.toString().padLeft(2, "0")}:${timestamp.minute.toString().padLeft(2, "0")}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: RawKeyboardListener(
            focusNode: _serverMessageFocusNode,
            onKey: (event) async {
              if (event is RawKeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.enter) {
                if (event.isShiftPressed) {
                  final selection = _inlineMessageController.selection;
                  final text = _inlineMessageController.text;
                  final result = text.replaceRange(
                    selection.start,
                    selection.end,
                    '\n',
                  );
                  _inlineMessageController.value = TextEditingValue(
                    text: result,
                    selection: TextSelection.collapsed(
                      offset: selection.start + 1,
                    ),
                  );
                } else {
                  await _sendServerMessage();
                }
              }
            },
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    focusNode: _serverMessageFocusNode,
                    controller: _inlineMessageController,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(),
                    ),
                    minLines: 1,
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: _sendServerMessage,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBrowserArea(ThemeData theme) {
    return BrowserScreen(
      inTab: true,
      initialUrl: SettingsService.instance.browserHomeUrl,
    );
  }

  Widget _buildMainArea(ThemeData theme) {
    return Column(
      children: [
        _buildModuleNav(theme),
        Expanded(child: _buildMainContent(theme)),
      ],
    );
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
                    const Text(
                      'Use the tabs above to switch between dashboard, torrents, messages, servers, and browser.',
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
                      title: const Text('Persistent sidebar'),
                      subtitle: const Text(
                        'Keeps full left panel visible on desktop',
                      ),
                      value: usePersistentSidebar,
                      onChanged: (v) => _togglePersistentSidebar(v),
                    ),
                    const Divider(),
                    TextField(
                      controller: _identityNameController,
                      decoration: const InputDecoration(
                        labelText: 'Identity display name',
                        isDense: true,
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _saveIdentityName,
                            child: const Text('Save name'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Copy node ID',
                          icon: const Icon(Icons.copy),
                          onPressed: () {
                            final nodeId =
                                IdentityService.instance.identity?.nodeId ?? '';
                            if (nodeId.isNotEmpty) {
                              _copyToClipboard(
                                nodeId,
                                'Node ID copied',
                                context,
                              );
                            }
                          },
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _exportIdentity,
                            child: const Text('Export identity'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _importIdentity,
                            child: const Text('Import identity'),
                          ),
                        ),
                      ],
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

    final editablePages = [
      _buildMainArea(theme),
      _buildTorrentsArea(theme),
      _buildMessagesArea(theme),
      _buildServerPanel(theme),
    ];

    Widget content;

    if (isMobile) {
      content = Scaffold(
        body: SafeArea(child: editablePages[_mobileNavIndex]),
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
    } else if (usePersistentSidebar) {
      content = Scaffold(
        body: Row(
          children: [
            _buildServerPanel(theme),
            Expanded(child: _buildMainArea(theme)),
          ],
        ),
      );
    } else {
      content = Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          title: const Text('VaultTheSpire'),
          leading: IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            tooltip: 'Open sidebar',
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: 'Settings',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SettingsScreen(),
                ),
              ),
            ),
          ],
        ),
        drawer: Drawer(child: _buildServerPanel(theme, inDrawer: true)),
        body: _buildMainArea(theme),
      );
    }

    return KeyboardListener(
      focusNode: _hotkeyFocusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          final isCtrl =
              HardwareKeyboard.instance.logicalKeysPressed.contains(
                LogicalKeyboardKey.controlLeft,
              ) ||
              HardwareKeyboard.instance.logicalKeysPressed.contains(
                LogicalKeyboardKey.controlRight,
              );
          final key = event.logicalKey;
          if (key == LogicalKeyboardKey.digit1 && isCtrl) {
            setState(() => _mainView = MainView.dashboard);
          } else if (key == LogicalKeyboardKey.digit2 && isCtrl) {
            setState(() => _mainView = MainView.torrents);
          } else if (key == LogicalKeyboardKey.digit3 && isCtrl) {
            setState(() => _mainView = MainView.messages);
          } else if (key == LogicalKeyboardKey.digit4 && isCtrl) {
            setState(() => _mainView = MainView.server);
          } else if (key == LogicalKeyboardKey.keyS && isCtrl) {
            _showSeedingSettings();
          }
        }
      },
      child: content,
    );
  }
}
