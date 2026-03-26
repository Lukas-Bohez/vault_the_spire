import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:vault_the_spire/bittorrent/bencode.dart';
import 'package:vault_the_spire/bittorrent/magnet_link.dart';
import 'package:vault_the_spire/bittorrent/torrent_file.dart';
import 'package:vault_the_spire/db/torrents_dao.dart';
import 'package:vault_the_spire/models/torrent.dart';
import 'package:vault_the_spire/services/torrent_engine_service.dart';

class TorrentAlreadyExistsException implements Exception {
  final String torrentId;
  TorrentAlreadyExistsException(this.torrentId);

  @override
  String toString() => 'Torrent already exists: $torrentId';
}

class TorrentService {
  TorrentService._();

  static final TorrentService instance = TorrentService._();

  static bool isTorrentOrMagnetUrl(String url) {
    final lower = url.trim().toLowerCase();
    return lower.startsWith('magnet:') || lower.endsWith('.torrent');
  }

  static String normalizeTorrentUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';

    final lower = trimmed.toLowerCase();
    if (lower.startsWith('magnet:') || lower.startsWith('file://')) {
      return trimmed;
    }

    if (lower.endsWith('.torrent')) {
      // Keep explicit .torrent paths as-is so we can support local files and web URLs.
      return trimmed;
    }

    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return trimmed;
    }

    return 'https://$trimmed';
  }

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

    final destinationDir = Directory(destinationPath);
    if (!await destinationDir.exists()) {
      throw FileSystemException(
        'Destination folder does not exist',
        destinationPath,
      );
    }

    await updateTorrent(
      existing.copyWith(
        status: 'downloading',
        bytesDown: existing.bytesDown,
        bytesUp: existing.bytesUp,
      ),
    );

    try {
      await TorrentEngineService.instance.startTorrent(
        id,
        destinationPath: destinationPath,
      );
    } catch (e, st) {
      debugPrint('TorrentEngine startTorrent failed: $e');
      debugPrint('$st');
      rethrow;
    }

    final completer = Completer<void>();
    StreamSubscription<TorrentEngineStatus>? subscription;
    subscription = TorrentEngineService.instance.statusStream
        .where((status) => status.torrentId == id)
        .listen((status) async {
          if (status.state == 'completed') {
            if (!completer.isCompleted) completer.complete();
          } else if (status.state == 'error') {
            if (!completer.isCompleted) {
              completer.completeError(
                StateError('Download failed for torrent $id'),
              );
            }
          }

          if (status.downloaded > 0) {
            await updateProgress(id, status.downloaded, status.uploaded);
          }
        });

    try {
      await completer.future.timeout(
        const Duration(hours: 12),
        onTimeout: () => throw TimeoutException('Torrent download timed out'),
      );
    } finally {
      await subscription.cancel();
      TorrentEngineService.instance.stopTorrent(id);
    }

    final completed = await getTorrentById(id);
    if (completed != null) {
      await updateTorrent(
        completed.copyWith(
          status: 'completed',
          completedAt: DateTime.now().millisecondsSinceEpoch,
          isSequential: true,
        ),
      );
    }
  }

  // ignore: unused_element
  Future<TorrentMetadata?> _loadTorrentMetadata(TorrentModel torrent) async {
    if (torrent.type == 'torrent_file' && torrent.filePath != null) {
      final file = File(torrent.filePath!);
      if (await file.exists()) {
        try {
          return TorrentFileParser.parse(await file.readAsBytes());
        } catch (_) {
          // fallback
        }
      }
    }
    return null;
  }

  // ignore: unused_element
  Future<void> _prepareTargetFiles(
    TorrentModel torrent,
    Directory destinationDir,
    TorrentMetadata? metadata,
    int totalSize,
  ) async {
    if (metadata != null && metadata.files.isNotEmpty) {
      for (final fileEntry in metadata.files) {
        final targetPath = p.join(destinationDir.path, fileEntry.path);
        final targetFile = File(targetPath);
        await targetFile.parent.create(recursive: true);
        final raf = await targetFile.open(mode: FileMode.write);
        await raf.truncate(fileEntry.length);
        await raf.close();
      }
    } else {
      final name = torrent.name.isNotEmpty ? torrent.name : torrent.id;
      final sanitized = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final filePath = p.join(destinationDir.path, '$sanitized.bin');
      final file = File(filePath);
      await file.parent.create(recursive: true);
      final raf = await file.open(mode: FileMode.write);
      await raf.truncate(totalSize);
      await raf.close();
    }
  }

  Future<void> setDestinationAndStart(String id, String destinationPath) async {
    final torrent = await getTorrentById(id);
    if (torrent == null) {
      throw StateError('Torrent not found: $id');
    }

    await updateTorrent(torrent.copyWith(status: 'downloading'));
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
      await TorrentEngineService.instance.forceRefresh(existing.id);
      throw TorrentAlreadyExistsException(existing.id);
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

    // Auto-start torrent file sessions for better UX.
    await updateTorrentStatus(metadata.infoHashV1, 'downloading');
    await TorrentEngineService.instance.startTorrent(metadata.infoHashV1);
  }

  Future<void> addTorrentFromMagnetLink(String uri) async {
    final magnet = MagnetLink.parse(uri);
    final infoHash = magnet.infoHashV1 ?? magnet.infoHashV2;
    if (infoHash == null || infoHash.isEmpty) {
      throw FormatException('Magnet link must contain btih or btmh infohash');
    }

    final existing = await TorrentsDao.instance.getTorrentById(infoHash);
    if (existing != null) {
      await TorrentEngineService.instance.forceRefresh(existing.id);
      throw TorrentAlreadyExistsException(existing.id);
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
    await updateTorrent(torrent.copyWith(status: 'downloading'));
    await TorrentEngineService.instance.startTorrent(infoHash);
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
