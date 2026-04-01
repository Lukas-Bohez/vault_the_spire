import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vault_the_spire/models/torrent.dart';
import 'package:vault_the_spire/services/torrent_engine_service.dart';

class TorrentDetailScreen extends StatefulWidget {
  final TorrentModel torrent;

  const TorrentDetailScreen({super.key, required this.torrent});

  @override
  State<TorrentDetailScreen> createState() => _TorrentDetailScreenState();
}

class _TorrentDetailScreenState extends State<TorrentDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final haveCount = widget.torrent.havePieces;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.torrent.name),
        actions: [
          if (widget.torrent.magnetLink != null)
            IconButton(
              tooltip: 'Copy magnet link',
              icon: const Icon(Icons.link),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(
                  ClipboardData(text: widget.torrent.magnetLink!),
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
              'InfoHash: ${widget.torrent.id}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            StreamBuilder<TorrentEngineStatus>(
              stream: TorrentEngineService.instance.statusStream.where(
                (status) => status.torrentId == widget.torrent.id,
              ),
              builder: (context, snapshot) {
                final status = snapshot.data;
                final progress = status == null
                    ? widget.torrent.progress
                    : (status.state.toLowerCase().contains('seed')
                          ? status.seedingProgress
                          : status.progress)
                        .clamp(0.0, 1.0);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 8),
                    Text('Progress: ${(progress * 100).toStringAsFixed(1)}%'),
                    if (status != null && status.state.toLowerCase().contains('seed'))
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Seeding back: ${(status.seedingProgress * 100).toStringAsFixed(1)}% of original size shared',
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            StreamBuilder<TorrentEngineStatus>(
              stream: TorrentEngineService.instance.statusStream.where(
                (status) => status.torrentId == widget.torrent.id,
              ),
              builder: (context, snapshot) {
                final status = snapshot.data;
                return Text(
                  'Seeders (DHT: ${status?.dhtNodes ?? 0}, Trackers: ${status?.trackers ?? 0}): ${status?.seeders ?? widget.torrent.seeders} • '
                  'Leechers: ${status?.leechers ?? widget.torrent.leechers}',
                );
              },
            ),
            const SizedBox(height: 16),
            StreamBuilder<TorrentEngineStatus>(
              stream: TorrentEngineService.instance.statusStream.where(
                (status) => status.torrentId == widget.torrent.id,
              ),
              builder: (context, snapshot) {
                final status = snapshot.data;
                if (status == null) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Status: ${widget.torrent.status ?? 'unknown'}'),
                      Text('Type: ${widget.torrent.type}'),
                      Text('Size: ${widget.torrent.totalSize ?? 0} bytes'),
                      Text('Downloaded: ${widget.torrent.bytesDown}'),
                      Text('Uploaded: ${widget.torrent.bytesUp}'),
                    ],
                  );
                }

                final statusMessage = status.statusMessage;
                final hasError =
                    status.state.toLowerCase().contains('error') ||
                    status.state.toLowerCase().contains('failed');

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Connection: ${status.connectionMessage}'),
                    Text(
                      'DHT nodes: ${status.dhtNodes}, peers: ${status.peers}',
                    ),
                    Text(
                      'Download: ${(status.downloadSpeed / 1024).toStringAsFixed(2)} kB/s',
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ElevatedButton(
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            await TorrentEngineService.instance.forceRefresh(
                              widget.torrent.id,
                            );
                            if (!mounted) return;
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Connection refresh triggered'),
                              ),
                            );
                          },
                          child: const Text('Refresh'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            final logs = TorrentEngineService.instance.getLogs(
                              widget.torrent.id,
                            );
                            await Clipboard.setData(
                              ClipboardData(text: logs.join('\n')),
                            );
                            if (!mounted) return;
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Connection logs copied'),
                              ),
                            );
                          },
                          child: const Text('Copy Logs'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('State: ${status.state}'),
                    Text('Type: ${widget.torrent.type}'),
                    Text('Size: ${widget.torrent.totalSize ?? 0} bytes'),
                    Text('Downloaded: ${status.downloaded}'),
                    Text('Uploaded: ${status.uploaded}'),
                    Text(
                      'Progress engine: ${(status.progress * 100).toStringAsFixed(1)}%',
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Text('Pieces: $haveCount / ${widget.torrent.totalPieces ?? 0}'),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  String getStatusLabel(TorrentEngineStatus status) {
    if (status.state.toLowerCase().contains('paused')) {
      return '⏸️ Paused';
    }

    if (status.downloaded <= 0) {
      if (status.peers == 0 && status.dhtNodes < 5) {
        return '🛰️ Bootstrapping DHT... (Checking network)';
      }
      if (status.peers == 0) {
        return '🔍 Searching for peers...';
      }
      return '📥 Downloading metadata...';
    }

    return '🚀 Downloading data...';
  }
}
