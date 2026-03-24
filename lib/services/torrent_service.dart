import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:vault_the_spire/bittorrent/bencode.dart';
import 'package:vault_the_spire/bittorrent/magnet_link.dart';
import 'package:vault_the_spire/bittorrent/torrent_file.dart';
import 'package:vault_the_spire/db/torrents_dao.dart';
import 'package:vault_the_spire/models/torrent.dart';

class TorrentService {
  TorrentService._();

  static final TorrentService instance = TorrentService._();

  Future<List<TorrentModel>> allTorrents() =>
      TorrentsDao.instance.getAllTorrents();

  Future<List<TorrentModel>> findTorrents(String query) async {
    final keyword = query.toLowerCase().trim();
    final all = await allTorrents();
    return all.where((torrent) {
      final name = torrent.name.toLowerCase();
      final magnet = torrent.magnetLink?.toLowerCase() ?? '';
      return name.contains(keyword) || magnet.contains(keyword);
    }).toList();
  }


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

  Future<void> downloadTorrent(String id, String destinationPath) async {
    final existing = await TorrentsDao.instance.getTorrentById(id);
    if (existing == null) {
      throw StateError('Torrent not found: $id');
    }

    if (destinationPath.trim().isEmpty) {
      throw ArgumentError('Destination path cannot be empty');
    }

    final folder = Directory(destinationPath);
    if (!await folder.exists()) {
      throw FileSystemException(
        'Destination folder does not exist',
        destinationPath,
      );
    }

    final totalSize = existing.totalSize ?? 500 * 1024 * 1024;
    int bytesDown = existing.bytesDown;
    int bytesUp = existing.bytesUp;

    await updateTorrent(
      existing.copyWith(
        status: 'downloading',
        filePath: destinationPath,
        bytesDown: bytesDown,
        bytesUp: bytesUp,
      ),
    );

    final int chunkSize = max(1024 * 1024, (totalSize ~/ 25));

    while (bytesDown < totalSize) {
      await Future.delayed(const Duration(seconds: 1));
      bytesDown = min(totalSize, bytesDown + chunkSize);
      bytesUp = min(totalSize, bytesUp + chunkSize);

      await updateProgress(id, bytesDown, bytesUp);
    }

    await updateTorrent(
      existing.copyWith(
        status: 'completed',
        bytesDown: totalSize,
        bytesUp: totalSize,
        completedAt: DateTime.now().millisecondsSinceEpoch,
        filePath: destinationPath,
        isSequential: true,
      ),
    );
  }

  Future<void> setDestinationAndStart(String id, String destinationPath) async {
    await updateTorrent(
      (await getTorrentById(id))!.copyWith(filePath: destinationPath),
    );
    await downloadTorrent(id, destinationPath);
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
      pieces.addAll(trackersQuery.split('&'));
    }

    return 'magnet:?${pieces.join('&')}';
  }

  Future<void> addTorrentFromPath(
    String path, {
    int pieceLength = 262144,
  }) async {
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('Path does not exist', path);
    }

    final root = Directory(path);
    final name = p.basename(path);
    final baseDir = type == FileSystemEntityType.directory
        ? Directory(path)
        : File(path).parent;

    final List<_FileEntry> entries = [];

    if (type == FileSystemEntityType.file) {
      final file = File(path);
      final stat = await file.stat();
      entries.add(
        _FileEntry(
          file.path,
          p.relative(file.path, from: baseDir.path),
          stat.size,
        ),
      );
    } else {
      await for (var entity in root.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final rel = p.relative(entity.path, from: root.path);
          final stat = await entity.stat();
          entries.add(_FileEntry(entity.path, rel, stat.size));
        }
      }
      entries.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    }

    if (entries.isEmpty) {
      throw StateError('No files to create torrent from');
    }

    final bytesBuilder = BytesBuilder();
    final pieceHashes = BytesBuilder();
    int bufferLen = 0;

    Future<void> addChunk(List<int> chunk) async {
      bytesBuilder.add(chunk);
      bufferLen += chunk.length;
      if (bufferLen >= pieceLength) {
        final pieceData = bytesBuilder.toBytes();
        final toHash = pieceData.sublist(0, pieceLength);
        final digest = sha1.convert(toHash);
        pieceHashes.add(digest.bytes);
        final remaining = pieceData.sublist(pieceLength);
        bytesBuilder.clear();
        bytesBuilder.add(remaining);
        bufferLen = remaining.length;
      }
    }

    for (final entry in entries) {
      final file = File(entry.path);
      final raf = file.openRead();
      await for (final chunk in raf) {
        await addChunk(chunk);
      }
    }

    if (bufferLen > 0) {
      final digest = sha1.convert(bytesBuilder.toBytes());
      pieceHashes.add(digest.bytes);
    }

    final info = <String, dynamic>{
      'name': name,
      'piece length': pieceLength,
      'pieces': Uint8List.fromList(pieceHashes.toBytes()),
    };

    if (type == FileSystemEntityType.file) {
      info['length'] = entries.first.length;
    } else {
      final files = entries
          .map(
            (e) => {
              'length': e.length,
              'path': e.relativePath.split(p.separator),
            },
          )
          .toList();
      info['files'] = files;
    }

    final metadict = <String, dynamic>{
      'announce': 'https://tracker.openbittorrent.com:443/announce',
      'info': info,
    };

    final torrentBytes = bencode(metadict);
    final torrentFileName = '$name.torrent';
    final torrentFilePath = p.join(baseDir.path, torrentFileName);
    final torrentFile = File(torrentFilePath);
    await torrentFile.writeAsBytes(torrentBytes, flush: true);

    await addTorrentFromTorrentFile(torrentFilePath);
  }
}

class _FileEntry {
  final String path;
  final String relativePath;
  final int length;

  _FileEntry(this.path, this.relativePath, this.length);
}
