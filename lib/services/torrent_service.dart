import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:vault_the_spire/bittorrent/magnet_link.dart';
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

  Future<TorrentModel?> getTorrentById(String id) =>
      TorrentsDao.instance.getTorrentById(id);

  Future<void> updateTorrent(TorrentModel torrent) =>
      TorrentsDao.instance.updateTorrent(torrent);

  Future<void> removeTorrent(String id) =>
      TorrentsDao.instance.deleteTorrent(id);

  Future<void> updateTorrentStatus(String id, String status) async {
    final existing = await TorrentsDao.instance.getTorrentById(id);
    if (existing == null) {
      throw StateError('Torrent not found: $id');
    }
    final updated = TorrentModel(
      id: existing.id,
      name: existing.name,
      type: existing.type,
      totalSize: existing.totalSize,
      totalPieces: existing.totalPieces,
      pieceLength: existing.pieceLength,
      piecesHave: existing.piecesHave,
      status: status,
      vaultKey: existing.vaultKey,
      filePath: existing.filePath,
      vaultLink: existing.vaultLink,
      magnetLink: existing.magnetLink,
      bytesDown: existing.bytesDown,
      bytesUp: existing.bytesUp,
      addedAt: existing.addedAt,
      completedAt: existing.completedAt,
      isSequential: existing.isSequential,
      selectedFiles: existing.selectedFiles,
      maxSeedRatio: existing.maxSeedRatio,
      deleteAfterRatioReached: existing.deleteAfterRatioReached,
    );
    await TorrentsDao.instance.updateTorrent(updated);
  }

  Future<void> setSeedRatioLimit(String id, double ratio) async {
    final existing = await TorrentsDao.instance.getTorrentById(id);
    if (existing == null) {
      throw StateError('Torrent not found: $id');
    }
    final updated = TorrentModel(
      id: existing.id,
      name: existing.name,
      type: existing.type,
      totalSize: existing.totalSize,
      totalPieces: existing.totalPieces,
      pieceLength: existing.pieceLength,
      piecesHave: existing.piecesHave,
      status: existing.status,
      vaultKey: existing.vaultKey,
      filePath: existing.filePath,
      vaultLink: existing.vaultLink,
      magnetLink: existing.magnetLink,
      bytesDown: existing.bytesDown,
      bytesUp: existing.bytesUp,
      addedAt: existing.addedAt,
      completedAt: existing.completedAt,
      isSequential: existing.isSequential,
      selectedFiles: existing.selectedFiles,
      maxSeedRatio: ratio,
      deleteAfterRatioReached: existing.deleteAfterRatioReached,
    );
    await TorrentsDao.instance.updateTorrent(updated);
  }

  Future<void> setDeleteAfterRatioReached(String id, bool value) async {
    final existing = await TorrentsDao.instance.getTorrentById(id);
    if (existing == null) {
      throw StateError('Torrent not found: $id');
    }
    final updated = TorrentModel(
      id: existing.id,
      name: existing.name,
      type: existing.type,
      totalSize: existing.totalSize,
      totalPieces: existing.totalPieces,
      pieceLength: existing.pieceLength,
      piecesHave: existing.piecesHave,
      status: existing.status,
      vaultKey: existing.vaultKey,
      filePath: existing.filePath,
      vaultLink: existing.vaultLink,
      magnetLink: existing.magnetLink,
      bytesDown: existing.bytesDown,
      bytesUp: existing.bytesUp,
      addedAt: existing.addedAt,
      completedAt: existing.completedAt,
      isSequential: existing.isSequential,
      selectedFiles: existing.selectedFiles,
      maxSeedRatio: existing.maxSeedRatio,
      deleteAfterRatioReached: value,
    );
    await TorrentsDao.instance.updateTorrent(updated);
  }

  Future<void> updateProgress(String id, int bytesDown, int bytesUp) async {
    final existing = await TorrentsDao.instance.getTorrentById(id);
    if (existing == null) {
      throw StateError('Torrent not found: $id');
    }

    double suggestedRatio = existing.maxSeedRatio ?? 0.0;
    bool shouldDelete = existing.deleteAfterRatioReached;
    String updatedStatus = existing.status ?? 'downloading';

    if (existing.maxSeedRatio != null && existing.maxSeedRatio! > 0) {
      final ratio = existing.bytesDown > 0 ? bytesUp / existing.bytesDown : 0.0;
      if (ratio >= existing.maxSeedRatio!) {
        updatedStatus = 'seed_ratio_reached';
        if (existing.deleteAfterRatioReached) {
          shouldDelete = true;
        }
      }
    }

    final updated = TorrentModel(
      id: existing.id,
      name: existing.name,
      type: existing.type,
      totalSize: existing.totalSize,
      totalPieces: existing.totalPieces,
      pieceLength: existing.pieceLength,
      piecesHave: existing.piecesHave,
      status: updatedStatus,
      vaultKey: existing.vaultKey,
      filePath: existing.filePath,
      vaultLink: existing.vaultLink,
      magnetLink: existing.magnetLink,
      bytesDown: bytesDown,
      bytesUp: bytesUp,
      addedAt: existing.addedAt,
      completedAt: existing.completedAt,
      isSequential: existing.isSequential,
      selectedFiles: existing.selectedFiles,
      maxSeedRatio: existing.maxSeedRatio,
      deleteAfterRatioReached: shouldDelete,
    );

    await TorrentsDao.instance.updateTorrent(updated);

    if (shouldDelete && updatedStatus == 'seed_ratio_reached') {
      await TorrentsDao.instance.deleteTorrent(id);
    }
  }

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

  Future<void> addTorrentFromMagnetLink(String uri) async {
    final magnet = MagnetLink.parse(uri);
    final infoHash = magnet.infoHashV1 ?? magnet.infoHashV2;
    if (infoHash == null || infoHash.isEmpty) {
      throw FormatException('Magnet link must contain btih or btmh infohash');
    }

    final existing = await TorrentsDao.instance.getTorrentById(infoHash);
    if (existing != null) {
      throw StateError(
        'Torrent already exists: ${magnet.displayName ?? infoHash}',
      );
    }

    final torrent = TorrentModel(
      id: infoHash,
      name: magnet.displayName ?? 'Magnet $infoHash',
      type: 'magnet_link',
      totalSize: null,
      totalPieces: null,
      pieceLength: null,
      piecesHave: null,
      status: 'queued',
      filePath: null,
      vaultLink: null,
      magnetLink: uri,
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
