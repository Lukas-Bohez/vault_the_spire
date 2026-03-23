import 'package:flutter/material.dart';
import 'package:vault_the_spire/screens/messages_screen.dart';
import 'package:vault_the_spire/screens/torrents_screen.dart';
import 'package:vault_the_spire/services/identity_service.dart';
import 'package:vault_the_spire/services/settings_service.dart';
import 'package:vault_the_spire/services/tray_service.dart';
import 'package:vault_the_spire/services/startup_service.dart';
import 'package:vault_the_spire/services/torrent_service.dart';
import 'package:window_manager/window_manager.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late bool _useSystemTray;
  late bool _minimizeToTrayOnClose;
  late bool _launchOnStartup;

  @override
  void initState() {
    super.initState();
    _useSystemTray = SettingsService.instance.useSystemTray;
    _minimizeToTrayOnClose = SettingsService.instance.minimizeToTrayOnClose;
    _launchOnStartup = SettingsService.instance.launchOnStartup;
  }

  Future<void> _toggleSystemTray(bool value) async {
    await SettingsService.instance.setUseSystemTray(value);
    setState(() {
      _useSystemTray = value;
    });
  }

  Future<void> _toggleMinimizeToTray(bool value) async {
    await SettingsService.instance.setMinimizeToTrayOnClose(value);
    setState(() {
      _minimizeToTrayOnClose = value;
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
      _launchOnStartup = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final identity = IdentityService.instance.identity;

    return Scaffold(
      appBar: AppBar(title: const Text('VaultTheSpire')),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Welcome to VaultTheSpire',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const TorrentsScreen())),
              icon: const Icon(Icons.storage),
              label: const Text('Open Torrents'),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const MessagesScreen())),
              icon: const Icon(Icons.chat),
              label: const Text('Open Messaging'),
            ),
            const SizedBox(height: 16),
            const Text('Core identity and peer state are initialized.'),
            const SizedBox(height: 16),
            if (identity == null)
              const Text('Identity was not found. Please restart the app.')
            else ...[
              Text('Node ID: ${identity.nodeId}'),
              const SizedBox(height: 12),
              Text(
                'Public Key (short): ${identity.publicKeyBase64.substring(0, 16)}...',
              ),
              const SizedBox(height: 12),
              Text(
                'Private Key (short): ${identity.privateKeyBase64.substring(0, 16)}...',
              ),
            ],
            const SizedBox(height: 24),
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Desktop behavior',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SwitchListTile(
                      title: const Text('Enable system tray icon'),
                      value: _useSystemTray,
                      onChanged: (value) async {
                        await _toggleSystemTray(value);
                        if (value) {
                          await TrayService(
                            shouldMinimiseToTray: () => _minimizeToTrayOnClose,
                            onTrayShow: () => windowManager.show(),
                            onTrayQuit: () => windowManager.destroy(),
                          ).init();
                        }
                      },
                    ),
                    SwitchListTile(
                      title: const Text('Minimize to tray on close'),
                      value: _minimizeToTrayOnClose,
                      onChanged: _useSystemTray ? _toggleMinimizeToTray : null,
                    ),
                    SwitchListTile(
                      title: const Text('Launch on startup'),
                      value: _launchOnStartup,
                      onChanged: _toggleLaunchOnStartup,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Connected service: https://quizthespire.com/',
              style: TextStyle(color: Colors.blue),
            ),
            const SizedBox(height: 8),
            const Text(
              'VaultTheSpire is the desktop client for QuizTheSpire services.\nUsers can manage encrypted torrents and messaging built on quizthespire API.',
            ),
            const SizedBox(height: 24),
            const Text(
              'Next work: implement DHT + peer wire + torrents engine.',
            ),
            const SizedBox(height: 24),
            const Text('Local DB status:'),
            FutureBuilder(
              future: TorrentService.instance.allTorrents(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Text('Loading torrents...');
                }
                if (snapshot.hasError) {
                  return Text('DB error: ${snapshot.error}');
                }
                final torrents = snapshot.data as List?;
                return Text('Torrents in DB: ${torrents?.length ?? 0}');
              },
            ),
          ],
        ),
      ),
    );
  }
}
