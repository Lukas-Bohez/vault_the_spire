import 'package:flutter/material.dart';
import 'package:vault_the_spire/screens/messages_screen.dart';
import 'package:vault_the_spire/screens/torrents_screen.dart';
import 'package:vault_the_spire/services/identity_service.dart';
import 'package:vault_the_spire/services/settings_service.dart';
import 'package:vault_the_spire/services/theme_service.dart';
import 'package:vault_the_spire/services/tray_service.dart';
import 'package:vault_the_spire/services/server_service.dart';
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
  final TextEditingController _serverNameController = TextEditingController();
  final TextEditingController _inviteCodeController = TextEditingController();

  @override
  void dispose() {
    _serverNameController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    useSystemTray = SettingsService.instance.useSystemTray;
    minimizeToTrayOnClose = SettingsService.instance.minimizeToTrayOnClose;
    launchOnStartup = SettingsService.instance.launchOnStartup;
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

  @override
  Widget build(BuildContext context) {
    final identity = IdentityService.instance.identity;
    final theme = Theme.of(context);

    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 260,
            color: theme.colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
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
                TextButton.icon(
                  icon: const Icon(Icons.storage),
                  label: const Text('Torrents'),
                  style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TorrentsScreen()),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.chat),
                  label: const Text('Messaging'),
                  style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MessagesScreen()),
                  ),
                ),
                const Divider(height: 26),
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
                const Text('Servers', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...ServerService.instance.servers.map((server) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Text(server.icon),
                      title: Text(server.name),
                      subtitle: Text(server.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                    )),
                const SizedBox(height: 8),
                TextField(
                  controller: _inviteCodeController,
                  decoration: const InputDecoration(labelText: 'Invite code', isDense: true),
                ),
                ElevatedButton(
                  onPressed: () {
                    final success = ServerService.instance.joinServer(_inviteCodeController.text.trim());
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(success ? 'Joined server!' : 'Invalid invite code.')),
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
                  decoration: const InputDecoration(labelText: 'New server name', isDense: true),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (_serverNameController.text.trim().isEmpty) return;
                    final server = ServerService.instance.createServer(
                      name: _serverNameController.text.trim(),
                      description: 'Community server',
                    );
                    _serverNameController.clear();
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Created server: ${server.name} (invite: ${server.id})')),
                    );
                  },
                  child: const Text('Create server'),
                ),
                const SizedBox(height: 10),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'Welcome to the VaultTheSpire Discord-style client.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
          Expanded(
            child: Container(
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
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const TorrentsScreen(),
                                    ),
                                  ),
                                ),
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.chat),
                                  label: const Text('Messaging'),
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const MessagesScreen(),
                                    ),
                                  ),
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
                              onChanged: useSystemTray
                                  ? _toggleMinimizeToTray
                                  : null,
                            ),
                            SwitchListTile(
                              title: const Text('Launch on startup'),
                              value: launchOnStartup,
                              onChanged: _toggleLaunchOnStartup,
                            ),
                            SwitchListTile(
                              title: const Text('Use dark theme'),
                              value:
                                  ThemeService.instance.themeMode ==
                                  ThemeMode.dark,
                              onChanged: (dark) async {
                                await ThemeService.instance.setThemeMode(
                                  dark ? ThemeMode.dark : ThemeMode.light,
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
                              future: TorrentService.instance
                                  .allTorrents()
                                  .then((list) => list.length),
                              builder: (context, snapshot) {
                                if (snapshot.connectionState ==
                                    ConnectionState.waiting) {
                                  return const Text('Loading Torrent state...');
                                }
                                if (snapshot.hasError) {
                                  return Text('DB error: ${snapshot.error}');
                                }
                                return Text(
                                  'Torrents in DB: ${snapshot.data ?? 0}',
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
