import 'dart:async';
import 'dart:math';

import 'package:vault_the_spire/models/torrent.dart';
import 'package:vault_the_spire/services/torrent_service.dart';

class TorrentEngineStatus {
  final String torrentId;
  final int downloaded;
  final int uploaded;
  final double progress;
  final String state;
  final int peers;

  TorrentEngineStatus({
    required this.torrentId,
    required this.downloaded,
    required this.uploaded,
    required this.progress,
    required this.state,
    required this.peers,
  });
}

class TorrentEngineService {
  TorrentEngineService._();

  static final TorrentEngineService instance = TorrentEngineService._();

  final Map<String, Timer> _runningDownloads = {};
  final StreamController<TorrentEngineStatus> _statusController =
      StreamController.broadcast();

  Stream<TorrentEngineStatus> get statusStream => _statusController.stream;

  bool isRunning(String torrentId) => _runningDownloads.containsKey(torrentId);

  Future<void> startTorrent(String torrentId) async {
    if (isRunning(torrentId)) return;

    final torrent = await TorrentService.instance.getTorrentById(torrentId);
    if (torrent == null) throw StateError('Torrent not found: $torrentId');

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
        // Insufficient metadata, just increment bytes and stay queued.
        await TorrentService.instance.updateProgress(
          torrentId,
          latest.bytesDown + 1024,
          latest.bytesUp,
        );
        return;
      }

      final pieceMap =
          (latest.piecesHave?.split(',') ??
                  List.filled(latest.totalPieces!, '0'))
              .map((e) => e == '1')
              .toList();

      final nextIndex = pieceMap.indexWhere((have) => !have);
      if (nextIndex == -1) {
        await TorrentService.instance.updateTorrentStatus(
          torrentId,
          'completed',
        );
        stopTorrent(torrentId);
        return;
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
      _statusController.add(
        TorrentEngineStatus(
          torrentId: torrentId,
          downloaded: newDownloaded,
          uploaded: newUploaded,
          progress: progress,
          state: 'downloading',
          peers: 8,
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
        peers: 0,
      ),
    );
  }

  void stopTorrent(String torrentId) {
    final timer = _runningDownloads.remove(torrentId);
    if (timer != null) {
      timer.cancel();
    }
    TorrentService.instance.updateTorrentStatus(torrentId, 'paused');
    _statusController.add(
      TorrentEngineStatus(
        torrentId: torrentId,
        downloaded: 0,
        uploaded: 0,
        progress: 0.0,
        state: 'paused',
        peers: 0,
      ),
    );
  }

  void stopAll() {
    for (final timer in _runningDownloads.values) {
      timer.cancel();
    }
    _runningDownloads.clear();
  }
}
