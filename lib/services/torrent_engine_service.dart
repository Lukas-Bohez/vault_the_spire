import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart' as dt;
import 'package:flutter_background_service/flutter_background_service.dart';
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
    required this.dhtNodes,
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.statusMessage,
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

  static const List<String> _fallbackDhtBootstraps = [
    'router.bittorrent.com:6881',
    'dht.transmissionbt.com:6881',
    'router.utorrent.com:6881',
  ];

  bool isRunning(String torrentId) => _tasks.containsKey(torrentId);

  bool get hasActiveTasks {
    return _tasks.values.any((task) {
      try {
        final dyn = task as dynamic;
        final state = dyn.state?.toString().toLowerCase() ?? '';
        return !(state.contains('paused') || state.contains('completed') || state.contains('stopped'));
      } catch (_) {
        return true;
      }
    });
  }

  bool shouldStopService() {
    if (_tasks.isEmpty) return true;
    if (hasActiveTasks) {
      _lastActive = DateTime.now();
      return false;
    }

    if (_lastActive == null) {
      _lastActive = DateTime.now();
      return false;
    }

    return DateTime.now().difference(_lastActive!).inMinutes >= 5;
  }

  DateTime? _lastActive;

  void pauseAll() {
    for (final task in _tasks.values) {
      try {
        final dyn = task as dynamic;
        if (dyn.pause != null) {
          dyn.pause();
        } else if (dyn.stop != null) {
          dyn.stop();
        }
      } catch (e) {
        print('⚠️ Pause all failed for task: $e');
      }
    }
  }

  void resumeAll() {
    for (final task in _tasks.values) {
      try {
        final dyn = task as dynamic;
        if (dyn.resume != null) {
          dyn.resume();
        } else if (dyn.start != null) {
          dyn.start();
        }
      } catch (e) {
        print('⚠️ Resume all failed for task: $e');
      }
    }
  }

  TorrentEngineStatus aggregateStatus() {
    var totalDownload = 0;
    var totalUpload = 0;
    num totalDht = 0;
    num totalPeers = 0;
    var progress = 0.0;
    var speed = 0.0;
    for (final task in _tasks.values) {
      try {
        final dyn = task as dynamic;
        final downloadValue = dyn.downloaded ?? 0;
        totalDownload += downloadValue is num ? downloadValue.toInt() : 0;
        final uploadValue = dyn.uploaded ?? 0;
        totalUpload += uploadValue is num ? uploadValue.toInt() : 0;
        final dhtValue = dyn.dhtNodesNumber ?? dyn.dhtNodeCount ?? 0;
        totalDht += dhtValue is num ? dhtValue.toInt() : 0;
        final peerValue = dyn.connectedPeersNumber ?? 0;
        totalPeers += peerValue is num ? peerValue.toInt() : 0;
        final progressValue = dyn.progress ?? 0.0;
        progress += progressValue is num ? progressValue.toDouble() : 0.0;
        final currentDownloadSpeedVal = dyn.currentDownloadSpeed ?? 0.0;
        speed += (currentDownloadSpeedVal is num ? currentDownloadSpeedVal.toDouble() : 0.0) * 1000;
      } catch (_) {
      }
    }
    final taskCount = _tasks.length;

    final aggregateStatusMessage = hasActiveTasks
        ? '⚡ Aggregating status: $totalPeers peers, ${totalDht.toInt()} DHT nodes'
        : '⏹️ Idle';

    return TorrentEngineStatus(
      torrentId: 'aggregate',
      downloaded: totalDownload,
      uploaded: totalUpload,
      progress: taskCount > 0 ? progress / taskCount : 0.0,
      state: hasActiveTasks ? 'downloading' : 'idle',
      peers: totalPeers.toInt(),
      dhtNodes: totalDht.toInt(),
      downloadSpeed: speed,
      uploadSpeed: 0,
      statusMessage: aggregateStatusMessage,
    );
  }

  void _addFallbackDhtNodes(dt.TorrentTask task) {
    for (final node in _fallbackDhtBootstraps) {
      try {
        final dynTask = task as dynamic;
        final uri = Uri.parse('udp://$node');
        dynTask.addDHTNode(uri);
      } catch (e) {
        print('⚠️ Could not add fallback DHT node $node: $e');
      }
    }
  }

  dynamic _normalizeTorrentMap(dynamic value) {
    if (value is Uint8List) {
      try {
        return utf8.decode(value);
      } catch (_) {
        return value;
      }
    }
    if (value is List) {
      return value.map(_normalizeTorrentMap).toList();
    }
    if (value is Map) {
      final map = <String, dynamic>{};
      for (final key in value.keys) {
        final keyStr = key is Uint8List ? utf8.decode(key) : key.toString();
        map[keyStr] = _normalizeTorrentMap(value[key]);
      }
      return map;
    }
    return value;
  }


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

  Future<void> _startFromFile(TorrentModel torrent, {String? destinationPath}) async {
    // torrent.filePath is the path to the .torrent FILE, not a download folder.
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

    // Wire events BEFORE start() — pieces can complete immediately on resume.
    _tasks[torrent.id] = task;
    _wireEvents(torrent.id, task);

    // Announce to every tracker embedded in the .torrent file.
    // infoHashBuffer is the correct Uint8List property name.
    for (final url in dtModel.announces) {
      task.startAnnounceUrl(url, dtModel.infoHashBuffer);
    }

    // Subscribe to public tracker list — this is what gets peers flowing even
    // when the .torrent file's own trackers are dead or empty.
    // findPublicTrackers() is from dtorrent_common, fetches from the internet.
    findPublicTrackers().listen((urls) {
      for (final url in urls) {
        task.startAnnounceUrl(url, dtModel.infoHashBuffer);
      }
    });

    // Feed DHT bootstrap nodes from the torrent file.
    for (final node in dtModel.nodes) {
      task.addDHTNode(node);
    }

    // Add static fallback DHT bootstraps for resiliency.
    _addFallbackDhtNodes(task);

    await task.start();

    await TorrentService.instance.updateTorrentStatus(torrent.id, 'downloading');
    _startPollTimer(torrent.id, task);
    _startScrapeTimer(torrent.id, task);
  }

  Future<void> _startFromMagnet(TorrentModel torrent, {String? destinationPath}) async {
    final magnet = dt.MagnetParser.parse(torrent.magnetLink!);
    if (magnet == null) throw FormatException('Invalid magnet link');

    final downloader = dt.MetadataDownloader.fromMagnet(torrent.magnetLink!);
    final completer = Completer<dt.TorrentModel>();

    downloader.createListener()
      ..on<dt.MetaDataDownloadComplete>((event) {
        if (completer.isCompleted) return;
        try {
          // event.data is the raw bencoded info-dict bytes.
          // decode() from b_encode_decode returns Map<dynamic, dynamic> with
          // Uint8List keys — NOT Map<String, dynamic>.
          // DO NOT type-check with "is Map<String, dynamic>" — it always fails
          // for real bencode data and silently breaks every magnet download.
          // Just pass the raw decoded value directly to parseTorrentFileContent.
          final rawData = event.data;
          final msg = decode(rawData is Uint8List
              ? rawData
              : Uint8List.fromList(rawData));

          final normalizedInfo = _normalizeTorrentMap(msg);
          final model = dt.TorrentParser.parseFromMap(<String, dynamic>{
            'info': normalizedInfo,
          });
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

    // Announce to trackers from the magnet link + parsed model before start.
    final infoHash = dtModel.infoHashBuffer;
    final seenUrls = <String>{};
    for (final url in [...magnet.trackers, ...dtModel.announces]) {
      final s = url.toString();
      if (seenUrls.add(s)) task.startAnnounceUrl(url, infoHash);
    }

    // Public tracker list — ensures peers even without tracker URLs in magnet.
    findPublicTrackers().listen((urls) {
      for (final url in urls) {
        task.startAnnounceUrl(url, infoHash);
      }
    });

    // DHT bootstrap nodes from parsed metadata.
    for (final node in dtModel.nodes) {
      task.addDHTNode(node);
    }

    // Add static fallback DHT bootstraps for resiliency.
    _addFallbackDhtNodes(task);

    await task.start();

    // Hand off peers already connected during metadata fetch.
    // This is what gets pieces flowing immediately.
    for (final peer in downloader.activePeers) {
      task.addPeer(peer.address, dt.PeerSource.manual, type: peer.type);
    }

    await TorrentService.instance.updateTorrentStatus(torrent.id, 'downloading');
    _startPollTimer(torrent.id, task);
    _startScrapeTimer(torrent.id, task);
  }

  void _wireEvents(String torrentId, dt.TorrentTask task) {
    task.createListener()
      ..on<dt.StateFileUpdated>((_) {
        print('🔁 [$torrentId] StateFileUpdated');
        _emitStats(torrentId, task, 'downloading');
      })
      ..on<dt.TaskCompleted>((_) async {
        print('✅ [$torrentId] TaskCompleted');
        _emitStats(torrentId, task, 'completed');
        await TorrentService.instance
            .updateTorrentStatus(torrentId, 'completed');
        _cleanup(torrentId);
      })
      ..on<dt.TaskStopped>((_) {
        print('⏹️ [$torrentId] TaskStopped');
        _cleanup(torrentId);
      });

    // Optional task-level exception callback if supported by library.
    try {
      final dynamicTask = task as dynamic;
      if (dynamicTask.onException != null) {
        dynamicTask.onException((e) {
          print('🛑 [$torrentId] Task exception: $e');
          if (e is FileSystemException || e.toString().contains('FileSystemException')) {
            print('⚠️ [$torrentId] FileSystemException detected.');
          }
        });
      }
    } catch (_) {
      // ignore - not supported by dtorrent_task API
    }
  }

  void _startPollTimer(String torrentId, dt.TorrentTask task) {
    // Poll every 2 s so the UI stays alive during peer discovery
    // (StateFileUpdated only fires once pieces start writing to disk).
    _pollTimers[torrentId] = Timer.periodic(const Duration(seconds: 2), (_) {
      _emitStats(torrentId, task, 'downloading');
    });
  }

  void _emitStats(String torrentId, dt.TorrentTask task, String state) {
    final downloaded = task.downloaded ?? 0;
    // Speed is in bytes/ms — multiply by 1000 for bytes/s.
    final dlSpeed = task.currentDownloadSpeed * 1000;
    final ulSpeed = task.uploadSpeed * 1000;

    var dhtNodes = 0;
    try {
      final dyn = task as dynamic;
      final dhtValue = dyn.dhtNodesNumber ?? dyn.dhtNodeCount ?? 0;
      dhtNodes = dhtValue is num ? dhtValue.toInt() : 0;
    } catch (_) {
      dhtNodes = 0;
    }

    final statusMsg = _deriveStatusMessage(task, dhtNodes);

    _statusController.add(TorrentEngineStatus(
      torrentId: torrentId,
      downloaded: downloaded,
      uploaded: 0,
      progress: task.progress,
      state: state,
      peers: task.connectedPeersNumber,
      dhtNodes: dhtNodes,
      seeders: task.seederNumber,
      downloadSpeed: dlSpeed,
      uploadSpeed: ulSpeed,
      statusMessage: statusMsg,
    ));

    TorrentService.instance.updateProgress(torrentId, downloaded, 0);

    // Notify background service for notification updates.
    try {
      final service = FlutterBackgroundService();
      service.invoke('update_status', {
        'downloadSpeed': dlSpeed,
        'progress': task.progress,
        'peers': task.connectedPeersNumber,
        'dhtNodes': dhtNodes,
      });
    } catch (_) {
      // Background service may not be available on desktop/test.
    }
  }

  String _deriveStatusMessage(dt.TorrentTask task, int dhtNodes) {
    final peers = task.connectedPeersNumber;
    final progress = task.progress;
    final hasDownloaded = (task.downloaded ?? 0) > 0;

    if (dhtNodes <= 0) {
      return '🛰️ DHT bootstrapping...';
    }
    if (peers <= 0) {
      return '🔍 Searching peers... ($dhtNodes DHT nodes)';
    }
    if (!hasDownloaded && progress <= 0.01) {
      return '📥 Getting metadata...';
    }
    if (progress < 1.0) {
      return '📦 Downloading pieces... ${ (progress * 100).toStringAsFixed(1)}%';
    }
    return '✅ Download complete';
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
      // task.metaInfo.infoHash is the confirmed property for scrape lookup.
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

  // Always save to Documents/VaultTheSpire.
  // torrent.filePath for torrent_file type is the .torrent FILE path — never
  // use it as a download destination or you'll try to write into wherever the
  // user dragged the .torrent from.
  Future<String> _defaultDownloadDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir =
        Directory('${docs.path}${Platform.pathSeparator}VaultTheSpire');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }
}