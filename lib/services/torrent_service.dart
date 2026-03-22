import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vault_the_spire/bittorrent/torrent_file.dart';
import 'package:vault_the_spire/db/torrents_dao.dart';
import 'package:vault_the_spire/models/torrent.dart';

class TorrentService {
  TorrentService._();

  static final TorrentService instance = TorrentService._();

  Future<List<TorrentModel>> allTorrents() =>
      TorrentsDao.instance.getAllTorrents();

  Future<void> addTorrent(TorrentModel torrent) =>
      TorrentsDao.instance.insertTorrent(torrent);

  Future<void> updateTorrent(TorrentModel torrent) =>
      TorrentsDao.instance.updateTorrent(torrent);

  Future<void> removeTorrent(String id) =>
      TorrentsDao.instance.deleteTorrent(id);

  Future<void> addTorrentFromTorrentFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('Torrent file does not exist', path);
    }

    final bytes = await file.readAsBytes();
    final metadata = TorrentFileParser.parse(bytes);

    final existing = await TorrentsDao.instance.getTorrentById(
      metadata.infoHashV1,
    );
    if (existing != null) {
      throw StateError('Torrent already exists: ${metadata.name}');
    }

    final totalSize = metadata.files.fold<int>(
      0,
      (sum, entry) => sum + entry.length,
    );
    final magnetLink = createMagnetLink(
      metadata.infoHashV1,
      metadata.name,
      metadata.trackers,
    );

    final torrent = TorrentModel(
      id: metadata.infoHashV1,
      name: metadata.name,
      type: 'torrent_file',
      totalSize: totalSize,
      totalPieces: metadata.pieceHashes.length,
      pieceLength: metadata.pieceLength,
      piecesHave: null,
      status: 'added',
      filePath: p.normalize(path),
      magnetLink: magnetLink,
      bytesDown: 0,
      bytesUp: 0,
      addedAt: DateTime.now().millisecondsSinceEpoch,
      isSequential: false,
    );

    await TorrentsDao.instance.insertTorrent(torrent);
  }

  static String createMagnetLink(
    String infoHash,
    String name,
    List<String> trackers,
  ) {
    final encodedName = Uri.encodeComponent(name);
    final trackersQuery = trackers
        .where((t) => t.isNotEmpty)
        .map((t) => 'tr=${Uri.encodeComponent(t)}')
        .join('&');

    final List<String> pieces = ['xt=urn:btih:$infoHash', 'dn=$encodedName'];
    if (trackersQuery.isNotEmpty) {
      pieces.add(trackersQuery);
    }

    return 'magnet:?${pieces.join('&')}';
  }
}
