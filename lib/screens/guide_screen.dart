import 'package:flutter/material.dart';

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Guide')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _GuideCard(
            icon: Icons.flag_outlined,
            title: 'Quick Start',
            bullets: const [
              'Open TorrentSpire AI and paste a magnet link.',
              'Watch progress in the Torrents queue panel.',
              'Use the folder button in Torrents to jump to files.',
              'Ask AI for help on safety, naming, or next actions.',
            ],
          ),
          const SizedBox(height: 12),
          _GuideCard(
            icon: Icons.shield_outlined,
            title: 'Safety Signals',
            bullets: const [
              'Prefer torrents with more seeders than leechers.',
              'Be careful with very old or unknown sources.',
              'Use the AI card to sanity-check suspicious entries.',
              'Scan downloaded executables before opening them.',
            ],
          ),
          const SizedBox(height: 12),
          _GuideCard(
            icon: Icons.android,
            title: 'Android Usage',
            bullets: const [
              'Default local Ollama URL on Android emulator is 10.0.2.2.',
              'Keep app permissions minimal and notifications enabled.',
              'Use app-managed download folders for best compatibility.',
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
              'Tip: If a torrent reaches 100% but you cannot find files, remove it and re-add after selecting the correct save folder.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
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
