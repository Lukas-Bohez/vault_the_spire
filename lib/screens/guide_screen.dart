import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  bool get _isAndroidOnlyBuild =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final android = _isAndroidOnlyBuild;

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
                  android
                      ? 'Android Torrent Guide'
                      : 'Desktop TorrentSpire Guide',
                  style: tt.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  android
                      ? 'This guide is for the Android app: managing torrents you have already imported, checking progress, choosing storage, and handling the common mobile quirks that come with long downloads.'
                      : 'This guide is for the desktop app: search workflows, AI-assisted checks, stable long-running sessions, and safer seeding.',
                  style: tt.bodyMedium?.copyWith(
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _GuideChip(
                      label: android ? 'Android focused' : 'Desktop focused',
                      icon: Icons.devices,
                    ),
                    _GuideChip(
                      label: android
                          ? 'Storage-safe workflow'
                          : 'AI-assisted decisions',
                      icon: android
                          ? Icons.folder_open_outlined
                          : Icons.smart_toy_outlined,
                    ),
                    const _GuideChip(
                      label: 'Safer download workflow',
                      icon: Icons.health_and_safety_outlined,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _GuideCard(
            icon: Icons.flag_outlined,
            title: 'Quick Start Flow',
            bullets: android
                ? const [
                    'Open Torrents to manage downloads that have already been added to the app.',
                    'Set your default download folder in Settings before long downloads.',
                    'Watch status in Torrents and use the row actions menu for play/pause/remove.',
                    'Once complete, keep seeding if you want to share back to the swarm.',
                  ]
                : const [
                    'Open TorrentSpire AI and search or paste a magnet link.',
                    'Confirm destination folder in Settings before long downloads.',
                    'Track progress in Torrents and use Open folder to inspect output.',
                    'Once complete, leave seeding active to contribute back to swarm health.',
                  ],
          ),
          const SizedBox(height: 12),
          _GuideCard(
            icon: Icons.shield_outlined,
            title: 'Trust and Safety Signals',
            bullets: android
                ? const [
                    'Prefer torrents with stable seed counts rather than single-source links.',
                    'Treat unknown uploaders and very old listings as higher risk.',
                    'Avoid installing APKs from untrusted sources.',
                    'Scan downloaded archives before opening on any device.',
                  ]
                : const [
                    'Prefer strong seed counts and balanced swarm ratios over single-source listings.',
                    'Treat unknown uploaders and extremely old listings as higher risk.',
                    'Use AI context cards for second-pass sanity checks before opening files.',
                    'Always scan executables and archives with trusted security tools.',
                  ],
          ),
          const SizedBox(height: 12),
          _GuideCard(
            icon: android ? Icons.android : Icons.desktop_windows_outlined,
            title: android ? 'Android Usage' : 'Desktop Workflow',
            bullets: android
                ? const [
                    'Use app-managed storage paths for best Android compatibility.',
                    'If folder opening is restricted by Android, use the shown saved path in Files app.',
                    'Disable battery optimization for long-running downloads when possible.',
                    'Use the compact row actions menu on smaller screens.',
                  ]
                : const [
                    'Use browser and AI tabs for triage before starting large downloads.',
                    'Keep long-running sessions on stable network/power for best seeding uptime.',
                    'Use Open Folder directly from torrent row to verify output quickly.',
                    'Close stale duplicate app instances before rebuilding/rerunning on Windows.',
                  ],
          ),
          const SizedBox(height: 12),
          _GuideCard(
            icon: Icons.rocket_launch_outlined,
            title: 'Performance and Reliability',
            bullets: android
                ? const [
                    'Metadata fetching can be slower on mobile networks; allow time for peer discovery.',
                    'If metadata stalls repeatedly, remove and re-add with a healthier magnet/trackers.',
                    'Avoid aggressive battery/data saver modes during active downloads.',
                  ]
                : const [
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
              android
                  ? 'Pro tip: If the list feels slow right after launch, pull to refresh once. On Android, torrents can take a moment to sync after add/remove actions.'
                  : 'Pro tip: If a torrent reaches 100% but files are hard to locate, open its folder directly from the torrent row and verify destination settings before re-adding.',
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
