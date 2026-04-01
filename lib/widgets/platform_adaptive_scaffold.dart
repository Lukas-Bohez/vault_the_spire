import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;
    final location = GoRouterState.of(context).uri.path;

    final navItems = [
      _NavItem(
        icon: Icons.auto_awesome,
        activeIcon: Icons.auto_awesome,
        label: 'TorrentSpire AI',
        route: '/copilot',
      ),
      _NavItem(
        icon: Icons.chat_bubble_outline,
        activeIcon: Icons.chat_bubble,
        label: 'Local AI',
        route: '/ai_chat',
      ),
      _NavItem(
        icon: Icons.download_outlined,
        activeIcon: Icons.download,
        label: 'Torrents',
        route: '/torrents',
      ),
      _NavItem(
        icon: Icons.campaign_outlined,
        activeIcon: Icons.campaign,
        label: 'Channels',
        route: '/browser',
      ),
      _NavItem(
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings,
        label: 'Settings',
        route: '/about',
      ),
    ];

    if (isDesktop) {
      final sidebarWidth = MediaQuery.of(context).size.width > 1400
          ? 240.0
          : 200.0;
      return Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: sidebarWidth,
              child: _Sidebar(items: navItems, currentPath: location),
            ),
            const VerticalDivider(width: 1),
            Expanded(child: child),
          ],
        ),
      );
    }

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indexForPath(location, navItems),
        onDestinationSelected: (i) => context.go(navItems[i].route),
        destinations: navItems
            .map(
              (item) => NavigationDestination(
                icon: Icon(item.icon),
                selectedIcon: Icon(item.activeIcon),
                label: item.label,
              ),
            )
            .toList(),
      ),
    );
  }

  int _indexForPath(String path, List<_NavItem> items) {
    final idx = items.indexWhere((i) => i.route == path);
    return idx < 0 ? 0 : idx;
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final String route;
  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.route,
  });
}

class _Sidebar extends StatelessWidget {
  final List<_NavItem> items;
  final String currentPath;
  const _Sidebar({required this.items, required this.currentPath});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A2E),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.lock, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                const Text(
                  'TorrentSpire AI',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'TorrentSpire AI',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          ...items.map((item) {
            final isActive = currentPath == item.route;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: ListTile(
                leading: Icon(
                  isActive ? item.activeIcon : item.icon,
                  color: isActive
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                title: Text(
                  item.label,
                  style: TextStyle(
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    color: isActive
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                tileColor: isActive
                    ? Theme.of(context).colorScheme.primaryContainer
                    : null,
                onTap: () => context.go(item.route),
              ),
            );
          }),
          const Spacer(),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text('Identity active', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
