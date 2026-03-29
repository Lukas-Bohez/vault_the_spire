import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vault_the_spire/services/identity_service.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final identity = IdentityService.instance.identity;
    final fingerprint = identity?.publicKeyBase64 ?? 'N/A';
    return Scaffold(
      appBar: AppBar(
        title: const Text('VaultTheSpire'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            const Text(
              'VaultTheSpire',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'What goes into the Vault, stays in the Vault.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 20,
                crossAxisSpacing: 20,
                childAspectRatio: 1.2,
                children: [
                  _QuickActionCard(
                    icon: Icons.chat_bubble_outline,
                    title: 'New Message',
                    subtitle: 'Start a secure conversation',
                    onTap: () => context.go('/chat_hub'),
                  ),
                  _QuickActionCard(
                    icon: Icons.download_outlined,
                    title: 'Add Torrent',
                    subtitle: 'Share or download files',
                    onTap: () => context.go('/torrents'),
                  ),
                  _QuickActionCard(
                    icon: Icons.campaign_outlined,
                    title: 'Browse Channels',
                    subtitle: 'Join public or private channels',
                    onTap: () => context.go('/browser'),
                  ),
                  _QuickActionCard(
                    icon: Icons.settings_outlined,
                    title: 'Settings',
                    subtitle: 'Manage preferences',
                    onTap: () => context.go('/about'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Identity ready',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        'Fingerprint: ${fingerprint.length > 16 ? fingerprint.substring(0, 16) : fingerprint}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: Colors.grey,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                icon,
                size: 36,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
