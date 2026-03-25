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
    final progress = widget.torrent.progress;

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
          if (widget.torrent.vaultLink != null)
            IconButton(
              tooltip: 'Copy vault link',
              icon: const Icon(Icons.copy),
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(
                  ClipboardData(text: widget.torrent.vaultLink!),
                );
                if (!mounted) return;
                messenger.showSnackBar(
                  const SnackBar(content: Text('Vault link copied')),
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
            LinearProgressIndicator(value: progress),
            const SizedBox(height: 8),
            Text('Progress: ${(progress * 100).toStringAsFixed(1)}%'),
            const SizedBox(height: 8),
            Text(
              'Seeders: ${widget.torrent.seeders} • Leechers: ${widget.torrent.leechers}',
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

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Status: ${status.state}'),
                    Text('Type: ${widget.torrent.type}'),
                    Text('Size: ${widget.torrent.totalSize ?? 0} bytes'),
                    Text('Downloaded: ${status.downloaded}'),
                    Text('Uploaded: ${status.uploaded}'),
                    Text('Peers: ${status.peers}'),

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
            if (widget.torrent.type == 'vault' &&
                widget.torrent.vaultLink != null) ...[
              const Text('Vault link:'),
              SelectableText(
                widget.torrent.vaultLink!,
                style: const TextStyle(color: Colors.blueAccent),
              ),
            ],
          ],
        ),
      ),
    );
  }
}