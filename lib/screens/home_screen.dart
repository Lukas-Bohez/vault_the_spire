import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vault_the_spire/screens/browser_screen.dart';
import 'package:vault_the_spire/screens/chat_hub_screen.dart';
import 'package:vault_the_spire/screens/settings_screen.dart';
import 'package:vault_the_spire/screens/torrents_screen.dart';
import 'package:vault_the_spire/services/theme_service.dart';
import 'package:vault_the_spire/services/torrent_engine_service.dart';
import 'package:vault_the_spire/widgets/network_health_indicator.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  int _activeSpires = 0;

  static const _titles = [
    'Dashboard',
    'Browser',
    'Messages',
    'Settings',
  ];

  Timer? _swarmPulseTimer;

  @override
  void initState() {
    super.initState();
    _refreshActiveSpires();
    _swarmPulseTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _refreshActiveSpires();
    });
  }

  Future<void> _refreshActiveSpires() async {
    final count = TorrentEngineService.instance.activeSpiresCount;
    if (!mounted) return;
    setState(() => _activeSpires = count);
  }

  Widget _buildChatIcon(bool selected) {
    const baseIcon = Icons.chat_bubble_outline;
    const baseSelectedIcon = Icons.chat_bubble;

    final icon = Icon(selected ? baseSelectedIcon : baseIcon);
    if (_activeSpires <= 0) {
      return icon;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
              border: Border.all(color: Theme.of(context).colorScheme.surface, width: 1.5),
            ),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            child: Text(
              '$_activeSpires',
              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _swarmPulseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('VaultTheSpire - ${_titles[_selectedIndex]}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.brightness_6),
            tooltip: 'Toggle theme',
            onPressed: () {
              final current = ThemeService.instance.themeMode;
              final next = current == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
              ThemeService.instance.setThemeMode(next);
            },
          ),
          const NetworkHealthIndicator(),
        ],
      ),
      body: Row(
        children: [
          NavigationRail(
            backgroundColor: Theme.of(context).colorScheme.surface,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              if (mounted) {
                setState(() {
                  _selectedIndex = index;
                });
              }
            },
            labelType: NavigationRailLabelType.all,
            destinations: [
              const NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('Dashboard'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.public_outlined),
                selectedIcon: Icon(Icons.public),
                label: Text('Browser'),
              ),
              NavigationRailDestination(
                icon: _buildChatIcon(false),
                selectedIcon: _buildChatIcon(true),
                label: const Text('Chat'),
              ),
              const NavigationRailDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: Text('Settings'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: const [
                TorrentsScreen(),
                BrowserScreen(),
                ChatHubScreen(),
                SettingsScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
