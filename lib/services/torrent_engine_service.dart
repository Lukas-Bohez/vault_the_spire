import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
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
  final int dhtNodes;
  final int seeders;
  final int leechers;
  final double downloadSpeed;
  final double uploadSpeed;
  final String statusMessage;

  const TorrentEngineStatus({
    required this.torrentId,
    required this.downloaded,
    required this.uploaded,
    required this.progress,
    required this.state,
    required this.peers,
    this.dhtNodes = 0,
    required this.downloadSpeed,
    required this.uploadSpeed,
    this.seeders = 0,
    this.leechers = 0,
    this.statusMessage = '',
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

  Future<void> startTorrent(String torrentId, {String? destinationPath}) async {
    if (isRunning(torrentId)) return;
    final torrent = await TorrentService.instance.getTorrentById(torrentId);
    if (torrent == null) throw StateError('Torrent not found: $torrentId');

    if (torrent.type == 'torrent_file' && torrent.filePath != null) {
      await _startFromFile(torrent, destinationPath: destinationPath);
    } else if (torrent.magnetLink != null) {
      await _startFromMagnet(torrent, destinationPath: destinationPath);
    } else {
      throw StateError('Torrent has no source');
    }
  }

  Future<void> _startFromFile(
    TorrentModel torrent, {
    String? destinationPath,
  }) async {
    // dt.TorrentModel.parse handles all reading, decoding, and parsing internally.
    // Do NOT manually read bytes, decode, normalize, and call parseFromMap —
    // that chain corrupts the internal piece structure.
    final dtModel = await dt.TorrentModel.parse(torrent.filePath!);
    final saveDir = destinationPath?.trim().isNotEmpty == true
        ? destinationPath!
        : await _defaultDownloadDir();

    final totalBytes = dtModel.files.fold<int>(0, (s, f) => s + f.length);
    if (totalBytes > 0 && (torrent.totalSize ?? 0) != totalBytes) {
      await TorrentService.instance
          .updateTorrent(torrent.copyWith(totalSize: totalBytes));
    }

    final task = dt.TorrentTask.newTask(dtModel, saveDir);
    _tasks[torrent.id] = task;
    _wireEvents(torrent.id, task);

    await task.start();

    for (final url in dtModel.announces) {
      task.startAnnounceUrl(url, dtModel.infoHashBuffer);
    }
    findPublicTrackers().listen((urls) {
      for (final url in urls) {
        task.startAnnounceUrl(url, dtModel.infoHashBuffer);
      }
    });
    for (final node in dtModel.nodes) {
      task.addDHTNode(node);
    }

    await TorrentService.instance.updateTorrentStatus(torrent.id, 'downloading');
    _startPollTimer(torrent.id, task);
    _startScrapeTimer(torrent.id, task);
  }

  Future<void> _startFromMagnet(
    TorrentModel torrent, {
    String? destinationPath,
  }) async {
    final magnet = dt.MagnetParser.parse(torrent.magnetLink!);
    if (magnet == null) throw FormatException('Invalid magnet link');

    // Step 1: fetch metadata from the swarm.
    final downloader = dt.MetadataDownloader.fromMagnet(torrent.magnetLink!);
    final completer = Completer<dt.TorrentModel>();

    downloader.createListener()
      ..on<dt.MetaDataDownloadComplete>((event) async {
        if (completer.isCompleted) return;
        try {
          final Uint8List rawData = Uint8List.fromList(event.data);
          final msg = decode(rawData);
          // msg is Map<dynamic, dynamic> with Uint8List keys — do NOT type-check it.
          // _parseTorrentModelFromRawBencode re-encodes it to bytes and parses correctly.
          final model = await _parseTorrentModelFromRawBencode(msg);
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

    final dtModel = await completer.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () =>
          throw TimeoutException('Metadata timed out for ${torrent.id}'),
    );

    final saveDir = destinationPath?.trim().isNotEmpty == true
        ? destinationPath!
        : await _defaultDownloadDir();

    final totalBytes = dtModel.files.fold<int>(0, (s, f) => s + f.length);
    if (totalBytes > 0) {
      await TorrentService.instance
          .updateTorrent(torrent.copyWith(totalSize: totalBytes));
    }

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

    _tasks[torrent.id] = task;
    _wireEvents(torrent.id, task);

    // ── MUST call start() first ─────────────────────────────────────────────
    await task.start();
    // ────────────────────────────────────────────────────────────────────────

    // Announce to trackers from magnet + parsed model, deduplicated.
    final infoHash = dtModel.infoHashBuffer;
    final seenUrls = <String>{};
    for (final url in [...magnet.trackers, ...dtModel.announces]) {
      if (seenUrls.add(url.toString())) {
        task.startAnnounceUrl(url, infoHash);
      }
    }

    // Public tracker stream — must be after start().
    findPublicTrackers().listen((urls) {
      for (final url in urls) {
        task.startAnnounceUrl(url, infoHash);
      }
    });

    // Hand off peers from metadata fetch so download starts immediately.
    for (final peer in downloader.activePeers) {
      task.addPeer(peer.address, dt.PeerSource.manual, type: peer.type);
    }

    // DHT bootstrap nodes — must be after start().
    for (final node in dtModel.nodes) {
      task.addDHTNode(node);
    }

    await TorrentService.instance.updateTorrentStatus(torrent.id, 'downloading');
    _startPollTimer(torrent.id, task);
    _startScrapeTimer(torrent.id, task);
  }

  Future<dt.TorrentModel> _parseTorrentModelFromRawBencode(dynamic infoDict) async {
    // infoDict is the raw decoded bencode info-dict (Map<dynamic, dynamic> with
    // Uint8List keys). Wrap it in a minimal torrent map, re-encode to bytes,
    // write to temp file, and let TorrentModel.parse handle everything correctly.
    final torrentMap = <dynamic, dynamic>{
      Uint8List.fromList('info'.codeUnits): infoDict,
    };
    final bytes = encode(torrentMap);
    final tempPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}vts_${DateTime.now().millisecondsSinceEpoch}.torrent';
    final tempFile = File(tempPath);
    await tempFile.writeAsBytes(bytes);
    try {
      return await dt.TorrentModel.parse(tempFile.path);
    } finally {
      try {
        if (await tempFile.exists()) await tempFile.delete();
      } catch (_) {}
    }
  }

  void _wireEvents(String torrentId, dt.TorrentTask task) {
    task.createListener()
      ..on<dt.StateFileUpdated>((_) {
        _emitStats(torrentId, task, 'downloading');
      })
      ..on<dt.TaskCompleted>((_) async {
        _emitStats(torrentId, task, 'completed');
        await TorrentService.instance
            .updateTorrentStatus(torrentId, 'completed');
        _cleanup(torrentId);
      })
      ..on<dt.TaskStopped>((_) {
        _cleanup(torrentId);
      });
  }

  void _startPollTimer(String torrentId, dt.TorrentTask task) {
    _pollTimers[torrentId] = Timer.periodic(const Duration(seconds: 2), (_) {
      _emitStats(torrentId, task, 'downloading');
    });
  }

  void _emitStats(String torrentId, dt.TorrentTask task, String state) {
    final downloaded = task.downloaded ?? 0;
    final dlSpeed = task.currentDownloadSpeed * 1000; // bytes/ms → bytes/s
    final ulSpeed = task.uploadSpeed * 1000;
    final peers = task.connectedPeersNumber;

    int seeders = task.seederNumber;
    int leechers = (peers - seeders).clamp(0, peers);

    if (task.activePeers != null) {
      seeders = task.activePeers!.where((p) => p.isSeeder).length;
      leechers = task.activePeers!.where((p) => !p.isSeeder).length;
    }

    final progress = task.progress;

    final msg = peers == 0
        ? 'Searching for peers...'
        : downloaded == 0
            ? 'Connected to $peers peer${peers == 1 ? '' : 's'}, waiting for pieces...'
            : '${(progress * 100).toStringAsFixed(1)}% — $peers peer${peers == 1 ? '' : 's'}';

    final dhtNodes = 0;

    _statusController.add(TorrentEngineStatus(
      torrentId: torrentId,
      downloaded: downloaded,
      uploaded: 0,
      progress: progress,
      state: state,
      peers: peers,
      dhtNodes: dhtNodes,
      seeders: seeders,
      leechers: leechers,
      downloadSpeed: dlSpeed,
      uploadSpeed: ulSpeed,
      statusMessage: msg,
    ));

    TorrentService.instance.updateProgress(torrentId, downloaded, 0);
  }

  void _startScrapeTimer(String torrentId, dt.TorrentTask task) {
    _scrapeTimers[torrentId] =
        Timer.periodic(const Duration(seconds: 30), (_) {
      _doScrape(torrentId, task);
    });
    _doScrape(torrentId, task);
  }

  Future<void> _doScrape(String torrentId, dt.TorrentTask task) async {
    try {
      final result = await task.scrapeTracker();
      if (!result.isSuccess) return;
      final stats = result.getStatsForInfoHash(task.metaInfo.infoHash);
      if (stats == null) return;
      final existing =
          await TorrentService.instance.getTorrentById(torrentId);
      if (existing == null) return;
      await TorrentService.instance.updateTorrent(
        existing.copyWith(
            seeders: stats.complete, leechers: stats.incomplete),
      );
    } catch (_) {
      // Best-effort — scrape must never crash the engine.
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

  void pauseAll() {
    for (final id in _tasks.keys.toList()) {
      pauseTorrent(id);
    }
  }

  void resumeAll() {
    for (final id in _tasks.keys.toList()) {
      resumeTorrent(id);
    }
  }

  TorrentEngineStatus aggregateStatus() {
    if (_tasks.isEmpty) {
      return const TorrentEngineStatus(
        torrentId: '',
        downloaded: 0,
        uploaded: 0,
        progress: 0.0,
        state: 'stopped',
        peers: 0,
        dhtNodes: 0,
        downloadSpeed: 0.0,
        uploadSpeed: 0.0,
      );
    }

    final firstTask = _tasks.values.first;
    final dhtNodes = 0;
    return TorrentEngineStatus(
      torrentId: firstTask.metaInfo.name,
      downloaded: firstTask.downloaded ?? 0,
      uploaded: 0,
      progress: firstTask.progress,
      state: 'downloading',
      peers: firstTask.connectedPeersNumber,
      dhtNodes: dhtNodes,
      downloadSpeed: firstTask.currentDownloadSpeed * 1000,
      uploadSpeed: firstTask.uploadSpeed * 1000,
    );
  }

  bool shouldStopService() => _tasks.isEmpty;

  void stopAll() {
    for (final id in _tasks.keys.toList()) {
      stopTorrent(id);
    }
  }

  Future<String> _defaultDownloadDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir =
        Directory('${docs.path}${Platform.pathSeparator}VaultTheSpire');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }
}