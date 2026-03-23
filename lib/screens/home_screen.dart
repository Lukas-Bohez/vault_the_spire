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
import 'package:vault_the_spire/models/server.dart';
import 'package:vault_the_spire/models/torrent.dart';
import 'package:vault_the_spire/services/startup_service.dart';
import 'package:vault_the_spire/constants.dart';
import 'package:vault_the_spire/services/torrent_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum MainView { dashboard, torrents, messages, server }

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
  String _selectedDmPeer = '';
  String _dmSearchQuery = '';
  String _selectedThreadMessageId = '';
  ChatMessage? _dmReplyTarget;
  bool _inVoiceChannel = false;
  String _voiceChannelServer = '';

  String _torrentSearchQuery = '';
  bool _onlineDiscoveryLoading = false;
  bool _isMinerActive = false;
  Timer? _torrentMiningTimer;
  List<TorrentModel> _discoveredTorrents = [];
  String _downloadDestination = '';
  TorrentSortMode _sortMode = TorrentSortMode.reputation;
  int _minSeeders = 0;
  final Set<String> _dmContacts = <String>{};
  final Map<String, int> _dmUnread = <String, int>{};
  final Map<String, bool> _voiceMuted = <String, bool>{};
  final TextEditingController _serverNameController = TextEditingController();
  final TextEditingController _inviteCodeController = TextEditingController();
  final TextEditingController _channelNameController = TextEditingController();
  final TextEditingController _torrentInputController = TextEditingController();
  final TextEditingController _dmPeerController = TextEditingController();
  final FocusNode _hotkeyFocusNode = FocusNode();
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
    _torrentMiningTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    useSystemTray = SettingsService.instance.useSystemTray;
    minimizeToTrayOnClose = SettingsService.instance.minimizeToTrayOnClose;
    launchOnStartup = SettingsService.instance.launchOnStartup;
    usePersistentSidebar = SettingsService.instance.usePersistentSidebar;

    if (IdentityService.instance.identity != null) {
      _identityNameController.text =
          IdentityService.instance.identity?.displayName ?? '';
    }

    ServerService.instance.init().then((_) {
      setState(() {});
    });

    _torrentMiningTimer = Timer.periodic(const Duration(seconds: 20), (
      _,
    ) async {
      if (!_isMinerActive) return;
      await _performMiningSweep();
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
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Torrent added successfully')),
      );
    } catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add torrent: $error')));
    }
  }

  Future<void> _showSeedingSettings() async {
    final messenger = ScaffoldMessenger.of(context);
    final torrents = await TorrentService.instance.allTorrents();
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

  Future<void> _performMiningSweep() async {
    final currentSearch = _torrentSearchQuery.isNotEmpty
        ? _torrentSearchQuery
        : 'trending';
    final discovered = await TorrentService.instance.discoverTorrentsOnline(
      currentSearch,
    );
    for (final torrent in discovered) {
      try {
        await TorrentService.instance.addTorrent(torrent);
      } catch (_) {
        // ignore duplicates
      }
      if (_isMinerActive && _downloadDestination.isNotEmpty) {
        TorrentService.instance
            .downloadTorrent(torrent.id, _downloadDestination)
            .catchError((_) {});
      }
    }

    setState(() {
      _discoveredTorrents.addAll(discovered);
      _discoveredTorrents = _discoveredTorrents.fold<List<TorrentModel>>([], (
        acc,
        item,
      ) {
        if (!acc.any((t) => t.id == item.id)) acc.add(item);
        return acc;
      });
    });
  }

  void _toggleMiner(bool value) {
    setState(() {
      _isMinerActive = value;
      if (!value) {
        _torrentMiningTimer?.cancel();
      } else {
        _torrentMiningTimer ??= Timer.periodic(const Duration(seconds: 20), (
          _,
        ) async {
          await _performMiningSweep();
        });
      }
    });
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
          ],
        ),
      ),
    );
  }

  Widget _buildTorrentsArea(ThemeData theme) {
    final filteredDiscovered = _discoveredTorrents
        .where((torrent) => torrent.seeders >= _minSeeders)
        .toList();

    filteredDiscovered.sort((a, b) {
      switch (_sortMode) {
        case TorrentSortMode.seeders:
          return b.seeders.compareTo(a.seeders);
        case TorrentSortMode.leechers:
          return b.leechers.compareTo(a.leechers);
        case TorrentSortMode.reputation:
        default:
          return b.reputation.compareTo(a.reputation);
      }
    });

    return Container(
      color: theme.colorScheme.surface,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Torrents', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _torrentInputController,
                  decoration: InputDecoration(
                    hintText: 'Paste magnet link or .torrent path here',
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _addTorrentFromInput(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _addTorrentFromInput,
                icon: const Icon(Icons.file_upload),
                label: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Find torrents by name or link',
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (value) => setState(() {
                    _torrentSearchQuery = value;
                  }),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () async {
                  setState(() {
                    _onlineDiscoveryLoading = true;
                  });
                  final discovered = await TorrentService.instance
                      .discoverTorrentsOnline(_torrentSearchQuery);
                  for (final torrent in discovered) {
                    await TorrentService.instance.addTorrent(torrent);
                  }
                  setState(() {
                    _discoveredTorrents = discovered;
                    _onlineDiscoveryLoading = false;
                  });
                },
                icon: _onlineDiscoveryLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: const Text('Discover online'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Card(
            elevation: 1,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
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
                  const SizedBox(height: 8),
                  Row(
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
                          }
                        },
                        items: TorrentSortMode.values.map((item) {
                          return DropdownMenuItem(
                            value: item,
                            child: Text(item.toString().split('.').last),
                          );
                        }).toList(),
                      ),
                      const SizedBox(width: 16),
                      const Text('Min seeders:'),
                      Expanded(
                        child: Slider(
                          min: 0,
                          max: 500,
                          divisions: 25,
                          value: _minSeeders.toDouble(),
                          label: '$_minSeeders',
                          onChanged: (value) {
                            setState(() {
                              _minSeeders = value.toInt();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            children: [
              ElevatedButton(
                onPressed: () => setState(() {}),
                child: const Text('Refresh'),
              ),
              OutlinedButton(
                onPressed: _showSeedingSettings,
                child: const Text('Seeding settings'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 1,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Auto mining',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Text(_isMinerActive ? 'Running' : 'Stopped'),
                  const SizedBox(width: 8),
                  Switch(value: _isMinerActive, onChanged: _toggleMiner),
                ],
              ),
            ),
          ),
          if (_downloadDestination.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text(
                'Choose a destination folder to enable auto-download',
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (filteredDiscovered.isNotEmpty) ...[
            Text('Discovered Torrents', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ...filteredDiscovered.map((torrent) {
              return ListTile(
                leading: const Icon(Icons.new_releases),
                title: Text(torrent.name),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seeders ${torrent.seeders}, Leechers ${torrent.leechers}, Rep ${torrent.reputation.toStringAsFixed(1)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (torrent.magnetLink != null)
                      Text(
                        torrent.magnetLink!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (torrent.filePath != null &&
                        torrent.filePath!.isNotEmpty)
                      Text(
                        'Destination: ${torrent.filePath}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.add),
                      tooltip: 'Add discovered torrent',
                      onPressed: () async {
                        try {
                          await TorrentService.instance.addTorrent(torrent);
                          setState(() {
                            _discoveredTorrents.remove(torrent);
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Added ${torrent.name}.')),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Already added: ${torrent.name}'),
                            ),
                          );
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.download),
                      tooltip: 'Download torrent',
                      onPressed: () async {
                        if (_downloadDestination.isEmpty) {
                          await _chooseDownloadDirectory();
                          if (_downloadDestination.isEmpty) {
                            return;
                          }
                        }

                        try {
                          await TorrentService.instance.addTorrent(torrent);
                        } catch (_) {}

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Starting download: ${torrent.name}'),
                          ),
                        );

                        TorrentService.instance
                            .downloadTorrent(torrent.id, _downloadDestination)
                            .then((_) {
                              if (!mounted) return;
                              setState(() {});
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Download complete: ${torrent.name}',
                                  ),
                                ),
                              );
                            })
                            .catchError((error) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Download failed: $error'),
                                ),
                              );
                            });
                      },
                    ),
                  ],
                ),
              );
            }),
            const Divider(),
          ],
          FutureBuilder<List<dynamic>>(
            future: _torrentSearchQuery.isEmpty
                ? TorrentService.instance.allTorrents()
                : TorrentService.instance.findTorrents(_torrentSearchQuery),
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
                    final progress =
                        (torrent.totalSize != null && torrent.totalSize! > 0)
                        ? (torrent.bytesDown / torrent.totalSize!).clamp(
                            0.0,
                            1.0,
                          )
                        : 0.0;
                    return ListTile(
                      title: Text(torrent.name ?? 'Unnamed'),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(torrent.status ?? 'unknown'),
                          if (torrent.totalSize != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 6,
                              ),
                            ),
                          if (torrent.totalSize != null)
                            Text('${(progress * 100).toStringAsFixed(0)}%'),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (torrent.status != 'downloading' &&
                              torrent.status != 'completed')
                            IconButton(
                              icon: const Icon(Icons.play_arrow),
                              tooltip: 'Start download',
                              onPressed: () async {
                                if (_downloadDestination.isEmpty) {
                                  await _chooseDownloadDirectory();
                                  if (_downloadDestination.isEmpty) return;
                                }
                                await TorrentService.instance.downloadTorrent(
                                  torrent.id,
                                  _downloadDestination,
                                );
                                setState(() {});
                              },
                            ),
                          if (torrent.status == 'downloading')
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          if (torrent.status == 'completed')
                            const Icon(Icons.check_circle, color: Colors.green),
                        ],
                      ),
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
              OutlinedButton.icon(
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final item = await Clipboard.getData('text/plain');
                  final payload = item?.text?.trim() ?? '';
                  if (payload.isEmpty) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Clipboard is empty')),
                    );
                    return;
                  }
                  setState(() {
                    _dmPeerController.text = payload;
                    _selectedDmPeer = payload;
                    _dmContacts.add(payload);
                    _dmUnread[payload] = 0;
                  });
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Friend identity pasted and added'),
                    ),
                  );
                },
                icon: const Icon(Icons.paste),
                label: const Text('Paste friend'),
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search contacts',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                  ),
                  onChanged: (value) => setState(() {
                    _dmSearchQuery = value.toLowerCase();
                  }),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 140,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Builder(
                    builder: (context) {
                      final filtered = _dmContacts
                          .where(
                            (peer) =>
                                peer.toLowerCase().contains(_dmSearchQuery),
                          )
                          .toList();
                      if (filtered.isEmpty) {
                        return Center(
                          child: Text(
                            'No matching contacts.',
                            style: theme.textTheme.bodySmall,
                          ),
                        );
                      }
                      return ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final peer = filtered[index];
                          final unread = _dmUnread[peer] ?? 0;
                          final selected = peer == _selectedDmPeer;
                          final peerTyping = ChatService.instance.isUserTyping(
                            peer,
                          );
                          return Container(
                            margin: const EdgeInsets.symmetric(vertical: 2),
                            decoration: BoxDecoration(
                              color: selected
                                  ? theme.colorScheme.primaryContainer
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              leading: Stack(
                                alignment: Alignment.bottomRight,
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundImage: AssetImage(kAppFavicon192),
                                  ),
                                  if (peerTyping)
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.green,
                                        border: Border.all(
                                          color: theme.colorScheme.surface,
                                          width: 1.2,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              title: Text(peer),
                              subtitle: peerTyping
                                  ? const Text(
                                      'typing...',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.green,
                                      ),
                                    )
                                  : null,
                              trailing: unread > 0
                                  ? CircleAvatar(
                                      radius: 10,
                                      backgroundColor:
                                          theme.colorScheme.primary,
                                      child: Text(
                                        '$unread',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                              color:
                                                  theme.colorScheme.onPrimary,
                                            ),
                                      ),
                                    )
                                  : null,
                              onTap: () {
                                setState(() {
                                  _selectedDmPeer = peer;
                                  _markDmRead(peer);
                                });
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
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

                  final threadRoots = messages
                      .where(
                        (m) => messages.any(
                          (reply) => reply.replyToMessageId == m.id,
                        ),
                      )
                      .toList();

                  return Column(
                    children: [
                      Expanded(
                        child: ListView.builder(
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
                                shape: RoundedRectangleBorder(
                                  side: m.id == _selectedThreadMessageId
                                      ? BorderSide(
                                          color: theme.colorScheme.primary,
                                          width: 2,
                                        )
                                      : BorderSide.none,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.center,
                                        children: [
                                          CircleAvatar(
                                            radius: 10,
                                            backgroundColor: isMe
                                                ? theme.colorScheme.primary
                                                : theme.colorScheme.secondary,
                                            child: Text(
                                              m.author.isNotEmpty
                                                  ? m.author[0].toUpperCase()
                                                  : '?',
                                              style: const TextStyle(
                                                fontSize: 10,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              m.author,
                                              style: theme.textTheme.labelSmall,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      if (m.replyToMessageId != null)
                                        Text(
                                          'Replying to ${messages.firstWhere((msg) => msg.id == m.replyToMessageId, orElse: () => m).author}',
                                          style: theme.textTheme.bodySmall,
                                        ),
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
                        ),
                      ),
                      if (threadRoots.isNotEmpty) ...[
                        const Divider(),
                        Container(
                          height: 160,
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Threads',
                                style: theme.textTheme.titleSmall,
                              ),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: threadRoots.length,
                                  itemBuilder: (context, index) {
                                    final thread = threadRoots[index];
                                    return ListTile(
                                      dense: true,
                                      title: Text(
                                        thread.text,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        '${messages.where((m) => m.replyToMessageId == thread.id).length} replies',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                      selected:
                                          thread.id == _selectedThreadMessageId,
                                      onTap: () {
                                        setState(() {
                                          _selectedThreadMessageId = thread.id;
                                        });
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
          if (_dmReplyTarget != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withAlpha(50),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Replying to ${_dmReplyTarget!.author}: ${_dmReplyTarget!.text}',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      setState(() {
                        _dmReplyTarget = null;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
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
                        try {
                          await ChatService.instance.sendDirectMessage(
                            'you',
                            _selectedDmPeer,
                            text,
                            replyToMessageId: _dmReplyTarget?.id,
                          );
                          if (ChatService.instance.messageMentions(
                            _selectedDmPeer,
                            text,
                          )) {
                            await SoundService.instance.playMention();
                          } else {
                            await SoundService.instance.playSend();
                          }
                          _dmReplyTarget = null;
                          _dmMessageController.clear();
                          if (!mounted) return;
                          setState(() {});
                          _scrollToEnd(_dmChatScrollController);
                        } catch (error) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Send failed: $error')),
                          );
                        }
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
                    leading: CircleAvatar(
                      backgroundColor: Colors.blueGrey.shade600,
                      child: Text(
                        m.author.isNotEmpty ? m.author[0].toUpperCase() : '?',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
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
                  if (selectedServer == null || selectedChannelId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Select server/channel first'),
                      ),
                    );
                    return;
                  }
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
                    if (!mounted) return;
                    setState(() {});
                  } catch (error) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Send failed: $error')),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ],
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
