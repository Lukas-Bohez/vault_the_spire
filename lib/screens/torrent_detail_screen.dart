import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vault_the_spire/models/torrent.dart';
import 'package:vault_the_spire/services/torrent_engine_service.dart';
import 'package:vault_the_spire/services/torrent_service.dart';

class TorrentDetailScreen extends StatefulWidget {
  final TorrentModel torrent;

  const TorrentDetailScreen({super.key, required this.torrent});

  @override
  State<TorrentDetailScreen> createState() => _TorrentDetailScreenState();
}

class _TorrentDetailScreenState extends State<TorrentDetailScreen> {
  Future<bool> _confirmRedownload() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Redownload torrent?'),
        content: const Text(
          'This will stop the torrent, clear downloaded content, and start from 0%.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Redownload'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _redownload(TorrentModel torrent) async {
    final confirmed = await _confirmRedownload();
    if (!confirmed || !mounted) return;

    try {
      await TorrentEngineService.instance.forceRedownload(torrent.id);

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Redownload restarted.')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Redownload failed: $e')));
    }
  }

  Future<void> _recheck(String torrentId) async {
    try {
      final result = await TorrentEngineService.instance.recheckTorrent(torrentId);
      if (!mounted) return;
      final valid = result['isValid'] == true;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            valid
                ? 'Recheck complete: all pieces valid.'
                : 'Recheck complete: ${result['invalidPieces']} piece(s) invalid.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Recheck failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<TorrentViewState?>(
      stream: TorrentService.instance.torrentStateStream(widget.torrent.id),
      builder: (context, snapshot) {
        final view = snapshot.data;
        final torrent = view?.model ?? widget.torrent;
        final progress = (view?.progress ?? torrent.progress).clamp(0.0, 1.0);
        final haveCount = torrent.havePieces;
        final statusLabel = view?.statusLabel ?? (torrent.status ?? 'unknown');

        return Scaffold(
          appBar: AppBar(
            title: Text(torrent.name),
            actions: [
              if (torrent.magnetLink != null)
                IconButton(
                  tooltip: 'Copy magnet link',
                  icon: const Icon(Icons.link),
                  onPressed: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(
                      ClipboardData(text: torrent.magnetLink!),
                    );
                    if (!mounted) return;
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Magnet link copied')),
                    );
                  },
                ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              statusLabel,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.primary,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              '${(progress * 100).toStringAsFixed(2)}%',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 20,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                            value: progress,
                            minHeight: 10,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                          ),
                        ),
                        if (torrent.totalSize != null && torrent.totalSize! > 0) ...[
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${_fmtBytes((progress * torrent.totalSize!).round())} downloaded',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              Text(
                                'of ${_fmtBytes(torrent.totalSize!)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (view != null)
                  Row(
                    children: [
                      _StatChip(
                        icon: Icons.arrow_downward_rounded,
                        label: '${_fmtBytes(view.downloadSpeed.round())}/s',
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      _StatChip(
                        icon: Icons.arrow_upward_rounded,
                        label: '${_fmtBytes(view.uploadSpeed.round())}/s',
                        color: Theme.of(context).colorScheme.tertiary,
                      ),
                      const SizedBox(width: 8),
                      _StatChip(
                        icon: Icons.people_outline,
                        label: '${view.peers} peers',
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Refresh'),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await TorrentEngineService.instance.forceRefresh(torrent.id);
                        if (!mounted) return;
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Connection refresh triggered')),
                        );
                      },
                    ),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.fact_check_outlined, size: 16),
                      label: const Text('Recheck files'),
                      onPressed: () => _recheck(torrent.id),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.replay, size: 16),
                      label: const Text('Redownload'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                      ),
                      onPressed: () => _redownload(torrent),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Copy logs'),
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final logs = TorrentEngineService.instance.getLogs(
                          torrent.id,
                        );
                        await Clipboard.setData(
                          ClipboardData(text: logs.join('\n')),
                        );
                        if (!mounted) return;
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Connection logs copied')),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _InfoTile('InfoHash', torrent.id, small: true),
                _InfoTile('Type', torrent.type),
                _InfoTile('Status', statusLabel),
                if (view != null) ...[
                  _InfoTile(
                    'Seeders',
                    '${view.seeders} (DHT: ${view.dhtNodes}, Tracker: ${view.trackers})',
                  ),
                  _InfoTile('Leechers', '${view.leechers}'),
                  _InfoTile('Connection', view.connectionMessage),
                ],
                _InfoTile('Pieces', '$haveCount / ${torrent.totalPieces ?? 0}'),
                _InfoTile(
                  'Downloaded',
                  _fmtBytes(view?.downloaded ?? torrent.bytesDown),
                ),
                _InfoTile('Uploaded', _fmtBytes(view?.uploaded ?? torrent.bytesUp)),
                if ((view?.isSeeding ?? false))
                  _InfoTile(
                    'Shared back',
                    '${(view!.seedingProgress * 100).toStringAsFixed(1)}% of size',
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final bool small;

  const _InfoTile(this.label, this.value, {this.small = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: small ? 10 : 12,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: small ? 10 : 13,
                fontFamily: small ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _fmtBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  return '${value.toStringAsFixed(index == 0 ? 0 : 1)} ${units[index]}';
}
