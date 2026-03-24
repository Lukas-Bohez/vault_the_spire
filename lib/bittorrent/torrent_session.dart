import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:vault_the_spire/bittorrent/dht.dart';
import 'package:vault_the_spire/bittorrent/piece_manager.dart';
import 'package:vault_the_spire/bittorrent/torrent_file.dart';
import 'package:vault_the_spire/bittorrent/magnet_link.dart';
import 'package:vault_the_spire/vault_swarm/vault_piece.dart';

class TorrentStatus {
  final int downloaded;
  final int uploaded;
  final double progress;
  final String state;

  TorrentStatus({
    required this.downloaded,
    required this.uploaded,
    required this.progress,
    required this.state,
  });
}

abstract class TorrentSession {
  final TorrentMetadata? metadata;
  final PieceManager pieceManager;
  final DhtEngine? dhtEngine;
  final StreamController<TorrentStatus> _statusCtrl =
      StreamController.broadcast();

  TorrentSession({this.metadata, required this.pieceManager, this.dhtEngine});

  Stream<TorrentStatus> get statusStream => _statusCtrl.stream;

  Future<void> onPieceReceived(int index, Uint8List data);

  Future<void> start() async {
    final currentPieces = await pieceManager.getPieceMap();

    final downloaded =
        currentPieces.where((have) => have).length * (metadata?.pieceLength ?? 0);
    _statusCtrl.add(
      TorrentStatus(
        downloaded: downloaded,
        uploaded: 0,
        progress: currentPieces.isEmpty
            ? 0
            : currentPieces.where((e) => e).length /
                  (metadata?.pieceHashes.length ?? 1),
        state: 'starting',
      ),
    );

    if ((metadata?.trackers.isNotEmpty ?? false) && dhtEngine != null) {
      for (final tracker in metadata!.trackers) {
        await _announceTracker(tracker);
      }
    }

    if ((metadata?.infoHashV1.isNotEmpty ?? false) && dhtEngine != null) {
      final peers = await _bootstrapDht(metadata!.infoHashV1);
      _statusCtrl.add(
        TorrentStatus(
          downloaded: downloaded,
          uploaded: 0,
          progress: currentPieces.isEmpty
              ? 0
              : currentPieces.where((e) => e).length /
                    (metadata?.pieceHashes.length ?? 1),
          state: 'peers_found:${peers.length}',
        ),
      );
    }

    _statusCtrl.add(
      TorrentStatus(
        downloaded: downloaded,
        uploaded: 0,
        progress: currentPieces.isEmpty
            ? 0
            : currentPieces.where((e) => e).length /
                  (metadata?.pieceHashes.length ?? 1),
        state: 'idle',
      ),
    );
  }

  Future<void> _announceTracker(String tracker) async {
    if (metadata == null || metadata!.infoHashV1.isEmpty) return;
    try {
      final bencoded = Uri(
        queryParameters: {
          'info_hash': Uri.encodeComponent(metadata!.infoHashV1),
          'peer_id': '-VS0001-012345678901',
          'port': '6881',
          'uploaded': '0',
          'downloaded': '0',
          'left': '0',
          'compact': '1',
          'event': 'started',
        },
      ).query;
      final url = '$tracker?$bencoded';
      await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Future<List<DhtNodeInfo>> _bootstrapDht(String infoHash) async {
    if (dhtEngine == null) return [];
    return dhtEngine!.routingTable.findClosest(infoHash, 8);
  }

  void dispose() {
    _statusCtrl.close();
  }

  static Future<StandardTorrentSession> openFromTorrentFile(
    Uint8List torrentData,
    Directory appDir,
    DhtEngine dhtEngine,
  ) async {
    return StandardTorrentSession.openFromTorrentFile(torrentData, appDir, dhtEngine);
  }
}

class StandardTorrentSession extends TorrentSession {
  StandardTorrentSession({
    required super.metadata,
    required super.pieceManager,
    required super.dhtEngine,
  });

  @override
  Future<void> onPieceReceived(int index, Uint8List data) async {
    await pieceManager.writePiece(index, data);
  }

  static Future<StandardTorrentSession> openFromTorrentFile(
    Uint8List torrentData,
    Directory appDir,
    DhtEngine dhtEngine,
  ) async {
    final metadata = TorrentFileParser.parse(torrentData);
    final manager = PieceManager(
      infoHash: metadata.infoHashV1,
      pieceLength: metadata.pieceLength,
      totalPieces: metadata.pieceHashes.length,
      appDirectory: appDir,
    );
    await manager.initialize();
    return StandardTorrentSession(
      metadata: metadata,
      pieceManager: manager,
      dhtEngine: dhtEngine,
    );
  }

  static StandardTorrentSession openFromMagnet(
    String uri,
    Directory appDir,
    DhtEngine dhtEngine,
  ) {
    final link = MagnetLink.parse(uri);
    if (link.infoHashV2 == null && link.infoHashV1 == null) {
      throw ArgumentError('Magnet link must include btih or btmh infohash');
    }

    final metadata = TorrentMetadata(
      infoHashV1: link.infoHashV1 ?? '',
      infoHashV2: link.infoHashV2,
      name: link.displayName ?? 'magnet',
      pieceLength: 0,
      pieceHashes: [],
      files: [],
      trackers: link.trackers,
      webSeeds: [],
    );
    final manager = PieceManager(
      infoHash: metadata.infoHashV1.isNotEmpty ? metadata.infoHashV1 : metadata.infoHashV2!,
      pieceLength: 16384,
      totalPieces: 0,
      appDirectory: appDir,
    );
    return StandardTorrentSession(
      metadata: metadata,
      pieceManager: manager,
      dhtEngine: dhtEngine,
    );
  }
}

class VaultTorrentSession extends TorrentSession {
  final Uint8List key;

  VaultTorrentSession({
    required super.metadata,
    required this.key,
    required super.pieceManager,
    super.dhtEngine,
  });

  @override
  Future<void> onPieceReceived(int index, Uint8List data) async {
    final decryptedPiece = VaultPiece.decryptPiece(data, key);
    await pieceManager.writePiece(index, decryptedPiece);
  }
}

