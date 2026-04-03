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
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'InfoHash: ${torrent.id}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 8),
                Text('Progress: ${(progress * 100).toStringAsFixed(1)}%'),
                if ((view?.isSeeding ?? false))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Seeding back: ${(view!.seedingProgress * 100).toStringAsFixed(1)}% of original size shared',
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  'Seeders (DHT: ${view?.dhtNodes ?? 0}, Trackers: ${view?.trackers ?? 0}): ${view?.seeders ?? torrent.seeders} • '
                  'Leechers: ${view?.leechers ?? torrent.leechers}',
                ),
                const SizedBox(height: 16),
                if (view != null) ...[
                  Text('Connection: ${view.connectionMessage}'),
                  Text('DHT nodes: ${view.dhtNodes}, peers: ${view.peers}'),
                  Text(
                    'Download: ${(view.downloadSpeed / 1024).toStringAsFixed(2)} kB/s',
                  ),
                  Text(
                    'Upload: ${(view.uploadSpeed / 1024).toStringAsFixed(2)} kB/s',
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    ElevatedButton(
                      onPressed: () async {
                        final messenger = ScaffoldMessenger.of(context);
                        await TorrentEngineService.instance.forceRefresh(torrent.id);
                        if (!mounted) return;
                        messenger.showSnackBar(
                          const SnackBar(content: Text('Connection refresh triggered')),
                        );
                      },
                      child: const Text('Refresh'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
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
                      child: const Text('Copy Logs'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('State: $statusLabel'),
                Text('Type: ${torrent.type}'),
                Text('Size: ${torrent.totalSize ?? 0} bytes'),
                Text('Downloaded: ${view?.downloaded ?? torrent.bytesDown}'),
                Text('Uploaded: ${view?.uploaded ?? torrent.bytesUp}'),
                const SizedBox(height: 16),
                Text('Pieces: $haveCount / ${torrent.totalPieces ?? 0}'),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}
