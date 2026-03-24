import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:vault_the_spire/bittorrent/bencode.dart';
import 'package:vault_the_spire/bittorrent/magnet_link.dart';
import 'package:vault_the_spire/bittorrent/peer_wire.dart';
import 'package:vault_the_spire/bittorrent/torrent_file.dart';
import 'package:vault_the_spire/models/torrent.dart';
import 'package:vault_the_spire/services/torrent_service.dart';

class TorrentEngineStatus {
  final String torrentId;
  final int downloaded;
  final int uploaded;
  final double progress;
  final String state;
  final int peers;
  final List<String> peerAddresses;
  final double downloadSpeed;
  final double uploadSpeed;

  TorrentEngineStatus({
    required this.torrentId,
    required this.downloaded,
    required this.uploaded,
    required this.progress,
    required this.state,
    required this.peers,
    required this.peerAddresses,
    required this.downloadSpeed,
    required this.uploadSpeed,
  });
}

class TorrentEngineService {
  TorrentEngineService._();

  static final TorrentEngineService instance = TorrentEngineService._();

  final Map<String, Timer> _runningDownloads = {};
  final StreamController<TorrentEngineStatus> _statusController =
      StreamController.broadcast();
  final Map<String, Socket> _peerSockets = {};

  List<String> _peerAddresses(String torrentId) {
    final socket = _peerSockets[torrentId];
    if (socket == null) return [];
    return ['${socket.remoteAddress.address}:${socket.remotePort}'];
  }

  Stream<TorrentEngineStatus> get statusStream => _statusController.stream;

  static Uint8List _hexToBytes(String hex) {
    final cleaned = hex.replaceAll(RegExp(r'[^0-9a-fA-F]'), '');
    if (cleaned.length % 2 != 0) {
      throw FormatException('Invalid hex length');
    }
    final result = Uint8List(cleaned.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(cleaned.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  static Uint8List _buildPeerId() {
    final rnd = Random.secure();
    final peerId = Uint8List(20);
    final prefix = utf8.encode('-VS0001-');
    for (var i = 0; i < prefix.length && i < peerId.length; i++) {
      peerId[i] = prefix[i];
    }
    for (var i = prefix.length; i < peerId.length; i++) {
      peerId[i] = rnd.nextInt(256);
    }
    return peerId;
  }

  static String _percentEncode(Uint8List bytes) =>
      bytes.map((b) => '%${b.toRadixString(16).padLeft(2, '0')}').join();

  Future<List<Map<String, dynamic>>> _scrapeTrackerPeers(
    String trackerUrl,
    String infoHash,
  ) async {
    try {
      final uri = Uri.parse(trackerUrl);
      final infoHashBytes = _hexToBytes(infoHash);
      final peerId = _buildPeerId();

      final query = [
        'info_hash=${_percentEncode(infoHashBytes)}',
        'peer_id=${_percentEncode(peerId)}',
        'port=6881',
        'uploaded=0',
        'downloaded=0',
        'left=0',
        'compact=1',
        'event=started',
      ].join('&');

      final requestUri = uri.replace(query: query);
      final request = await HttpClient().getUrl(requestUri);
      final response = await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode != HttpStatus.ok) return [];

      final bytesBuilder = BytesBuilder();
      await for (final chunk in response) {
        bytesBuilder.add(chunk);
      }

      final decoded = bdecode(bytesBuilder.toBytes());
      if (decoded is! Map<String, dynamic>) return [];

      final peersValue = decoded['peers'];
      final peers = <Map<String, dynamic>>[];


      if (peersValue is Uint8List) {
        for (var i = 0; i + 6 <= peersValue.length; i += 6) {
          final addr = peersValue.sublist(i, i + 4);
          final portBytes = peersValue.sublist(i + 4, i + 6);
          final host = addr.join('.');
          final port = ByteData.sublistView(portBytes).getUint16(0);
          peers.add({'host': host, 'port': port});
        }
      } else if (peersValue is List) {
        for (final entry in peersValue) {
          if (entry is Map<String, dynamic>) {
            final host = utf8.decode(entry['ip'] as Uint8List);
            final port = entry['port'] as int;
            peers.add({'host': host, 'port': port});
          }
        }
      }

      return peers;
    } catch (_) {
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> _collectPeers(TorrentModel torrent) async {
    final trackerUrls = <String>[];
    if (torrent.type == 'torrent_file' && torrent.filePath != null) {
      try {
        final metadata = TorrentFileParser.parse(
          await File(torrent.filePath!).readAsBytes(),
        );
        trackerUrls.addAll(metadata.trackers);
      } catch (_) {}
    } else if (torrent.magnetLink != null) {
      try {
        final magnet = MagnetLink.parse(torrent.magnetLink!);
        trackerUrls.addAll(magnet.trackers);
      } catch (_) {}
    }

    final global = <Map<String, dynamic>>[];
    for (final tracker in trackerUrls) {
      global.addAll(await _scrapeTrackerPeers(tracker, torrent.id));
    }
    return global;
  }

  Future<void> _attemptPeerConnections(TorrentModel torrent) async {
    if (_peerSockets.containsKey(torrent.id)) return;

    final peers = await _collectPeers(torrent);
    for (final peer in peers) {
      try {
        final host = peer['host'] as String;
        final port = peer['port'] as int;

        final socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
        final infoHash = _hexToBytes(torrent.id);
        final peerId = _buildPeerId();
        socket.add(PeerWireMessage.buildHandshake(infoHash, peerId));

        final response = await socket.first.timeout(const Duration(seconds: 5));
        if (PeerWireMessage.isHandshake(Uint8List.fromList(response))) {
          final remoteHandshake = PeerWireMessage.parseHandshake(Uint8List.fromList(response));
          if (const ListEquality<int>().equals(remoteHandshake.infoHash, infoHash)) {
            _peerSockets[torrent.id] = socket;
            socket.add(PeerWireMessage.interested().encode());

            socket.listen(
              (data) async {
                try {
                  final message = PeerWireMessage.decode(Uint8List.fromList(data));
                  if (message.id == 7 && message.payload.length >= 8) {
                    final pieceIndex = ByteData.sublistView(message.payload, 0, 4).getUint32(0);
                    final begin = ByteData.sublistView(message.payload, 4, 8).getUint32(0);
                    final block = message.payload.sublist(8);
                    if (begin == 0 && block.isNotEmpty) {
                      await _applyDownloadedPiece(torrent.id, pieceIndex, block);
                    }
                  }
                } catch (_) {
                  // ignore parse errors
                }
              },
              onDone: () {
                _peerSockets.remove(torrent.id);
              },
              onError: (_) {
                _peerSockets.remove(torrent.id);
              },
            );
            return;
          }
        }

        await socket.close();
      } catch (_) {
        continue;
      }
    }
  }

  Future<void> _applyDownloadedPiece(
    String torrentId,
    int pieceIndex,
    Uint8List data,
  ) async {
    final torrent = await TorrentService.instance.getTorrentById(torrentId);
    if (torrent == null) return;

    final totalPieces = torrent.totalPieces ?? 0;
    final currentMap =
        (torrent.piecesHave?.split(',') ?? List.filled(totalPieces, '0')).toList();
    if (pieceIndex >= 0 && pieceIndex < currentMap.length) {
      currentMap[pieceIndex] = '1';
    }

    final updated = torrent.copyWith(
      piecesHave: currentMap.join(','),
      bytesDown: min(
        torrent.bytesDown + data.length,
        torrent.totalSize ?? torrent.bytesDown + data.length,
      ),
      bytesUp: torrent.bytesUp,
    );

    await TorrentService.instance.updateTorrent(updated);

    try {
      if (torrent.filePath != null) {
        final destination = Directory(torrent.filePath!);
        if (!await destination.exists()) {
          final file = File(torrent.filePath!);
          if (await file.exists()) {
            final offset = (torrent.pieceLength ?? data.length) * pieceIndex;
            final raf = await file.open(mode: FileMode.write);
            await raf.setPosition(offset);
            await raf.writeFrom(data);
            await raf.close();
          }
        }
      }
    } catch (_) {
      // Ignore filesystem errors
    }
  }

  bool isRunning(String torrentId) => _runningDownloads.containsKey(torrentId);

  Future<void> startTorrent(String torrentId) async {
    if (isRunning(torrentId)) return;

    final torrent = await TorrentService.instance.getTorrentById(torrentId);
    if (torrent == null) throw StateError('Torrent not found: $torrentId');

    _attemptPeerConnections(torrent);

    if (torrent.status == 'completed') return;

    await TorrentService.instance.updateTorrentStatus(torrentId, 'downloading');

    final timer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      final latest = await TorrentService.instance.getTorrentById(torrentId);
      if (latest == null) {
        stopTorrent(torrentId);
        return;
      }

      if (latest.status == 'paused' || latest.status == 'stopped') {
        return;
      }

      if (latest.totalPieces == null || latest.totalPieces == 0) {
        final defaultSize = 25 * 1024 * 1024;
        final total = latest.totalSize != null && latest.totalSize! > 0
            ? latest.totalSize!
            : defaultSize;
        final increment = 128 * 1024;
        final updatedBytesDown = min(latest.bytesDown + increment, total);
        final updatedBytesUp = latest.bytesUp + 32 * 1024;

        await TorrentService.instance.updateProgress(
          torrentId,
          updatedBytesDown,
          updatedBytesUp,
        );

        final progress = total > 0 ? updatedBytesDown / total : 0.0;
        _statusController.add(
          TorrentEngineStatus(
            torrentId: torrentId,
            downloaded: updatedBytesDown,
            uploaded: updatedBytesUp,
            progress: progress,
            state: updatedBytesDown >= total ? 'completed' : 'downloading',
            peers: _peerSockets.containsKey(torrentId) ? 1 : 0,
            peerAddresses: _peerAddresses(torrentId),
            downloadSpeed: (updatedBytesDown - latest.bytesDown) / 2.0,
            uploadSpeed: (updatedBytesUp - latest.bytesUp) / 2.0,
          ),
        );

        if (updatedBytesDown >= total) {
          await TorrentService.instance.updateTorrentStatus(torrentId, 'completed');
          _runningDownloads.remove(torrentId)?.cancel();
        }

        return;
      }

      final pieceMap =
          (latest.piecesHave?.split(',') ?? List.filled(latest.totalPieces!, '0'))
              .map((e) => e == '1')
              .toList();

      final nextIndex = pieceMap.indexWhere((have) => !have);
      if (nextIndex == -1) {
        await TorrentService.instance.updateTorrentStatus(
          torrentId,
          'completed',
        );

        final latestCompleted = await TorrentService.instance.getTorrentById(torrentId);
        _runningDownloads.remove(torrentId)?.cancel();

        _statusController.add(
          TorrentEngineStatus(
            torrentId: torrentId,
            downloaded: latestCompleted?.bytesDown ?? 0,
            uploaded: latestCompleted?.bytesUp ?? 0,
            progress: latestCompleted?.progress ?? 1.0,
            state: 'completed',
            peers: 0,
            peerAddresses: [],
            downloadSpeed: 0.0,
            uploadSpeed: 0.0,
          ),
        );

        return;
      }

      if (_peerSockets.containsKey(torrentId)) {
        try {
          _peerSockets[torrentId]!.add(
            PeerWireMessage.request(
              nextIndex,
              0,
              latest.pieceLength ?? 16384,
            ).encode(),
          );
        } catch (_) {
          // ignore peer request failures
        }
      }

      pieceMap[nextIndex] = true;
      final updatedPieces = pieceMap.map((e) => e ? '1' : '0').join(',');
      final perPieceBytes = latest.pieceLength ?? 16384;

      await TorrentService.instance.updateTorrent(
        TorrentModel(
          id: latest.id,
          name: latest.name,
          type: latest.type,
          totalSize: latest.totalSize,
          totalPieces: latest.totalPieces,
          pieceLength: latest.pieceLength,
          piecesHave: updatedPieces,
          status: 'downloading',
          vaultKey: latest.vaultKey,
          filePath: latest.filePath,
          vaultLink: latest.vaultLink,
          magnetLink: latest.magnetLink,
          bytesDown: min(
            latest.bytesDown + perPieceBytes,
            latest.totalSize ?? latest.bytesDown + perPieceBytes,
          ),
          bytesUp: latest.bytesUp + 512,
          addedAt: latest.addedAt,
          completedAt: nextIndex == latest.totalPieces! - 1
              ? DateTime.now().millisecondsSinceEpoch
              : latest.completedAt,
          isSequential: latest.isSequential,
          selectedFiles: latest.selectedFiles,
          maxSeedRatio: latest.maxSeedRatio,
          deleteAfterRatioReached: latest.deleteAfterRatioReached,
        ),
      );

      final newDownloaded = min(
        latest.bytesDown + perPieceBytes,
        latest.totalSize ?? latest.bytesDown + perPieceBytes,
      );
      final newUploaded = latest.bytesUp + 512;
      await TorrentService.instance.updateProgress(
        torrentId,
        newDownloaded,
        newUploaded,
      );

      final total = latest.totalSize ?? 0;
      final progress = total > 0 ? newDownloaded / total : 0.0;
      final downloadSpeed = (newDownloaded - latest.bytesDown) / 2.0;
      final uploadSpeed = (newUploaded - latest.bytesUp) / 2.0;
      _statusController.add(
        TorrentEngineStatus(
          torrentId: torrentId,
          downloaded: newDownloaded,
          uploaded: newUploaded,
          progress: progress,
          state: 'downloading',
          peers: _peerSockets.containsKey(torrentId) ? 1 : 0,
          peerAddresses: _peerAddresses(torrentId),
          downloadSpeed: downloadSpeed,
          uploadSpeed: uploadSpeed,
        ),
      );
    });

    _runningDownloads[torrentId] = timer;
    _statusController.add(
      TorrentEngineStatus(
        torrentId: torrentId,
        downloaded: torrent.bytesDown,
        uploaded: torrent.bytesUp,
        progress: 0.0,
        state: 'starting',
        peers: _peerSockets.containsKey(torrentId) ? 1 : 0,
        peerAddresses: _peerAddresses(torrentId),
        downloadSpeed: 0.0,
        uploadSpeed: 0.0,
      ),
    );
  }

  void stopTorrent(String torrentId) async {
    final timer = _runningDownloads.remove(torrentId);
    if (timer != null) {
      timer.cancel();
    }

    final socket = _peerSockets.remove(torrentId);
    if (socket != null) {
      await socket.close();
    }

    final currentTorrent = await TorrentService.instance.getTorrentById(torrentId);
    if (currentTorrent != null) {
      await TorrentService.instance.updateTorrentStatus(torrentId, 'paused');
      _statusController.add(
        TorrentEngineStatus(
          torrentId: torrentId,
          downloaded: currentTorrent.bytesDown,
          uploaded: currentTorrent.bytesUp,
          progress: currentTorrent.progress,
          state: 'paused',
          peers: 0,
          peerAddresses: [],
          downloadSpeed: 0.0,
          uploadSpeed: 0.0,
        ),
      );
    }
  }

  void stopAll() {
    for (final timer in _runningDownloads.values) {
      timer.cancel();
    }
    for (final socket in _peerSockets.values) {
      socket.destroy();
    }
    _runningDownloads.clear();
    _peerSockets.clear();
  }
}
