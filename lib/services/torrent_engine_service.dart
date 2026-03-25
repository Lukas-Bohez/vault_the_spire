import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:developer' as developer;

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
  final Map<String, Timer> _scrapeTimers = {};
  final Map<String, Timer> _statsTimers = {};

  final _statusController = StreamController<TorrentEngineStatus>.broadcast();
  Stream<TorrentEngineStatus> get statusStream => _statusController.stream;

  bool isRunning(String torrentId) => _tasks.containsKey(torrentId);

  Future<void> startTorrent(String torrentId, {String? destinationPath}) async {
    if (isRunning(torrentId)) return;

    final torrent = await TorrentService.instance.getTorrentById(torrentId);
    if (torrent == null) throw StateError('Torrent not found: $torrentId');

    if (torrent.type == 'torrent_file' && torrent.filePath != null) {
      await _startFromFile(torrent, destinationPath);
    } else if (torrent.magnetLink != null) {
      await _startFromMagnet(torrent, destinationPath);
    } else {
      throw StateError('Torrent has no source');
    }
  }

  Future<void> _startFromFile(TorrentModel torrent, String? destinationPath) async {
    final torrentFile = File(torrent.filePath!);
    if (!await torrentFile.exists()) {
      throw FileSystemException('Torrent file does not exist', torrent.filePath);
    }

    final dtModel = await dt.TorrentModel.parse(torrent.filePath!);
    final saveDir = destinationPath != null && destinationPath.isNotEmpty
        ? destinationPath
        : await _defaultDownloadDir();

    final totalBytes = dtModel.files.fold<int>(0, (s, f) => s + f.length);
    if (totalBytes > 0) {
      await TorrentService.instance.updateTorrent(
        torrent.copyWith(
          totalSize: totalBytes,
          totalPieces: dtModel.files.length,
          pieceLength: dtModel.pieceLength,
        ),
      );
    }

    final task = dt.TorrentTask.newTask(dtModel, saveDir);

    // Wire events BEFORE start() so no early events are missed.
    _tasks[torrent.id] = task;
    _wireEvents(torrent.id, task);

    // Prepare DHT before starting so startup can immediately connect.
    for (final node in dtModel.nodes) {
      task.addDHTNode(node);
    }

    await task.start();

    // Announce to trackers after task start (tracker is initialized in start()).
    final infoHashBytes = dtModel.truncatedInfoHash;
    for (final url in dtModel.announces) {
      task.startAnnounceUrl(url, infoHashBytes);
    }

    // Kick DHT peer discovery immediately after start.
    task.requestPeersFromDHT();

    await TorrentService.instance
        .updateTorrentStatus(torrent.id, 'downloading');
    _startScrapeTimer(torrent.id, task);
  }

  Future<void> _startFromMagnet(TorrentModel torrent, String? destinationPath) async {
    final magnet = dt.MagnetParser.parse(torrent.magnetLink!);
    if (magnet == null) throw FormatException('Invalid magnet link');

    final downloader =
        dt.MetadataDownloader.fromMagnet(torrent.magnetLink!);
    final completer = Completer<dt.TorrentModel>();

    // Helper to normalize decoded bencode data into expected types for TorrentParser.
    Map<String, dynamic> normalizeInfoMap(Map<String, dynamic> raw) {
      final result = <String, dynamic>{};
      raw.forEach((key, value) {
        if (value is Uint8List) {
          try {
            result[key] = utf8.decode(value);
          } catch (_) {
            result[key] = value;
          }
        } else if (value is List) {
          result[key] = value.map((v) {
            if (v is Uint8List) {
              try {
                return utf8.decode(v);
              } catch (_) {
                return v;
              }
            } else if (v is Map<String, dynamic>) {
              return normalizeInfoMap(v);
            }
            return v;
          }).toList();
        } else if (value is Map) {
          result[key] = normalizeInfoMap(Map<String, dynamic>.from(value));
        } else {
          result[key] = value;
        }
      });
      return result;
    }

    downloader.createListener()
      ..on<dt.MetaDataDownloadComplete>((event) {
        if (completer.isCompleted) return;
        try {
          developer.log('Magnet metadata received (${event.data.length} bytes)');
          final msg = decode(Uint8List.fromList(event.data));
          developer.log('Decoded metadata type: ${msg.runtimeType}');

          if (msg is! Map<String, dynamic>) {
            throw StateError('Invalid metadata format from DHT');
          }

          developer.log('Metadata keys: ${msg.keys.join(', ')}');
          developer.log('info type: ${msg.runtimeType}');

          final normalizedInfo = normalizeInfoMap(msg);
          final normalizedInfoType = normalizedInfo.runtimeType;
          developer.log('Normalized info type: $normalizedInfoType');
          developer.log('Name value type: ${normalizedInfo['name']?.runtimeType}');

          final model = dt.TorrentParser.parseFromMap(<String, dynamic>{
            'info': normalizedInfo,
          });

          developer.log('Parsed model name: ${model.name}, files: ${model.files.length}');
          completer.complete(model);
        } catch (e, st) {
          developer.log('Magnet metadata parse failed: $e', error: e, stackTrace: st);
          TorrentService.instance.updateTorrentStatus(torrent.id, 'error');
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

    final saveDir = destinationPath != null && destinationPath.isNotEmpty
        ? destinationPath
        : await _defaultDownloadDir();

    final totalBytes = dtModel.files.fold<int>(0, (s, f) => s + f.length);
    if (totalBytes > 0) {
      await TorrentService.instance.updateTorrent(
        torrent.copyWith(
          totalSize: totalBytes,
          totalPieces: dtModel.files.length,
          pieceLength: dtModel.pieceLength,
        ),
      );
    }

    final task = dt.TorrentTask.newTask(
      dtModel,
      saveDir,
      false,
      magnet.webSeeds.isNotEmpty ? magnet.webSeeds : null,
      magnet.acceptableSources.isNotEmpty
          ? magnet.acceptableSources
          : null,
    );

    if (magnet.selectedFileIndices?.isNotEmpty == true) {
      task.applySelectedFiles(magnet.selectedFileIndices!);
    }

    _tasks[torrent.id] = task;
    _wireEvents(torrent.id, task);

    // Add DHT nodes from decoded metadata before start.
    for (final node in dtModel.nodes) {
      task.addDHTNode(node);
    }

    await task.start();

    // Announce to trackers after task start (task.start() initializes tracker).
    final infoHashBytes = dtModel.truncatedInfoHash;
    final trackerUrls = magnet.trackers.isNotEmpty
        ? magnet.trackers
        : dtModel.announces;
    for (final url in trackerUrls) {
      task.startAnnounceUrl(url, infoHashBytes);
    }

    // Hand off peers from metadata downloader — avoids full DHT reconnection.
    for (final peer in downloader.activePeers) {
      task.addPeer(peer.address, dt.PeerSource.manual, type: peer.type);
    }

    // Kick DHT peer discovery after starting.
    task.requestPeersFromDHT();


    await TorrentService.instance
        .updateTorrentStatus(torrent.id, 'downloading');
    _startScrapeTimer(torrent.id, task);
  }

  void _wireEvents(String torrentId, dt.TorrentTask task) {
    task.createListener()
      // Emit initial status on start/resume/paused events.
      ..on<dt.TaskStarted>((_) {
        _emitStats(torrentId, task, 'downloading');
      })
      ..on<dt.TaskResumed>((_) {
        _emitStats(torrentId, task, 'downloading');
      })
      ..on<dt.TaskPaused>((_) {
        _emitStats(torrentId, task, 'paused');
      })
      // StateFileUpdated fires every time a piece is verified and written to disk.
      // This is the best place to read stats.
      ..on<dt.StateFileUpdated>((_) {
        _emitStats(torrentId, task, 'downloading');
      })
      ..on<dt.TaskFileCompleted>((_) {
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

  void _emitStats(String torrentId, dt.TorrentTask task, String state) {
    final downloaded = task.downloaded ?? 0;
    final peers = task.connectedPeersNumber;
    final seeders = task.seederNumber;

    final torrentLength = task.metaInfo.length ??
        task.metaInfo.files.fold<int>(0, (s, f) => s + f.length);
    final progress = torrentLength > 0
        ? (downloaded / torrentLength).clamp(0.0, 1.0)
        : task.progress;

    // currentDownloadSpeed and uploadSpeed are in bytes/ms — multiply for bytes/s.
    final dlSpeed = task.currentDownloadSpeed * 1000;
    final ulSpeed = task.uploadSpeed * 1000;

    developer.log(
      'emitStats id=$torrentId state=$state downloaded=$downloaded ' 
      'total=$torrentLength progress=${(progress * 100).toStringAsFixed(2)} ' 
      'peers=$peers seeders=$seeders',
    );

    _statusController.add(TorrentEngineStatus(
      torrentId: torrentId,
      downloaded: downloaded,
      uploaded: 0,
      progress: progress,
      state: state,
      peers: peers,
      seeders: seeders,
      downloadSpeed: dlSpeed,
      uploadSpeed: ulSpeed,
    ));

    TorrentService.instance.updateProgress(torrentId, downloaded, 0);
  }

  void _startScrapeTimer(String torrentId, dt.TorrentTask task) {
    _scrapeTimers[torrentId] =
        Timer.periodic(const Duration(seconds: 30), (_) {
      _doScrape(torrentId, task);
    });
    _statsTimers[torrentId] =
        Timer.periodic(const Duration(seconds: 3), (_) {
      _emitStats(torrentId, task, 'downloading');
    });

    _doScrape(torrentId, task);
    _emitStats(torrentId, task, 'downloading');
  }

  Future<void> _doScrape(String torrentId, dt.TorrentTask task) async {
    try {
      final result = await task.scrapeTracker();
      if (!result.isSuccess) return;
      final infoHashString = task.metaInfo.truncatedInfoHash
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final stats = result.getStatsForInfoHash(infoHashString);
      if (stats == null) return;
      final existing =
          await TorrentService.instance.getTorrentById(torrentId);
      if (existing == null) return;
      await TorrentService.instance.updateTorrent(
        existing.copyWith(
            seeders: stats.complete, leechers: stats.incomplete),
      );
    } catch (_) {}
  }

  void _cleanup(String torrentId) {
    _scrapeTimers.remove(torrentId)?.cancel();
    _statsTimers.remove(torrentId)?.cancel();
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
    final task = _tasks[torrentId];
    task?.resume();
    task?.requestPeersFromDHT();
    TorrentService.instance.updateTorrentStatus(torrentId, 'downloading');
  }

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