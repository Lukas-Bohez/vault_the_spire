import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dtorrent_task_v2/dtorrent_task_v2.dart' as dt;
import 'package:path_provider/path_provider.dart';

import 'package:vault_the_spire/models/torrent.dart';
import 'package:vault_the_spire/services/torrent_service.dart';

/// The single status event emitted by the engine to the UI.
class TorrentEngineStatus {
  final String torrentId;
  final int downloaded;
  final int uploaded;
  final double progress;
  final String state;
  final int peers;
  final double downloadSpeed;
  final double uploadSpeed;

  const TorrentEngineStatus({
    required this.torrentId,
    required this.downloaded,
    required this.uploaded,
    required this.progress,
    required this.state,
    required this.peers,
    required this.downloadSpeed,
    required this.uploadSpeed,
  });
}

class TorrentEngineService {
  TorrentEngineService._();
  static final TorrentEngineService instance = TorrentEngineService._();

  // One TorrentTask per active torrent, keyed by info-hash.
  final Map<String, dt.TorrentTask> _tasks = {};

  // One poll timer per active torrent.
  final Map<String, Timer> _timers = {};

  final _statusController = StreamController<TorrentEngineStatus>.broadcast();

  Stream<TorrentEngineStatus> get statusStream => _statusController.stream;

  bool isRunning(String torrentId) => _tasks.containsKey(torrentId);

  /// Starts downloading (or seeding) a torrent.
  Future<void> startTorrent(String torrentId) async {
    if (isRunning(torrentId)) return;

    final torrent = await TorrentService.instance.getTorrentById(torrentId);
    if (torrent == null) throw StateError('Torrent not found: $torrentId');

    // Decide save directory.
    final saveDir = await _resolveSaveDir(torrent);

    // Build TorrentModel from either a .torrent file or a magnet link.
    dt.TorrentModel dtModel;
    if (torrent.type == 'torrent_file' && torrent.filePath != null) {
      dtModel = await dt.TorrentModel.parse(torrent.filePath!);
    } else if (torrent.magnetLink != null) {
      // dtorrent_task_v2 can resolve magnet metadata from peers/DHT itself.
      final magnet = dt.MagnetParser.parse(torrent.magnetLink!);
      if (magnet == null) throw FormatException('Invalid magnet link');

      final downloader = dt.MetadataDownloader.fromMagnet(torrent.magnetLink!);
      final metadataCompleter = Completer<Uint8List>();
      final metadataListener = downloader.createListener();
      metadataListener
        ..on<dt.MetaDataDownloadComplete>((event) {
          if (!metadataCompleter.isCompleted) {
            metadataCompleter.complete(Uint8List.fromList(event.data));
          }
        })
        ..on<dt.MetaDataDownloadFailed>((event) {
          if (!metadataCompleter.isCompleted) {
            metadataCompleter.completeError(FormatException(event.error));
          }
        });

      await downloader.startDownload();
      final bytes = await metadataCompleter.future.timeout(
        const Duration(minutes: 2),
      );
      dtModel = dt.TorrentParser.parseBytes(bytes);
    } else {
      throw StateError('Torrent has no .torrent file path and no magnet link');
    }

    final task = dt.TorrentTask.newTask(dtModel, saveDir);

    // Wire events.
    final listener = task.createListener();
    listener
      ..on<dt.TaskCompleted>((_) async {
        await TorrentService.instance.updateTorrentStatus(
          torrentId,
          'completed',
        );
        _emit(torrentId, task, 'completed');
        _cleanup(torrentId);
      })
      ..on<dt.TaskStopped>((_) {
        _cleanup(torrentId);
      });

    await task.start();
    _tasks[torrentId] = task;

    // Poll every 2 seconds for speed/peer stats (same cadence as before).
    _timers[torrentId] = Timer.periodic(const Duration(seconds: 2), (_) {
      _emit(torrentId, task, 'downloading');
    });

    await TorrentService.instance.updateTorrentStatus(torrentId, 'downloading');
  }

  void _emit(String torrentId, dt.TorrentTask task, String state) {
    final progress = task.progress; // 0.0 – 1.0
    final downloaded = task.downloaded ?? 0; // bytes
    final uploaded = task.stateFile?.uploaded ?? 0; // bytes
    final peers = task.connectedPeersNumber;
    final dlSpeed = task.currentDownloadSpeed; // bytes/s
    final ulSpeed = task.uploadSpeed; // bytes/s

    _statusController.add(
      TorrentEngineStatus(
        torrentId: torrentId,
        downloaded: downloaded,
        uploaded: uploaded,
        progress: progress,
        state: state,
        peers: peers,
        downloadSpeed: dlSpeed,
        uploadSpeed: ulSpeed,
      ),
    );

    // Persist progress to DB without awaiting (fire-and-forget).
    TorrentService.instance.updateProgress(torrentId, downloaded, uploaded);
  }

  void _cleanup(String torrentId) {
    _timers.remove(torrentId)?.cancel();
    _tasks.remove(torrentId);
  }

  void stopTorrent(String torrentId) {
    _tasks[torrentId]?.stop();
    _cleanup(torrentId);
    TorrentService.instance.updateTorrentStatus(torrentId, 'paused');
  }

  void pauseTorrent(String torrentId) {
    _tasks[torrentId]?.pause();
    TorrentService.instance.updateTorrentStatus(torrentId, 'paused');
  }

  void resumeTorrent(String torrentId) {
    _tasks[torrentId]?.resume();
    TorrentService.instance.updateTorrentStatus(torrentId, 'downloading');
  }

  void stopAll() {
    for (final id in _tasks.keys.toList()) {
      stopTorrent(id);
    }
  }

  Future<String> _resolveSaveDir(TorrentModel torrent) async {
    if (torrent.filePath != null) {
      final dir = Directory(torrent.filePath!);
      if (await dir.exists()) return dir.path;
      final parent = File(torrent.filePath!).parent;
      if (await parent.exists()) return parent.path;
    }
    final docs = await getApplicationDocumentsDirectory();
    return docs.path;
  }
}
