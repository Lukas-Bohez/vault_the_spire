import 'dart:async';
import 'dart:io';

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
  final int seeders;
  final int leechers;
  final double downloadSpeed; // bytes/s
  final double uploadSpeed;   // bytes/s

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
  final Map<String, Timer> _pollTimers = {};
  final Map<String, Timer> _scrapeTimers = {};

  final _statusController = StreamController<TorrentEngineStatus>.broadcast();
  Stream<TorrentEngineStatus> get statusStream => _statusController.stream;

  bool isRunning(String torrentId) => _tasks.containsKey(torrentId);

  Future<void> startTorrent(String torrentId) async {
    if (isRunning(torrentId)) return;
    final torrent = await TorrentService.instance.getTorrentById(torrentId);
    if (torrent == null) throw StateError('Torrent not found: $torrentId');

    if (torrent.type == 'torrent_file' && torrent.filePath != null) {
      await _startFromFile(torrent);
    } else if (torrent.magnetLink != null) {
      await _startFromMagnet(torrent);
    } else {
      throw StateError('Torrent has no source');
    }
  }

  Future<void> _startFromFile(TorrentModel torrent) async {
    // torrent.filePath is the path to the .torrent FILE, not a download directory.
    final dtModel = await dt.TorrentModel.parse(torrent.filePath!);
    final saveDir = await _defaultDownloadDir();

    // Persist size so UI shows real value immediately.
    final totalBytes = dtModel.files.fold<int>(0, (s, f) => s + f.length);
    if (totalBytes > 0 && (torrent.totalSize ?? 0) != totalBytes) {
      await TorrentService.instance
          .updateTorrent(torrent.copyWith(totalSize: totalBytes));
    }

    final task = dt.TorrentTask.newTask(dtModel, saveDir);

    // Register listeners BEFORE start() — an early TaskCompleted would be missed otherwise.
    _tasks[torrent.id] = task;
    _wireEvents(torrent.id, task);

    await task.start();

    // Announce to every tracker in the .torrent file.
    // infoHashBuffer is the correct Uint8List property — confirmed from working example.
    for (final url in dtModel.announces) {
      task.startAnnounceUrl(url, dtModel.infoHashBuffer);
    }

    // Also subscribe to public trackers so DHT has more entry points.
    dt.findPublicTrackers().listen((urls) {
      for (final url in urls) {
        task.startAnnounceUrl(url, dtModel.infoHashBuffer);
      }
    });

    // Feed DHT bootstrap nodes from the torrent file.
    for (final node in dtModel.nodes) {
      task.addDHTNode(node);
    }

    await TorrentService.instance.updateTorrentStatus(torrent.id, 'downloading');
    _startPollTimer(torrent.id, task);
    _startScrapeTimer(torrent.id, task);
  }

  Future<void> _startFromMagnet(TorrentModel torrent) async {
    final magnet = dt.MagnetParser.parse(torrent.magnetLink!);
    if (magnet == null) throw FormatException('Invalid magnet link');

    // Step 1: download metadata from DHT/peers.
    final downloader = dt.MetadataDownloader.fromMagnet(torrent.magnetLink!);
    final completer = Completer<dt.TorrentModel>();

    downloader.createListener()
      ..on<dt.MetaDataDownloadComplete>((event) {
        if (completer.isCompleted) return;
        try {
          // decode() from b_encode_decode — event.data is already the right type.
          // parseTorrentFileContent is the confirmed top-level function from v2 docs.
          // Do NOT use TorrentParser.parseFromMap — that is for a different use case.
          // Do NOT add any normalizeInfoMap helper — it breaks the byte fields.
          final msg = decode(event.data);
          final model = dt.parseTorrentFileContent(<String, dynamic>{'info': msg});
          if (model != null) {
            completer.complete(model);
          } else {
            completer.completeError(StateError('parseTorrentFileContent returned null'));
          }
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

    final dtModel = await completer.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () => throw TimeoutException('Metadata timed out for ${torrent.id}'),
    );

    final saveDir = await _defaultDownloadDir();

    final totalBytes = dtModel.files.fold<int>(0, (s, f) => s + f.length);
    if (totalBytes > 0) {
      await TorrentService.instance
          .updateTorrent(torrent.copyWith(totalSize: totalBytes));
    }

    final task = dt.TorrentTask.newTask(
      dtModel,
      saveDir,
      false, // not streaming mode
      magnet.webSeeds.isNotEmpty ? magnet.webSeeds : null,
      magnet.acceptableSources.isNotEmpty ? magnet.acceptableSources : null,
    );

    if (magnet.selectedFileIndices?.isNotEmpty == true) {
      task.applySelectedFiles(magnet.selectedFileIndices!);
    }

    _tasks[torrent.id] = task;
    _wireEvents(torrent.id, task);

    await task.start();

    // Announce to tracker URLs from the magnet link first, then from the parsed model.
    final infoHash = dtModel.infoHashBuffer; // confirmed real property name
    final trackerUrls = {
      ...magnet.trackers,
      ...dtModel.announces,
    };
    for (final url in trackerUrls) {
      task.startAnnounceUrl(url, infoHash);
    }

    // Also subscribe to public trackers.
    dt.findPublicTrackers().listen((urls) {
      for (final url in urls) {
        task.startAnnounceUrl(url, infoHash);
      }
    });

    // Hand off peers that were already connected during metadata fetch.
    // This is what makes the download start immediately.
    for (final peer in downloader.activePeers) {
      task.addPeer(peer.address, dt.PeerSource.manual, type: peer.type);
    }

    // DHT bootstrap nodes.
    for (final node in dtModel.nodes) {
      task.addDHTNode(node);
    }

    await TorrentService.instance.updateTorrentStatus(torrent.id, 'downloading');
    _startPollTimer(torrent.id, task);
    _startScrapeTimer(torrent.id, task);
  }

  void _wireEvents(String torrentId, dt.TorrentTask task) {
    task.createListener()
      ..on<dt.StateFileUpdated>((_) {
        _emitStats(torrentId, task, 'downloading');
      })
      ..on<dt.TaskCompleted>((_) async {
        _emitStats(torrentId, task, 'completed');
        await TorrentService.instance.updateTorrentStatus(torrentId, 'completed');
        _cleanup(torrentId);
      })
      ..on<dt.TaskStopped>((_) {
        _cleanup(torrentId);
      });
  }

  // Keep a poll timer as backup — StateFileUpdated may not fire during peer discovery
  // phase when no pieces have been verified yet. The timer keeps the UI alive.
  void _startPollTimer(String torrentId, dt.TorrentTask task) {
    _pollTimers[torrentId] = Timer.periodic(const Duration(seconds: 2), (_) {
      _emitStats(torrentId, task, 'downloading');
    });
  }

  void _emitStats(String torrentId, dt.TorrentTask task, String state) {
    final downloaded = task.downloaded ?? 0;
    // Speed properties are in bytes/ms — multiply by 1000 to get bytes/s.
    // task.uploadSpeed is the confirmed name — NOT currentUploadSpeed.
    final dlSpeed = task.currentDownloadSpeed * 1000;
    final ulSpeed = task.uploadSpeed * 1000;

    _statusController.add(TorrentEngineStatus(
      torrentId: torrentId,
      downloaded: downloaded,
      uploaded: 0,
      progress: task.progress,
      state: state,
      peers: task.connectedPeersNumber,
      seeders: task.seederNumber,
      downloadSpeed: dlSpeed,
      uploadSpeed: ulSpeed,
    ));

    TorrentService.instance.updateProgress(torrentId, downloaded, 0);
  }

  void _startScrapeTimer(String torrentId, dt.TorrentTask task) {
    _scrapeTimers[torrentId] = Timer.periodic(const Duration(seconds: 30), (_) {
      _doScrape(torrentId, task);
    });
    _doScrape(torrentId, task);
  }

  Future<void> _doScrape(String torrentId, dt.TorrentTask task) async {
    try {
      final result = await task.scrapeTracker();
      if (!result.isSuccess) return;
      // task.metaInfo.infoHash is the confirmed property — NOT truncatedInfoHash
      final stats = result.getStatsForInfoHash(task.metaInfo.infoHash);
      if (stats == null) return;
      final existing = await TorrentService.instance.getTorrentById(torrentId);
      if (existing == null) return;
      await TorrentService.instance.updateTorrent(
        existing.copyWith(seeders: stats.complete, leechers: stats.incomplete),
      );
    } catch (_) {
      // Best-effort — scrape failure must never crash the engine.
    }
  }

  void _cleanup(String torrentId) {
    _pollTimers.remove(torrentId)?.cancel();
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

  // Always download to Documents/VaultTheSpire.
  // Never use torrent.filePath as a save destination — for torrent_file type,
  // filePath is the path to the .torrent FILE ITSELF, not a download directory.
  Future<String> _defaultDownloadDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}VaultTheSpire');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }
}
