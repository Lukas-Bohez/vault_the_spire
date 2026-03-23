import 'package:flutter/material.dart';
import 'package:vault_the_spire/screens/chat_screen.dart';
import 'package:vault_the_spire/screens/dm_screen.dart';
import 'package:vault_the_spire/screens/messages_screen.dart';
import 'package:vault_the_spire/screens/torrents_screen.dart';
import 'package:vault_the_spire/services/sound_service.dart';
import 'package:vault_the_spire/services/identity_service.dart';
import 'package:vault_the_spire/services/settings_service.dart';
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

class _HomeScreenState extends State<HomeScreen> {
  bool useSystemTray = false;
  bool minimizeToTrayOnClose = false;
  bool launchOnStartup = false;
  ServerModel? selectedServer;
  String? selectedChannelId;
  int _mobileNavIndex = 0;
  final TextEditingController _serverNameController = TextEditingController();
  final TextEditingController _inviteCodeController = TextEditingController();
  final TextEditingController _channelNameController = TextEditingController();
  final TextEditingController _dmPeerController = TextEditingController();

  @override
  void dispose() {
    _serverNameController.dispose();
    _inviteCodeController.dispose();
    _channelNameController.dispose();
    _dmPeerController.dispose();
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
            const SizedBox(height: 14),
            Text('Connected', style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            const Text('quizthespire.com', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            Text('Identity', style: theme.textTheme.labelMedium),
            const SizedBox(height: 6),
            Text(identity != null ? identity.nodeId : 'No node'),
            const SizedBox(height: 10),
            const Divider(),
            const SizedBox(height: 8),
            const Text('Servers', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...ServerService.instance.servers.map((server) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Text(server.icon),
                title: Text(server.name),
                subtitle: Text(server.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                selected: selectedServer?.id == server.id,
                onTap: () async {
                  await SoundService.instance.playClick();
                  setState(() {
                    selectedServer = server;
                    selectedChannelId = server.channels.isNotEmpty ? server.channels.first.id : null;
                  });
                },
                trailing: PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'invite') {
                      final inviteCode = ServerService.instance.generateInvite(server);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Invite code: $inviteCode')));
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
                              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                              TextButton(onPressed: () => Navigator.of(context).pop(tmp.text.trim()), child: const Text('Rename')),
                            ],
                          );
                        },
                      );
                      if (newName != null && newName.isNotEmpty) {
                        await ServerService.instance.renameServer(server.id, newName);
                        if (selectedServer?.id == server.id) selectedServer = server.copyWith(name: newName);
                        setState(() {});
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'invite', child: Text('Copy invite code')),
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            TextField(controller: _inviteCodeController, decoration: const InputDecoration(labelText: 'Invite code', isDense: true)),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                await SoundService.instance.playNotification();
                final success = await ServerService.instance.joinServer(_inviteCodeController.text.trim());
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(success ? 'Joined server!' : 'Invalid invite code.')));
                if (success) {
                  _inviteCodeController.clear();
                  setState(() {});
                }
              },
              child: const Text('Join server'),
            ),
            const SizedBox(height: 8),
            TextField(controller: _serverNameController, decoration: const InputDecoration(labelText: 'New server name', isDense: true)),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () async {
                await SoundService.instance.playNotification();
                if (_serverNameController.text.trim().isEmpty) return;
                final server = ServerService.instance.createServer(name: _serverNameController.text.trim(), description: 'Community server');
                _serverNameController.clear();
                setState(() {
                  selectedServer = server;
                  selectedChannelId = server.channels.first.id;
                });
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Created server: ${server.name} (invite: ${server.id})')));
              },
              child: const Text('Create server'),
            ),
            const SizedBox(height: 8),
            if (selectedServer != null) ...[
              const SizedBox(height: 10),
              const Text('Create Channel', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              TextField(controller: _channelNameController, decoration: const InputDecoration(labelText: 'New channel name', isDense: true)),
              const SizedBox(height: 6),
              ElevatedButton(
                onPressed: () async {
                  await SoundService.instance.playClick();
                  final name = _channelNameController.text.trim();
                  if (name.isEmpty || selectedServer == null) return;
                  final updated = await ServerService.instance.addChannel(selectedServer!.id, name);
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
                    const Text('Quick actions', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.storage),
                          label: const Text('Torrents'),
                          onPressed: () => setState(() { _mobileNavIndex = 1; }),
                        ),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.chat),
                          label: const Text('Messaging'),
                          onPressed: () => setState(() { _mobileNavIndex = 2; }),
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
                    const Text('Desktop settings', style: TextStyle(fontWeight: FontWeight.bold)),
                    SwitchListTile(title: const Text('Enable system tray icon'), value: useSystemTray, onChanged: _toggleSystemTray),
                    SwitchListTile(title: const Text('Minimize to tray on close'), value: minimizeToTrayOnClose, onChanged: useSystemTray ? _toggleMinimizeToTray : null),
                    SwitchListTile(title: const Text('Launch on startup'), value: launchOnStartup, onChanged: _toggleLaunchOnStartup),
                    SwitchListTile(title: const Text('Use dark theme'), value: ThemeService.instance.themeMode == ThemeMode.dark, onChanged: (dark) async { await ThemeService.instance.setThemeMode(dark ? ThemeMode.dark : ThemeMode.light); setState(() {}); }),
                    SwitchListTile(title: const Text('Enable sound effects'), value: SettingsService.instance.soundEffectsEnabled, onChanged: (enabled) async { await SettingsService.instance.setSoundEffectsEnabled(enabled); setState(() {}); }),
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
                    const Text('Data status', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    FutureBuilder<int>(
                      future: TorrentService.instance.allTorrents().then((list) => list.length),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
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
            Text('Welcome to the VaultTheSpire full experience.', style: theme.textTheme.bodySmall),
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
        _buildDashboard(theme),
        const TorrentsScreen(),
        const MessagesScreen(),
        _buildServerPanel(theme),
      ];

      return Scaffold(
        body: SafeArea(child: pages[_mobileNavIndex]),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _mobileNavIndex,
          onTap: (value) => setState(() { _mobileNavIndex = value; }),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.storage), label: 'Torrents'),
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
          Expanded(child: _buildDashboard(theme)),
        ],
      ),
    );
  }
}