import 'package:flutter/material.dart';

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Guide')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                colors: [
                  cs.primaryContainer,
                  cs.tertiaryContainer,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TorrentSpire Release Guide',
                  style: tt.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'From first magnet to secure seeding, this flow covers the fastest way to operate safely and avoid common pitfalls.',
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: const [
                    _GuideChip(label: 'Desktop + Android ready', icon: Icons.devices),
                    _GuideChip(label: 'AI-assisted decisions', icon: Icons.smart_toy_outlined),
                    _GuideChip(label: 'Safer download workflow', icon: Icons.health_and_safety_outlined),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _GuideCard(
            icon: Icons.flag_outlined,
            title: 'Quick Start Flow',
            bullets: const [
              'Open TorrentSpire AI, search or paste a magnet link, then add it.',
              'Confirm destination folder in Settings before long downloads.',
              'Track progress in Torrents and use Open folder to inspect output.',
              'Once complete, leave seeding active to contribute back to swarm health.',
            ],
          ),
          const SizedBox(height: 12),
          _GuideCard(
            icon: Icons.shield_outlined,
            title: 'Trust and Safety Signals',
            bullets: const [
              'Prefer strong seed counts and balanced swarm ratios over single-source listings.',
              'Treat unknown uploaders and extremely old listings as higher risk.',
              'Use AI context cards for second-pass sanity checks before opening files.',
              'Always scan executables and archives with trusted security tools.',
            ],
          ),
          const SizedBox(height: 12),
          _GuideCard(
            icon: Icons.android,
            title: 'Android and Mobile Usage',
            bullets: const [
              'Default local Ollama URL on Android emulator is 10.0.2.2.',
              'Use app-managed storage paths for better compatibility and visibility.',
              'Keep battery optimization disabled for long-running torrent sessions.',
              'Use compact actions menu on small screens for folder/play/copy/delete tools.',
            ],
          ),
          const SizedBox(height: 12),
          _GuideCard(
            icon: Icons.rocket_launch_outlined,
            title: 'Performance and Reliability',
            bullets: const [
              'Keep at least one reliable tracker and allow enough time for peer discovery.',
              'If metadata resolution stalls, retry with a healthy magnet and known trackers.',
              'For stable desktop sessions, avoid running multiple heavy browser tabs in parallel.',
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Text(
              'Pro tip: If a torrent reaches 100% but files are hard to locate, open its folder directly from the torrent row and verify destination settings before re-adding.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuideChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _GuideChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: cs.surface.withOpacity(0.45),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSurface),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final List<String> bullets;

  const _GuideCard({
    required this.icon,
    required this.title,
    required this.bullets,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: cs.primary),
              const SizedBox(width: 8),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 8),
          for (final line in bullets)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('• $line'),
            ),
        ],
      ),
    );
  }
}
