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
  final int seeders;
  final int leechers;
  final double downloadSpeed;
  final double uploadSpeed;
  final List<String> peerAddresses;

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
    this.peerAddresses = const [],
  });
}

class TorrentEngineService {
  TorrentEngineService._();
  static final TorrentEngineService instance = TorrentEngineService._();

  final Map<String, dt.TorrentTask> _tasks = {};
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
    // torrent.filePath is the path to the .torrent file itself.
    final dtModel = await dt.TorrentModel.parse(torrent.filePath!);
    final saveDir = await _defaultDownloadDir();

    // Persist total size immediately so UI shows real value, not 0 B.
    final totalBytes = dtModel.files.fold<int>(0, (s, f) => s + f.length);
    if (totalBytes > 0 && (torrent.totalSize ?? 0) != totalBytes) {
      await TorrentService.instance
          .updateTorrent(torrent.copyWith(totalSize: totalBytes));
    }

    final task = dt.TorrentTask.newTask(dtModel, saveDir);

    // Register events BEFORE calling start().
    _tasks[torrent.id] = task;
    _wireEvents(torrent.id, task);

    await task.start();

    // Announce to all trackers embedded in the .torrent file.
    for (final url in dtModel.announces) {
      task.startAnnounceUrl(url, dtModel.infoHashBuffer);
    }

    // Feed in DHT bootstrap nodes if the torrent carries any.
    for (final node in dtModel.nodes) {
      task.addDHTNode(node);
    }

    await TorrentService.instance.updateTorrentStatus(torrent.id, 'downloading');
    _startScrapeTimer(torrent.id, task);
  }

  Future<void> _startFromMagnet(TorrentModel torrent) async {
    final magnet = dt.MagnetParser.parse(torrent.magnetLink!);
    if (magnet == null) throw FormatException('Invalid magnet link');

    // Step 1: resolve metadata via DHT/peers before we can start the task.
    final downloader = dt.MetadataDownloader.fromMagnet(torrent.magnetLink!);
    final completer = Completer<dt.TorrentModel>();

    downloader.createListener()
      ..on<dt.MetaDataDownloadComplete>((event) {
        if (completer.isCompleted) return;
        try {
          // event.data is the raw bencoded info-dict bytes.
          // Wrap into a minimal torrent map, then parse.
          final msg = decode(Uint8List.fromList(event.data));
          final model = dt.TorrentParser.parseFromMap({'info': msg});
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
      onTimeout: () => throw TimeoutException(
          'Metadata download timed out for ${torrent.id}'),
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

    // Register events BEFORE calling start().
    _tasks[torrent.id] = task;
    _wireEvents(torrent.id, task);

    await task.start();

    // Hand off peers that were already connected during metadata fetch.
    // This is what gets the first pieces flowing without waiting for
    // DHT to rediscover the swarm from scratch.
    for (final peer in downloader.activePeers) {
      task.addPeer(peer.address, dt.PeerSource.manual, type: peer.type);
    }

    // Announce to trackers from the magnet link.
    if (magnet.trackers.isNotEmpty && magnet.infoHashString.isNotEmpty) {
      final hashBytes = Uint8List.fromList(
        List.generate(magnet.infoHashString.length ~/ 2, (i) => int.parse(
            magnet.infoHashString.substring(i * 2, i * 2 + 2), radix: 16)),
      );
      for (final url in magnet.trackers) {
        task.startAnnounceUrl(url, hashBytes);
      }
    }

    await TorrentService.instance.updateTorrentStatus(torrent.id, 'downloading');
    _startScrapeTimer(torrent.id, task);
  }

  void _wireEvents(String torrentId, dt.TorrentTask task) {
    task.createListener()
      // StateFileUpdated fires every time a verified piece is written to disk.
      // This is the ONLY correct hook for reading download stats.
      // Timer-based polling reads stale values — properties are updated here.
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

  void _emitStats(String torrentId, dt.TorrentTask task, String state) {
    final downloaded = task.downloaded ?? 0;
    final progress = task.progress; // 0.0 – 1.0
    final peers = task.connectedPeersNumber;
    final seeders = task.seederNumber;
    final dlSpeed = task.currentDownloadSpeed; // bytes/ms → multiply by 1000 for bytes/s
    final ulSpeed = task.uploadSpeed;          // same unit
    final peerAddresses = task.activePeers
            ?.map((peer) => peer.address.toContactEncodingString())
            .toList() ??
        <String>[];

    _statusController.add(TorrentEngineStatus(
      torrentId: torrentId,
      downloaded: downloaded,
      uploaded: 0,
      progress: progress,
      state: state,
      peers: peers,
      seeders: seeders,
      downloadSpeed: dlSpeed * 1000, // convert to bytes/s
      uploadSpeed: ulSpeed * 1000,
      peerAddresses: peerAddresses,
    ));

    // Persist progress to DB (fire-and-forget).
    TorrentService.instance.updateProgress(torrentId, downloaded, 0);
  }

  void _startScrapeTimer(String torrentId, dt.TorrentTask task) {
    // Scrape trackers for seeder/leecher counts every 30 s.
    _scrapeTimers[torrentId] =
        Timer.periodic(const Duration(seconds: 30), (_) {
      _doScrape(torrentId, task);
    });
    // Run once immediately.
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

  void _cleanup(String torrentId) {
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

  Future<String> _defaultDownloadDir() async {
    // Always download to Documents/VaultTheSpire — never into the same
    // folder as the .torrent file, which is fragile and permission-dependent.
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}VaultTheSpire');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }
}