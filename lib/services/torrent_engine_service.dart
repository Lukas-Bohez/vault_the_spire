import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart' as dt;
import 'package:path_provider/path_provider.dart';

import 'package:vault_the_spire/models/torrent.dart';
import 'package:vault_the_spire/services/torrent_service.dart';

class TorrentEngineStatus {
  final String torrentId;
  final int downloaded;
  final int uploaded;
  final double progress;
  final String state;
  final int peers;
  final double downloadSpeed;
  final double uploadSpeed;
  final int seeders;
  final int leechers;

  const TorrentEngineStatus({
    required this.torrentId,
    required this.downloaded,
    required this.uploaded,
    required this.progress,
    required this.state,
    required this.peers,
    required this.downloadSpeed,
    required this.uploadSpeed,
    this.seeders = 0,
    this.leechers = 0,
  });
}

class TorrentEngineService {
  TorrentEngineService._();
  static final TorrentEngineService instance = TorrentEngineService._();

  final Map<String, dt.TorrentTask> _tasks = {};
  final Map<String, Timer> _timers = {};
  final Map<String, Timer> _scrapeTimers = {};

  final _statusController = StreamController<TorrentEngineStatus>.broadcast();
  Stream<TorrentEngineStatus> get statusStream => _statusController.stream;

  bool isRunning(String torrentId) => _tasks.containsKey(torrentId);

  Future<void> startTorrent(String torrentId) async {
    if (isRunning(torrentId)) return;

    final torrent = await TorrentService.instance.getTorrentById(torrentId);
    if (torrent == null) throw StateError('Torrent not found: $torrentId');

    final saveDir = await _resolveSaveDir(torrent);

    if (torrent.type == 'torrent_file' && torrent.filePath != null) {
      await _startFromFile(torrent, saveDir);
    } else if (torrent.magnetLink != null) {
      await _startFromMagnet(torrent, saveDir);
    } else {
      throw StateError('Torrent has no .torrent file path and no magnet link');
    }
  }

  Future<void> _startFromFile(TorrentModel torrent, String saveDir) async {
    final dtModel = await dt.TorrentModel.parse(torrent.filePath!);

    // Write totalSize into DB so UI stops showing 0 B.
    final totalBytes = dtModel.files.fold<int>(0, (s, f) => s + f.length);
    if (totalBytes > 0 && (torrent.totalSize ?? 0) != totalBytes) {
      await TorrentService.instance.updateTorrent(
        torrent.copyWith(totalSize: totalBytes),
      );
    }

    final task = dt.TorrentTask.newTask(dtModel, saveDir);
    await task.start();
    _tasks[torrent.id] = task;
    _wireEvents(torrent.id, task);
    _startPolling(torrent.id, task);
    await TorrentService.instance.updateTorrentStatus(
      torrent.id,
      'downloading',
    );
  }

  Future<void> _startFromMagnet(TorrentModel torrent, String saveDir) async {
    final magnet = dt.MagnetParser.parse(torrent.magnetLink!);
    if (magnet == null) throw FormatException('Invalid magnet link');

    // Step 1: fetch metadata from peers/DHT.
    final downloader = dt.MetadataDownloader.fromMagnet(torrent.magnetLink!);
    final completer = Completer<dt.TorrentModel>();

    downloader.createListener()
      ..on<dt.MetaDataDownloadComplete>((event) {
        if (completer.isCompleted) return;
        try {
          // event.data is the raw bencoded info-dict.
          // Compose minimal map and parse into a TorrentModel.
          final infoDict = decode(Uint8List.fromList(event.data));
          final model = dt.TorrentParser.parseFromMap({'info': infoDict});
          completer.complete(model);
        } catch (e) {
          completer.completeError(e);
        }
      })
      ..on<dt.MetaDataDownloadFailed>((event) {
        if (!completer.isCompleted) {
          completer.completeError(StateError(event.error));
        }
      });

    downloader.startDownload();

    dt.TorrentModel dtModel;
    try {
      dtModel = await completer.future.timeout(const Duration(minutes: 3));
    } on TimeoutException {
      // MetadataDownloader does not expose a stop method in this version,
      // so we only rethrow and avoid calling a non-existent API.
      rethrow;
    }

    // Step 2: write size to DB before download starts.
    final totalBytes = dtModel.files.fold<int>(0, (s, f) => s + f.length);
    if (totalBytes > 0) {
      await TorrentService.instance.updateTorrent(
        torrent.copyWith(totalSize: totalBytes),
      );
    }

    // Step 3: create task with web seeds from the magnet if present.
    final task = dt.TorrentTask.newTask(
      dtModel,
      saveDir,
      false,
      magnet.webSeeds.isNotEmpty ? magnet.webSeeds : null,
      magnet.acceptableSources.isNotEmpty ? magnet.acceptableSources : null,
    );

    if (magnet.selectedFileIndices?.isNotEmpty == true) {
      task.applySelectedFiles(magnet.selectedFileIndices!);
    }

    await task.start();

    // Step 4: hand over peers that already connected during metadata fetch —
    // this is what gets pieces flowing immediately instead of rediscovering peers.
    for (final peer in downloader.activePeers) {
      task.addPeer(peer.address, dt.PeerSource.manual, type: peer.type);
    }

    // Step 5: announce to trackers from the magnet link.
    if (magnet.trackers.isNotEmpty && magnet.infoHashString.isNotEmpty) {
      final hashBytes = Uint8List.fromList(
        List.generate(magnet.infoHashString.length ~/ 2, (i) {
          return int.parse(
            magnet.infoHashString.substring(i * 2, i * 2 + 2),
            radix: 16,
          );
        }),
      );
      for (final url in magnet.trackers) {
        task.startAnnounceUrl(url, hashBytes);
      }
    }

    _tasks[torrent.id] = task;
    _wireEvents(torrent.id, task);
    _startPolling(torrent.id, task);
    await TorrentService.instance.updateTorrentStatus(
      torrent.id,
      'downloading',
    );
  }

  void _wireEvents(String torrentId, dt.TorrentTask task) {
    task.createListener()
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
  }

  void _startPolling(String torrentId, dt.TorrentTask task) {
    // Emit speed/progress every 2 s.
    _timers[torrentId] = Timer.periodic(const Duration(seconds: 2), (_) {
      _emit(torrentId, task, 'downloading');
    });

    // Scrape trackers for seeder/leecher counts every 30 s.
    _scrapeTimers[torrentId] = Timer.periodic(const Duration(seconds: 30), (_) {
      _doScrape(torrentId, task);
    });
    // Immediate first scrape.
    _doScrape(torrentId, task);
  }

  Future<void> _doScrape(String torrentId, dt.TorrentTask task) async {
    try {
      final result = await task.scrapeTracker();
      if (!result.isSuccess) return;
      final stats = result.getStatsForInfoHash(task.metaInfo.infoHash);
      if (stats == null) return;
      final existing = await TorrentService.instance.getTorrentById(torrentId);
      if (existing == null) return;
      await TorrentService.instance.updateTorrent(
        existing.copyWith(seeders: stats.complete, leechers: stats.incomplete),
      );
    } catch (_) {
      // Best-effort; never crash the engine.
    }
  }

  void _emit(String torrentId, dt.TorrentTask task, String state) {
    final downloaded = task.downloaded ?? 0;
    final uploaded =
        0; // dtorrent_task_v2 does not expose task.uploaded on this version
    final dlSpeed = task.currentDownloadSpeed;
    final ulSpeed = task.uploadSpeed;

    _statusController.add(
      TorrentEngineStatus(
        torrentId: torrentId,
        downloaded: downloaded,
        uploaded: uploaded,
        progress: task.progress,
        state: state,
        peers: task.connectedPeersNumber,
        downloadSpeed: dlSpeed,
        uploadSpeed: ulSpeed,
      ),
    );

    TorrentService.instance.updateProgress(torrentId, downloaded, 0);
  }

  void _cleanup(String torrentId) {
    _timers.remove(torrentId)?.cancel();
    _scrapeTimers.remove(torrentId)?.cancel();
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
