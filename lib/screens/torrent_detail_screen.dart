import 'package:flutter/material.dart';
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
    final piecesCount = widget.torrent.totalPieces ?? 0;
    final haveCount =
        widget.torrent.piecesHave?.split(',').where((e) => e == '1').length ??
        0;
    final progress = piecesCount > 0 ? (haveCount / piecesCount) : 0.0;

    return Scaffold(
      appBar: AppBar(title: Text(widget.torrent.name)),
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
            Text('Pieces: $haveCount / $piecesCount'),
            const SizedBox(height: 16),
            if (torrent.type == 'vault' && torrent.vaultLink != null) ...[
              const Text('Vault link:'),
              SelectableText(
                torrent.vaultLink!,
                style: const TextStyle(color: Colors.blueAccent),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
