import 'package:flutter/material.dart';
import 'package:vault_the_spire/models/torrent.dart';

class TorrentDetailScreen extends StatelessWidget {
  final TorrentModel torrent;

  const TorrentDetailScreen({super.key, required this.torrent});

  @override
  Widget build(BuildContext context) {
    final piecesCount = torrent.totalPieces ?? 0;
    final haveCount =
        torrent.piecesHave?.split(',').where((e) => e == '1').length ?? 0;
    final progress = piecesCount > 0 ? (haveCount / piecesCount) : 0.0;

    return Scaffold(
      appBar: AppBar(title: Text(torrent.name)),
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
            const SizedBox(height: 16),
            Text('Status: ${torrent.status ?? 'unknown'}'),
            Text('Type: ${torrent.type}'),
            Text('Size: ${torrent.totalSize ?? 0} bytes'),
            Text('Downloaded: ${torrent.bytesDown}'),
            Text('Uploaded: ${torrent.bytesUp}'),
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
