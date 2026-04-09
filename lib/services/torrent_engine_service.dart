import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:bittorrent_dht/bittorrent_dht.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart' as dt;
import 'package:dtorrent_task_v2/src/piece/piece.dart' as dt_piece;
import 'package:dtorrent_task_v2/src/piece/sequential_config.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:vault_the_spire/models/torrent.dart';
import 'package:vault_the_spire/services/notification_service.dart';
import 'package:vault_the_spire/services/settings_service.dart';
import 'package:vault_the_spire/services/torrent_service.dart';

class TorrentEngineStatus {
  final String torrentId;
  final int downloaded;
  final int uploaded;
  final double progress;
  final String state;
  final int peers;
  final int dhtNodes;
  final int trackers;
  final int seeders;
  final int leechers;
  final double downloadSpeed;
  final double uploadSpeed;
  final double seedingProgress;
  final String statusMessage;
  final String connectionMessage;

  const TorrentEngineStatus({
    required this.torrentId,
    required this.downloaded,
    required this.uploaded,
    required this.progress,
    required this.state,
    required this.peers,
    this.dhtNodes = 0,
    this.trackers = 0,
    required this.downloadSpeed,
    required this.uploadSpeed,
    this.seedingProgress = 0.0,
    this.seeders = 0,
    this.leechers = 0,
    this.statusMessage = '',
    this.connectionMessage = '',
  });
}

class TorrentEngineService {
  TorrentEngineService._() {
    _bootstrapDhtNetwork();
  }
  static final TorrentEngineService instance = TorrentEngineService._();

  static const List<String> _defaultDhtBootstrapNodes = [
    'router.bittorrent.com:6881',
    'dht.transmissionbt.com:6881',
    'router.utorrent.com:6881',
    'dht.aelitis.com:6881',
  ];

  static const List<String> _fallbackTrackers = [
    'udp://tracker.openbittorrent.com:80/announce',
    'udp://tracker.opentrackr.org:1337/announce',
    'udp://tracker.coppersurfer.tk:6969/announce',
    'udp://tracker.leechers-paradise.org:6969/announce',
    'udp://tracker.internetwarriors.net:1337/announce',
    'udp://exodus.desync.com:6969/announce',
    'http://tracker.openbittorrent.com:80/announce',
    'http://tracker.opentrackr.org:1337/announce',
    'https://tracker.opentrackr.org:443/announce',
    'https://opentracker.i2p.rocks:443/announce',
  ];

  final Map<String, dt.TorrentTask> _tasks = {};
  final Map<String, Timer> _pollTimers = {};
  final Map<String, Timer> _scrapeTimers = {};
  final Map<String, Timer> _healthCheckTimers = {};
  final Map<String, Timer> _fastHealthCheckTimers = {};
  final Map<String, Timer> _progressTimers = {};
  final Map<String, int> _peerlessCounters = {};
  final Map<String, int> _zeroProgressCounters = {};
  final Map<String, int> _stallRecoveryCycles = {};
  final Set<String> _hardRecoveryInFlight = <String>{};
  final Map<String, int> _hardRestartCounts = {};
  final Map<String, DateTime> _nextAllowedHardRestart = {};
  final Map<String, List<Uri>> _torrentTrackers = {};
  final Map<String, List<String>> _connectionLogs = {};
  final Map<String, DateTime> _lastProgressLogTimes = {};
  final Map<String, double> _lastReportedProgressByTorrent = {};
  final Map<String, DateTime> _lastProgressChangeAtByTorrent = {};
  final Map<String, DateTime> _lastRefreshAtByTorrent = {};
  final Map<String, int> _lastDownloadedByTorrent = {};
  final Map<String, int> _stagnantDownloadIntervals = {};
  final Map<String, int> _uploadedBytesByTorrent = {};
  final Map<String, DateTime> _lastUploadedSampleByTorrent = {};
  final Map<String, int> _scrapedSeedersByTorrent = {};
  final Map<String, int> _scrapedLeechersByTorrent = {};
  final Set<String> _refreshInFlight = <String>{};
  final Set<String> _forceRedownloadInFlight = <String>{};
  DateTime _lastPeerLogTime = DateTime.fromMillisecondsSinceEpoch(0);
  int _peerEventsSinceLastLog = 0;
  DateTime _lastDhtLogTime = DateTime.fromMillisecondsSinceEpoch(0);
  int _dhtNodesSinceLastLog = 0;
  bool _defaultPortsBlocked = false;

  int get currentDhtNodeCount {
    int nodes = 0;
    for (final task in _tasks.values) {
      try {
        final dynamic t = task;
        final dht = t.dhtNodeCount as int? ?? 0;
        nodes += dht;
      } catch (_) {
        // ignore if not available
      }
    }
    return nodes;
  }

  int get activeSpiresCount => currentDhtNodeCount;

  int get totalPeerCount {
    int peers = 0;
    for (final task in _tasks.values) {
      try {
        final dynamic t = task;
        final pcount = t.connectedPeersNumber as int? ?? 0;
        peers += pcount;
      } catch (_) {
        // ignore if not available
      }
    }
    return peers;
  }

  void _bootstrapDhtNetwork() {
    _detectRestrictedNetwork();
  }

  Future<void> _detectRestrictedNetwork() async {
    // Port probe was producing false positives on some networks.
    // Peers are found via DHT/tracker, so do not force restrictions.
    _defaultPortsBlocked = false;
  }

  void _log(String torrentId, String message) {
    final logs = _connectionLogs.putIfAbsent(torrentId, () => []);
    logs.add('[${DateTime.now().toIso8601String()}] $message');
    if (logs.length > 200) {
      logs.removeRange(0, logs.length - 200);
    }
  }

  void _logPeerEventThrottled(String label, dt.TorrentTask task) {
    _peerEventsSinceLastLog++;
    final now = DateTime.now();
    if (now.difference(_lastPeerLogTime).inSeconds >= 10) {
      _peerEventsSinceLastLog = 0;
      _lastPeerLogTime = now;
    }
  }

  void _logDhtThrottled(dt.TorrentTask task) {
    _dhtNodesSinceLastLog++;
    final now = DateTime.now();
    if (now.difference(_lastDhtLogTime).inSeconds >= 10) {
      _dhtNodesSinceLastLog = 0;
      _lastDhtLogTime = now;
    }
  }

  void _logProgressThrottled(String torrentId, dt.TorrentTask task) {
    final now = DateTime.now();
    final last =
        _lastProgressLogTimes[torrentId] ??
        DateTime.fromMillisecondsSinceEpoch(0);
    if (now.difference(last).inSeconds >= 5) {
      _lastProgressLogTimes[torrentId] = now;
    }
  }

  void _recordProgressSample(String torrentId, double progress) {
    final previous = _lastReportedProgressByTorrent[torrentId];
    _lastReportedProgressByTorrent[torrentId] = progress;
    if (previous == null || (progress - previous).abs() >= 0.00001) {
      _lastProgressChangeAtByTorrent[torrentId] = DateTime.now();
    }
  }

  Future<void> _refreshUploadedSnapshot(
    String torrentId,
    dt.TorrentTask task,
  ) async {
    try {
      final stateUploaded = task.stateFile?.uploaded;
      if (stateUploaded != null && stateUploaded >= 0) {
        final prev = _uploadedBytesByTorrent[torrentId] ?? 0;
        _uploadedBytesByTorrent[torrentId] = stateUploaded >= prev
            ? stateUploaded
            : prev;
      }

      final dynamic taskUploaded = (task as dynamic).uploaded;
      final uploaded = taskUploaded is int
          ? taskUploaded
          : int.tryParse(taskUploaded?.toString() ?? '');
      if (uploaded != null && uploaded >= 0) {
        final prev = _uploadedBytesByTorrent[torrentId] ?? 0;
        _uploadedBytesByTorrent[torrentId] = uploaded >= prev ? uploaded : prev;
      }
    } catch (_) {
      // Best-effort snapshot only.
    }
  }

  List<String> getLogs(String torrentId) {
    return List.unmodifiable(_connectionLogs[torrentId] ?? []);
  }

  void clearLogs(String torrentId) {
    _connectionLogs[torrentId]?.clear();
  }

  Future<void> _configureTask(dt.TorrentTask task) async {
    // dtorrent_task_v2 enables DHT/tracker/PEX through internal defaults.
    // CLI-level calls are not available in this API surface.
    await _mapPorts(task);
    if (SettingsService.instance.useDht) {
      _addDhtBootstrapNodes(task);
    }
  }

  Future<void> _mapPorts(dt.TorrentTask task) async {
    // This package version does not expose setPort/UPnP/NAT-PMP mutators.
    // Allow the task to bind ports internally instead of spamming NoSuchMethod.
    _defaultPortsBlocked = true;
  }

  void _addDhtBootstrapNodes(dt.TorrentTask task) {
    for (final endpoint in _defaultDhtBootstrapNodes) {
      try {
        final uri = Uri.parse('udp://$endpoint');
        task.addDHTNode(uri);
      } catch (_) {
        // Ignore malformed bootstrap nodes and continue.
      }
    }
  }

  /// Returns the best SequentialConfig for this torrent:
  /// - Video → streaming-optimised with moov-atom prioritisation
  /// - Audio → streaming-optimised for audio
  /// - Everything else (game installers, archives, etc.) → minimal sequential
  ///   config that still prevents concurrent multi-file write races, which
  ///   is the root cause of the bitfield-cache desync / stuck-at-99% bug.
  ///
  /// IMPORTANT: the caller must pass stream: seqConfig != null to newTask()
  /// so the AdvancedSequentialPieceSelector is actually activated.
  SequentialConfig _sequentialConfigFor(dt.TorrentModel dtModel) {
    const videoExts = <String>{
      '.mkv',
      '.mp4',
      '.avi',
      '.mov',
      '.m4v',
      '.ts',
      '.wmv',
      '.flv',
      '.webm',
      '.mpg',
      '.mpeg',
    };
    const audioExts = <String>{
      '.mp3',
      '.flac',
      '.aac',
      '.ogg',
      '.wav',
      '.m4a',
      '.opus',
    };

    final paths = [
      ...dtModel.files.map((f) => f.path.toLowerCase()),
      if (dtModel.isSingleFile) dtModel.name.toLowerCase(),
    ];

    if (paths.any((p) => videoExts.any(p.endsWith))) {
      return SequentialConfig.forVideoStreaming();
    }
    if (paths.any((p) => audioExts.any(p.endsWith))) {
      return SequentialConfig.forAudioStreaming();
    }
    // Non-media: use minimal sequential to reduce concurrent write races on
    // large multi-file torrents. adaptiveStrategy=true lets the selector fall
    // back to rarest-first if peers are slow, so download speed is preserved.
    return const SequentialConfig(
      lookAheadSize: 8,
      criticalZoneSize: 2 * 1024 * 1024,
      adaptiveStrategy: true,
      minSpeedForSequential: 0,
      autoDetectMoovAtom: false,
      seekLatencyTolerance: 5,
      enablePeerPriority: true,
      enableFastResumption: true,
    );
  }

  void _announceTrackers(String torrentId, dt.TorrentTask task) {
    // Run tracker announcements in background without blocking UI
    unawaited(
      Future(() async {
        try {
          final configuredTrackers = _torrentTrackers[torrentId] ?? [];
          final seen = <String>{};
          final trackers = <Uri>[
            ...configuredTrackers.where((u) => seen.add(u.toString())),
            ..._fallbackTrackers
                .map(Uri.parse)
                .where((u) => seen.add(u.toString())),
          ];
          if (trackers.isEmpty) {
            debugPrint('[Trackers] No trackers found for $torrentId');
            return;
          }

          // Extract info hash from task
          Uint8List? infoHash;
          try {
            final metaInfo = (task as dynamic).metaInfo;
            if (metaInfo != null) {
              final hash = metaInfo.infoHash;
              if (hash is Uint8List) {
                infoHash = hash;
              } else if (hash is String) {
                infoHash = _hexToBytes(hash);
              }
            }
          } catch (e) {
            debugPrint('[Trackers] Failed to get infoHash: $e');
          }

          if (infoHash == null) {
            debugPrint('[Trackers] Could not extract infoHash for $torrentId');
            return;
          }
          final infoHashBytes = infoHash;

          // Announce to all trackers in parallel, ignore individual failures
          await Future.wait(
            trackers.map(
              (trackerUri) =>
                  _announceUrlWithRetry(
                    task,
                    trackerUri,
                    infoHashBytes,
                  ).catchError((e) {
                    _log(
                      torrentId,
                      'Tracker announce failed for $trackerUri: $e',
                    );
                  }),
            ),
          );
        } catch (e) {
          debugPrint('[Trackers] _announceTrackers error: $e');
        }
      }),
    );
  }

  Future<void> _announceUrlWithRetry(
    dt.TorrentTask task,
    Uri url,
    Uint8List infoHash, {
    int retries = 3,
    Duration delay = const Duration(seconds: 2),
  }) async {
    for (var attempt = 1; attempt <= retries; attempt++) {
      try {
        await (task as dynamic).startAnnounceUrl(url, infoHash);
        return;
      } catch (e) {
        final msg = 'Announce URL attempt $attempt failed: $url $e';
        final taskId = taskIdFromTask(task);
        if (taskId.isNotEmpty) _log(taskId, msg);
        if (attempt < retries) {
          await Future.delayed(delay);
        }
      }
    }
    final finalMsg = 'All announce attempts failed for $url';
    final taskId = taskIdFromTask(task);
    if (taskId.isNotEmpty) _log(taskId, finalMsg);
    throw StateError(finalMsg);
  }

  Future<void> announceTrackerUri(Uri uri, Uint8List infoHash) async {
    dt.TorrentTask? task;
    for (final t in _tasks.values) {
      try {
        final taskHash = (t as dynamic).metaInfo?.infoHash;
        if (taskHash != null &&
            taskHash is Uint8List &&
            listEquals(taskHash, infoHash)) {
          task = t;
          break;
        }
      } catch (_) {
        continue;
      }
    }

    if (task != null) {
      try {
        await (task as dynamic).startAnnounceUrl(uri, infoHash);
        debugPrint('Announced tracker via dtorrent_task_v2 for $uri');
      } catch (e, st) {
        debugPrint('dtorrent_task_v2 announceTrackerUri failed for $uri: $e');
        debugPrint(st.toString());
        rethrow;
      }
    } else {
      throw StateError(
        'No active torrent task found for tracker announce: $uri',
      );
    }
  }

  String taskIdFromTask(dt.TorrentTask task) {
    for (final entry in _tasks.entries) {
      if (identical(entry.value, task)) {
        return entry.key;
      }
    }
    return '';
  }

  Uint8List? _hexToBytes(String? hex) {
    if (hex == null || hex.length % 2 != 0) return null;
    final result = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  String _bytesToHex(Uint8List bytes) {
    StringBuffer buf = StringBuffer();
    for (int i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      buf.write((b < 16 ? '0' : '') + b.toRadixString(16));
    }
    return buf.toString();
  }

  bool _looksLikeIPv4(String address) {
    final parts = address.split('.');
    if (parts.length != 4) return false;
    for (final p in parts) {
      final value = int.tryParse(p);
      if (value == null || value < 0 || value > 255) return false;
    }
    return true;
  }

  List<int>? _ipv4ToBytes(String address) {
    if (!_looksLikeIPv4(address)) return null;
    return address.split('.').map((e) => int.parse(e)).toList();
  }

  Future<void> _refreshConnection(String torrentId, dt.TorrentTask task) async {
    debugPrint(
      'Refreshing connection for $torrentId: reannounce trackers and DHT bootstrap',
    );
    _log(torrentId, 'Triggered force refresh.');

    final trackers = _torrentTrackers[torrentId] ?? [];
    _log(torrentId, 'Attempting to contact ${trackers.length} tracker(s).');

    final dynamic maybeInfoHash = (task as dynamic).metaInfo?.infoHash;
    Uint8List? infoHash;
    if (maybeInfoHash is Uint8List) {
      infoHash = maybeInfoHash;
    } else if (maybeInfoHash is String) {
      infoHash = _hexToBytes(maybeInfoHash);
      if (infoHash == null) {
        debugPrint('[HealthCheck] infoHash hex parse failed: $maybeInfoHash');
      }
    } else if (maybeInfoHash != null) {
      debugPrint(
        '[HealthCheck] Unsupported infoHash type: ${maybeInfoHash.runtimeType}',
      );
    }

    int trackerSuccesses = 0;
    if (infoHash != null) {
      for (final url in trackers) {
        try {
          await _announceUrlWithRetry(task, url, infoHash);
          trackerSuccesses++;
        } catch (e) {
          _log(torrentId, 'Tracker $url failed: $e');
        }
      }
    }
    if (trackerSuccesses > 0) {
      _log(
        torrentId,
        'Successfully announced to $trackerSuccesses tracker(s).',
      );
    } else if (trackers.isNotEmpty) {
      _log(torrentId, 'All tracker announcements failed.');
    } else {
      _log(torrentId, 'No trackers configured for this torrent.');
    }

    _addDhtBootstrapNodes(task);
    try {
      for (final node in (task as dynamic).metaInfo?.nodes ?? []) {
        if (node is Map && node['host'] != null && node['port'] != null) {
          final host = node['host'];
          final port = node['port'];
          if (host is String && (port is int || port is String)) {
            task.addDHTNode(Uri.parse('udp://$host:$port'));
          }
        }
      }
    } catch (e, st) {
      debugPrint('Re-bootstrap DHT nodes failed: $e');
      debugPrint(st.toString());
    }
  }

  Future<void> _refreshConnectionIfDue(
    String torrentId,
    dt.TorrentTask task, {
    Duration minInterval = const Duration(minutes: 5),
    String reason = 'periodic_health_check',
  }) async {
    if (_refreshInFlight.contains(torrentId)) {
      _log(torrentId, 'Refresh skipped ($reason): refresh already in flight.');
      return;
    }

    final lastRefresh = _lastRefreshAtByTorrent[torrentId];
    if (lastRefresh != null &&
        DateTime.now().difference(lastRefresh) < minInterval) {
      _log(
        torrentId,
        'Refresh skipped ($reason): cooldown active (${minInterval.inSeconds}s).',
      );
      return;
    }

    _refreshInFlight.add(torrentId);
    _lastRefreshAtByTorrent[torrentId] = DateTime.now();
    try {
      await _refreshConnection(torrentId, task);
    } finally {
      _refreshInFlight.remove(torrentId);
    }
  }

  void _startHealthCheckTimer(String torrentId, dt.TorrentTask task) {
    _healthCheckTimers[torrentId]?.cancel();
    _peerlessCounters[torrentId] = 0;
    _zeroProgressCounters[torrentId] = 0;
    _stallRecoveryCycles[torrentId] = 0;
    _stagnantDownloadIntervals[torrentId] = 0;
    _lastDownloadedByTorrent[torrentId] = task.downloaded ?? 0;

    _healthCheckTimers[torrentId] = Timer.periodic(const Duration(seconds: 30), (
      timer,
    ) async {
      try {
        if (_isTaskComplete(task)) {
          _peerlessCounters[torrentId] = 0;
          _zeroProgressCounters[torrentId] = 0;
          _stallRecoveryCycles[torrentId] = 0;
          return;
        }

        final peers = task.connectedPeersNumber;
        final downloaded = task.downloaded ?? 0;
        final previousDownloaded =
            _lastDownloadedByTorrent[torrentId] ?? downloaded;
        final downloadedDelta = downloaded - previousDownloaded;
        _lastDownloadedByTorrent[torrentId] = downloaded;
        if (downloadedDelta > 0) {
          _lastProgressChangeAtByTorrent[torrentId] = DateTime.now();
        }

        final progress = task.progress;
        final lastProgress =
            _lastReportedProgressByTorrent[torrentId] ?? progress;
        final progressDelta = progress - lastProgress;
        final bool madeForwardProgress =
            downloadedDelta > 64 * 1024 || progressDelta > 0.0001;

        if (madeForwardProgress) {
          _stagnantDownloadIntervals[torrentId] = 0;
          _zeroProgressCounters[torrentId] = 0;
          _stallRecoveryCycles[torrentId] = 0;
        }

        if (peers == 0) {
          try {
            task.requestPeersFromDHT();
          } catch (_) {
            // Older API surfaces may not expose this; ignore.
          }
          _peerlessCounters[torrentId] =
              (_peerlessCounters[torrentId] ?? 0) + 1;
          _log(
            torrentId,
            'No peers for interval, peerless count ${_peerlessCounters[torrentId]}',
          );
          if (_peerlessCounters[torrentId]! >= 8) {
            _peerlessCounters[torrentId] = 0;
            _log(
              torrentId,
              'Peerless intervals reached: requesting DHT peers only (auto-refresh disabled).',
            );
            _addDhtBootstrapNodes(task);
            try {
              task.requestPeersFromDHT();
            } catch (_) {
              // Best-effort only.
            }
          }
        } else {
          if ((_peerlessCounters[torrentId] ?? 0) > 0) {
            _log(torrentId, 'Peers returned at $peers connections');
          }
          _peerlessCounters[torrentId] = 0;
          if (!madeForwardProgress) {
            _stagnantDownloadIntervals[torrentId] =
                (_stagnantDownloadIntervals[torrentId] ?? 0) + 1;

            if (downloaded <= 0 && progress < 0.001) {
              _zeroProgressCounters[torrentId] =
                  (_zeroProgressCounters[torrentId] ?? 0) + 1;
            }

            final stagnantCount = _stagnantDownloadIntervals[torrentId] ?? 0;
            if (stagnantCount >= 8 && task.currentDownloadSpeed <= 0.5) {
              _stagnantDownloadIntervals[torrentId] = 0;
              _stallRecoveryCycles[torrentId] =
                  (_stallRecoveryCycles[torrentId] ?? 0) + 1;
              _log(
                torrentId,
                'Triggering stall recovery after stagnant download intervals (auto-refresh disabled).',
              );
              _addDhtBootstrapNodes(task);
              try {
                task.requestPeersFromDHT();
              } catch (_) {
                // Best-effort only.
              }
              unawaited(_forceStateRecovery(torrentId, task));
              _requestMissingPieces(task);
            }
          } else {
            _stagnantDownloadIntervals[torrentId] = 0;
          }
        }

        final currentProgress = task.progress;

        // Activate faster health checks once past 90%
        if (currentProgress >= 0.90 &&
            !_fastHealthCheckTimers.containsKey(torrentId)) {
          _fastHealthCheckTimers[torrentId] = Timer.periodic(
            const Duration(seconds: 15),
            (_) => _recordProgressSample(
              torrentId,
              _tasks[torrentId]?.progress ?? currentProgress,
            ),
          );
          _log(
            torrentId,
            'Near-complete: upgraded to 15s health-check cadence.',
          );
        }

        if (!_isTaskComplete(task) && currentProgress >= 0.95) {
          final lastChange =
              _lastProgressChangeAtByTorrent[torrentId] ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final stalledFor = DateTime.now().difference(lastChange);
          if (stalledFor >= const Duration(seconds: 90)) {
            _stallRecoveryCycles[torrentId] =
                (_stallRecoveryCycles[torrentId] ?? 0) + 1;
            final cycle = _stallRecoveryCycles[torrentId] ?? 0;
            _log(
              torrentId,
              'Near-complete stall at ${(currentProgress * 100).toStringAsFixed(2)}% '
              '(stalled ${stalledFor.inSeconds}s, cycle $cycle).',
            );

            if (cycle == 1) {
              // Cycle 1: rebuild bitfield from disk and request missing pieces.
              TorrentService.instance.invalidateDiskSnapshot(torrentId);
              unawaited(TorrentService.instance.refreshTorrentStates());
              try {
                task.requestPeersFromDHT();
              } catch (_) {}
              unawaited(_forceStateRecovery(torrentId, task));
              _requestMissingPieces(task);
            } else if (cycle == 2) {
              // Cycle 2: retry DHT peer discovery + explicitly request missing pieces.
              try {
                task.requestPeersFromDHT();
              } catch (_) {}
              _requestMissingPieces(task);
              unawaited(_forceStateRecovery(torrentId, task));
            } else if (cycle >= 3) {
              // Cycle 3+: keep torrent active and continue piece recovery.
              _stallRecoveryCycles[torrentId] = 0;
              _log(
                torrentId,
                'Near-complete stall persists; continuing piece recovery without auto-refresh/hard-restart.',
              );
              try {
                task.requestPeersFromDHT();
              } catch (_) {}
              _requestMissingPieces(task);
              unawaited(_forceStateRecovery(torrentId, task));
            }
          }
        }
      } catch (e, st) {
        debugPrint('[HealthCheck] Error (non-fatal): $e');
        debugPrint(st.toString());
      }
    });
  }

  final _statusController = StreamController<TorrentEngineStatus>.broadcast();
  Stream<TorrentEngineStatus> get statusStream => _statusController.stream;

  bool isRunning(String torrentId) => _tasks.containsKey(torrentId);

  Future<void> forceRefresh(String torrentId) async {
    final task = _tasks[torrentId];
    if (task == null) {
      debugPrint('forceRefresh: torrent not active in memory: $torrentId');
      return;
    }
    await _refreshConnectionIfDue(
      torrentId,
      task,
      minInterval: const Duration(seconds: 20),
      reason: 'manual_force_refresh',
    );
  }

  /// Verifies all downloaded pieces against their SHA-1 hashes.
  /// Marks corrupted pieces for re-download without deleting good data.
  Future<Map<String, dynamic>> recheckTorrent(String torrentId) async {
    final torrent = await TorrentService.instance.getTorrentById(torrentId);
    if (torrent == null) throw StateError('Torrent not found: $torrentId');

    final savePath = (torrent.filePath?.trim().isNotEmpty == true)
        ? torrent.filePath!.trim()
        : SettingsService.instance.downloadDestination.trim();
    if (savePath.isEmpty)
      throw StateError('No save path for torrent $torrentId');

    final task = _tasks[torrentId];
    final wasRunning = task != null;
    if (wasRunning) await stopTorrent(torrentId);

    await TorrentService.instance.updateTorrentStatus(torrentId, 'rechecking');

    try {
      dt.TorrentModel? dtModel;
      if (task != null) {
        dtModel = (task as dynamic).metaInfo as dt.TorrentModel?;
      }
      if (dtModel == null) {
        // Try to parse local .torrent file if available
        if (torrent.type == 'torrent_file' &&
            torrent.filePath != null &&
            _isTorrentFilePath(torrent.filePath)) {
          dtModel = await dt.TorrentModel.parse(torrent.filePath!);
        }
      }
      if (dtModel == null)
        throw StateError('No torrent metadata available to recheck');

      // Build pieces list either from running task or construct from model
      List<dt_piece.Piece> pieces = [];
      if (task != null) {
        pieces = (task as dynamic).pieceManager?.pieces?.values?.toList() ?? [];
      } else {
        // Construct minimal Piece objects from model piece hashes
        final metaPieces = dtModel.pieces ?? [];
        var offset = 0;
        for (var i = 0; i < metaPieces.length; i++) {
          final byteLength = (i == metaPieces.length - 1)
              ? dtModel.lastPieceLength
              : dtModel.pieceLength;
          final hashBytes = metaPieces[i];
          final hashString = hashBytes
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join();
          pieces.add(dt_piece.Piece(hashString, i, byteLength, offset));
          offset += byteLength;
        }
      }

      final recovery = dt.StateRecovery(dtModel, savePath, pieces);
      await recovery.backupStateFile();

      final validator = dt.FileValidator(dtModel, pieces, savePath);
      final result = await validator.validateAll();

      if (result.isValid) {
        await TorrentService.instance.updateTorrentStatus(torrentId, 'seeding');
      } else {
        await TorrentService.instance.updateTorrentStatus(
          torrentId,
          'downloading',
        );
      }

      if (wasRunning) await startTorrent(torrentId, destinationPath: savePath);

      return {
        'validPieces':
            result.totalBytes - result.invalidPieces.length, // approximate
        'invalidPieces': result.invalidPieces.length,
        'isValid': result.isValid,
      };
    } catch (e) {
      await TorrentService.instance.updateTorrentStatus(
        torrentId,
        'error_recheck_failed',
      );
      rethrow;
    }
  }

  Future<void> startTorrent(String torrentId, {String? destinationPath}) async {
    // If already running, do nothing
    if (isRunning(torrentId)) return;

    final torrent = await TorrentService.instance.getTorrentById(torrentId);
    if (torrent == null) throw StateError('Torrent not found: $torrentId');

    final hasTorrentFileSource =
        torrent.type == 'torrent_file' && _isTorrentFilePath(torrent.filePath);

    if (hasTorrentFileSource) {
      await _startFromFile(torrent, destinationPath: destinationPath);
    } else if (torrent.magnetLink != null) {
      await _startFromMagnet(torrent, destinationPath: destinationPath);
    } else {
      throw StateError('Torrent has no source');
    }
  }

  /// Attach DHT event listeners to a task BEFORE task.start() is called
  /// This ensures DHT events that fire during startup are captured
  void _attachDhtListeners(String torrentId, dt.TorrentTask task) {
    final dht = task.dht;
    if (dht == null) return;

    dht.createListener()?..on<NewPeerEvent>((event) {
      _logDhtThrottled(task);
      try {
        if (Platform.isAndroid) {
          task.addPeer(event.address, dt.PeerSource.dht);
        } else {
          task.addPeer(event.address, dt.PeerSource.dht, type: dt.PeerType.TCP);
        }
      } catch (_) {
        try {
          task.addPeer(event.address, dt.PeerSource.dht);
        } catch (_) {
          _logPeerEventThrottled('dht peer add failed', task);
        }
      }
    });

    dht.krpc?.createListener()?..on<AnnouncePeerResponseEvent>((event) {
      _logDhtThrottled(task);

      // Try adding direct announce peer from event.address:event.port
      final address = event.address;
      final port = event.port;
      try {
        final caddr = CompactAddress(address, port);
        task.addPeer(caddr, dt.PeerSource.dht);
        _logPeerEventThrottled('peer update', task);
      } catch (_) {
        _logPeerEventThrottled('dht direct peer add failed', task);
      }

      final data = event.data;
      if (data is Map) {
        final values = data['values'];
        final peersField = data['peers'] ?? values;
        if (peersField is Iterable) {
          for (final peer in peersField) {
            try {
              CompactAddress? caddr;
              if (peer is CompactAddress) {
                caddr = peer;
              } else if (peer is List<int>) {
                if (peer.length == 6) {
                  caddr = CompactAddress.parseIPv4Address(peer);
                } else if (peer.length == 18) {
                  caddr = CompactAddress.parseIPv6Address(peer);
                }
              } else if (peer is String) {
                final bytes = peer.codeUnits;
                if (bytes.length == 6) {
                  caddr = CompactAddress.parseIPv4Address(bytes);
                } else if (bytes.length == 18) {
                  caddr = CompactAddress.parseIPv6Address(bytes);
                }
              }
              if (caddr != null) {
                task.addPeer(caddr, dt.PeerSource.dht);
                _logPeerEventThrottled('peer update', task);
              }
            } catch (_) {
              _logPeerEventThrottled('dht peer add failed', task);
            }
          }
        }
      }
    });
  }

  Future<void> _startFromFile(
    TorrentModel torrent, {
    String? destinationPath,
  }) async {
    final dtModel = await dt.TorrentModel.parse(torrent.filePath!);
    final preferredDownloadPath = destinationPath?.trim().isNotEmpty == true
        ? destinationPath
        : _storedDownloadDirForResume(torrent);
    final saveDir = await _resolveWritableDownloadDir(preferredDownloadPath);

    final totalBytes = dtModel.files.fold<int>(0, (s, f) => s + f.length);
    if (totalBytes > 0 && (torrent.totalSize ?? 0) != totalBytes) {
      await TorrentService.instance.updateTorrent(
        torrent.copyWith(totalSize: totalBytes, filePath: saveDir),
      );
    } else {
      await TorrentService.instance.updateTorrent(
        torrent.copyWith(filePath: saveDir),
      );
    }

    // Aggressive peer connectivity: enable DHT, PEX, sequential video streaming,
    // and use fallback trackers.
    // stream: true activates AdvancedSequentialPieceSelector — required for
    // the SequentialConfig to take effect. Without it the config is ignored.
    final task = dt.TorrentTask.newTask(
      dtModel,
      saveDir,
      true, // stream=true activates sequential piece selection
      null,
      null,
      _sequentialConfigFor(dtModel),
    );
    _tasks[torrent.id] = task;
    _wireEvents(torrent.id, task);
    await _configureTask(task);
    _torrentTrackers[torrent.id] = dtModel.announces
        .map<Uri>((u) => Uri.parse(u.toString()))
        .toList();
    _startHealthCheckTimer(torrent.id, task);

    // Attach DHT listeners BEFORE starting task to capture all events
    _attachDhtListeners(torrent.id, task);

    // Task configuration (port/NAT) already applied in _configureTask.
    // Backup existing state file before starting the task and attempt recovery
    try {
      final savePath = saveDir;
      if (savePath.isNotEmpty) {
        try {
          final preRecovery = dt.StateRecovery(dtModel, savePath, []);
          final backupOk = await preRecovery.backupStateFile();
          if (!backupOk) {
            debugPrint(
              'State file backup failed (non-fatal) for ${torrent.id}',
            );
          }
        } catch (e) {
          debugPrint('State backup step failed (non-fatal): $e');
        }
      }
    } catch (_) {}

    final startup = await task.start();
    _forceAllFilesNormalPriority(task);
    unawaited(_hideBtStateFilesOnWindows(saveDir, torrentId: torrent.id));
    // After starting the task, attempt recovery using the task's piece list
    try {
      final savePath = saveDir;
      if (savePath.isNotEmpty) {
        try {
          final pieces =
              (task as dynamic).pieceManager?.pieces?.values?.toList() ?? [];
          final recovery = dt.StateRecovery(dtModel, savePath, pieces);
          await recovery.recoverStateFile();
          unawaited(
            _hideBtStateFilesOnWindows(savePath, torrentId: torrent.id),
          );
        } catch (e) {
          debugPrint('State recovery failed (non-fatal): $e');
        }
      }
    } catch (_) {}
    final startupUploaded = startup['uploaded'] as int?;
    if (startupUploaded != null && startupUploaded >= 0) {
      _uploadedBytesByTorrent[torrent.id] = startupUploaded;
    }

    // Ensure tasks are running
    try {
      (task as dynamic).resume();
    } catch (_) {}
    try {
      (task as dynamic).unpause();
    } catch (_) {}
    _ensureTaskRunningMode(task);

    _progressTimers[torrent.id]?.cancel();
    _progressTimers[torrent.id] = Timer.periodic(const Duration(seconds: 5), (
      _,
    ) {
      _logProgressThrottled(torrent.id, task);
    });

    // Allow the DHT a short moment to bootstrap before firing many tracker requests
    await Future.delayed(const Duration(seconds: 2));

    // Use all announce URLs and fallback public trackers in parallel
    final seenUrls = <String>{};
    const fallbackTrackers = [
      'udp://tracker.openbittorrent.com:80/announce',
      'udp://tracker.opentrackr.org:1337/announce',
      'udp://tracker.coppersurfer.tk:6969/announce',
      'udp://tracker.leechers-paradise.org:6969/announce',
      'udp://tracker.internetwarriors.net:1337/announce',
      'udp://exodus.desync.com:6969/announce',
      'http://tracker.openbittorrent.com:80/announce',
      'http://tracker.opentrackr.org:1337/announce',
      'https://tracker.opentrackr.org:443/announce',
      'https://opentracker.i2p.rocks:443/announce',
    ];

    final announceUrls = <Uri>[];
    for (final u in dtModel.announces) {
      final s = u.toString();
      if (seenUrls.add(s)) announceUrls.add(Uri.parse(s));
    }
    for (final s in fallbackTrackers) {
      if (seenUrls.add(s)) announceUrls.add(Uri.parse(s));
    }

    await Future.wait(
      announceUrls.map(
        (uri) => _announceUrlWithRetry(task, uri, dtModel.infoHashBuffer)
            .catchError((e) {
              debugPrint('Tracker announce failed for $uri: $e');
            }),
      ),
    );

    // DHT bootstrap
    try {
      for (final node in dtModel.nodes) {
        task.addDHTNode(node);
      }
    } catch (e, st) {
      debugPrint('DHT node addition error for torrent ${torrent.id}: $e');
      debugPrint(st.toString());
    }

    await TorrentService.instance.updateTorrentStatus(
      torrent.id,
      'downloading',
    );
    _startPollTimer(torrent.id, task);
    _startScrapeTimer(torrent.id, task);

    final status = _isTaskComplete(task) ? 'seeding' : 'downloading';
    await TorrentService.instance.updateTorrentStatus(torrent.id, status);
  }

  Future<void> _startFromMagnet(
    TorrentModel torrent, {
    String? destinationPath,
  }) async {
    final sourceMagnet = torrent.magnetLink?.trim() ?? '';
    if (sourceMagnet.isEmpty) {
      throw FormatException('Invalid magnet link');
    }
    final effectiveMagnet = _augmentMagnetWithFallbackTrackers(sourceMagnet);
    final magnet = dt.MagnetParser.parse(effectiveMagnet);
    if (magnet == null) throw FormatException('Invalid magnet link');

    // Step 1: fetch metadata from the swarm with caching and retry logic.
    dt.TorrentModel? dtModel;
    dt.MetadataDownloader? downloader;
    String errorMessage = '';

    // First, try to load from cache (fastest path for resuming torrents)
    try {
      final infoHashString = _bytesToHex(Uint8List.fromList(magnet.infoHash));
      final cachedMetadata = await dt.MetadataDownloader.loadFromCache(
        infoHashString,
      );
      if (cachedMetadata != null) {
        _log(torrent.id, 'Using cached metadata from previous download');
        final msg = decode(cachedMetadata);
        dtModel = await _parseTorrentModelFromRawBencode(msg);
      }
    } catch (e) {
      _log(torrent.id, 'Cache lookup failed (this is OK): $e');
    }

    // If cache miss, try to download with retry logic
    if (dtModel == null) {
      for (int attempt = 1; attempt <= 2; attempt++) {
        try {
          downloader = dt.MetadataDownloader.fromMagnet(effectiveMagnet);
          final completer = Completer<dt.TorrentModel>();

          downloader.createListener()
            ..on<dt.MetaDataDownloadComplete>((event) async {
              if (completer.isCompleted) return;
              try {
                final Uint8List rawData = Uint8List.fromList(event.data);
                final msg = decode(rawData);

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

          // First attempt: 10 minutes timeout, retry attempt: 3 minutes
          final timeout = attempt == 1
              ? const Duration(minutes: 10)
              : const Duration(minutes: 3);

          dtModel = await completer.future.timeout(
            timeout,
            onTimeout: () =>
                throw TimeoutException('Metadata download timed out'),
          );

          // Success - break out of retry loop
          _log(
            torrent.id,
            'Metadata downloaded successfully on attempt $attempt',
          );
          break;
        } catch (e) {
          errorMessage = e.toString();
          _log(torrent.id, 'Metadata download attempt $attempt failed: $e');

          if (attempt < 2) {
            // Wait before retrying
            await Future.delayed(const Duration(seconds: 2));
          }
        }
      }
    }

    if (dtModel == null) {
      // Metadata download failed after all attempts - this is a hard error
      throw TimeoutException(
        'Failed to fetch metadata for ${torrent.id}: $errorMessage',
      );
    }

    final resolvedName = dtModel.name.trim();
    final updatedName =
        resolvedName.isNotEmpty &&
            !resolvedName.toLowerCase().startsWith('magnet:')
        ? resolvedName
        : torrent.name;

    // Metadata reconstruction can normalize fields and alter encoded info bytes.
    // Keep swarm identity anchored to the magnet info-hash.
    if (!listEquals(dtModel.infoHashBuffer, magnet.infoHash) &&
        magnet.infoHash.length == 20) {
      dtModel = dt.TorrentModel(
        name: dtModel.name,
        files: dtModel.files,
        infoHashBuffer: Uint8List.fromList(magnet.infoHash),
        pieceLength: dtModel.pieceLength,
        pieces: dtModel.pieces,
        announces: dtModel.announces,
        nodes: dtModel.nodes,
        length: dtModel.length,
        version: dtModel.version,
        metaVersion: dtModel.metaVersion,
        fileTree: dtModel.fileTree,
        pieceLayers: dtModel.pieceLayers,
        rootHash: dtModel.rootHash,
        infoDictBytes: dtModel.infoDictBytes,
        rawData: dtModel.rawData,
      );
      _log(torrent.id, 'Adjusted torrent model info-hash to magnet xt hash.');
    }

    final preferredDownloadPath = destinationPath?.trim().isNotEmpty == true
        ? destinationPath
        : _storedDownloadDirForResume(torrent);
    final saveDir = await _resolveWritableDownloadDir(preferredDownloadPath);

    final totalBytes = dtModel.files.fold<int>(0, (s, f) => s + f.length);
    if (totalBytes > 0) {
      await TorrentService.instance.updateTorrent(
        torrent.copyWith(
          name: updatedName,
          totalSize: totalBytes,
          filePath: saveDir,
        ),
      );
    } else {
      await TorrentService.instance.updateTorrent(
        torrent.copyWith(name: updatedName, filePath: saveDir),
      );
    }

    // Aggressive peer connectivity: enable DHT, PEX, sequential video streaming,
    // and use fallback trackers.
    // stream: true activates AdvancedSequentialPieceSelector — required for
    // the SequentialConfig to take effect. Without it the config is ignored.
    final task = dt.TorrentTask.newTask(
      dtModel,
      saveDir,
      true, // stream=true activates sequential piece selection
      magnet.webSeeds.isNotEmpty ? magnet.webSeeds : null,
      magnet.acceptableSources.isNotEmpty ? magnet.acceptableSources : null,
      _sequentialConfigFor(dtModel),
    );

    // Do not auto-apply magnet `so` file selection hints.
    // Many public magnets include `so` for partial/preview downloads, which can
    // make full-torrent progress appear hard-stuck at a fixed percent.
    // Keep default behavior aligned with mainstream clients: download full content
    // unless the user explicitly changes file priorities in-app.
    if (magnet.selectedFileIndices?.isNotEmpty == true) {
      _log(
        torrent.id,
        'Ignoring magnet so= file-selection hint to avoid implicit partial downloads.',
      );
    }

    _tasks[torrent.id] = task;
    _wireEvents(torrent.id, task);
    await _configureTask(task);
    _torrentTrackers[torrent.id] = [
      ...magnet.trackers
          .map<Uri>((s) => Uri.parse(s.toString()))
          .where((u) => u.toString().isNotEmpty),
      ...dtModel.announces.map<Uri>((u) => Uri.parse(u.toString())),
    ];
    _startHealthCheckTimer(torrent.id, task);

    // Attach DHT listeners BEFORE starting task to capture all events
    _attachDhtListeners(torrent.id, task);

    // Start task in background without blocking UI
    try {
      final startup = await task.start();
      _forceAllFilesNormalPriority(task);
      unawaited(_hideBtStateFilesOnWindows(saveDir, torrentId: torrent.id));
      final startupUploaded = startup['uploaded'] as int?;
      if (startupUploaded != null && startupUploaded >= 0) {
        _uploadedBytesByTorrent[torrent.id] = startupUploaded;
      }
    } catch (_) {
      _cleanup(torrent.id);
      rethrow;
    }

    // Ensure tasks are running
    try {
      (task as dynamic).resume();
    } catch (_) {}
    try {
      (task as dynamic).unpause();
    } catch (_) {}
    _ensureTaskRunningMode(task);

    _progressTimers[torrent.id]?.cancel();
    _progressTimers[torrent.id] = Timer.periodic(const Duration(seconds: 5), (
      _,
    ) {
      _logProgressThrottled(torrent.id, task);
    });

    // Announce to trackers in background without blocking UI
    _announceTrackers(torrent.id, task);

    // Hand off peers from metadata fetch so download starts immediately (if downloader exists).
    if (downloader != null) {
      for (final peer in downloader.activePeers) {
        try {
          task.addPeer(peer.address, dt.PeerSource.manual, type: peer.type);
        } catch (e, st) {
          debugPrint('Peer add error: ${peer.address} $e');
          debugPrint(st.toString());
        }
      }
    }

    // DHT bootstrap
    try {
      for (final node in dtModel.nodes) {
        task.addDHTNode(node);
      }
    } catch (e, st) {
      debugPrint('DHT node addition error for torrent ${torrent.id}: $e');
      debugPrint(st.toString());
    }

    final status = _isTaskComplete(task) ? 'seeding' : 'downloading';
    await TorrentService.instance.updateTorrentStatus(torrent.id, status);
    _startPollTimer(torrent.id, task);
    _startScrapeTimer(torrent.id, task);
  }

  Future<dt.TorrentModel> _parseTorrentModelFromRawBencode(
    dynamic infoDict,
  ) async {
    if (infoDict is! Map) {
      throw FormatException('Invalid metadata: expected info dictionary');
    }

    // Normalize all map and list values; keep binary buffers in place.
    final normalizedInfo = _normalizeBencodeMap(infoDict);
    if (normalizedInfo is! Map<String, dynamic>) {
      throw FormatException('Invalid metadata after normalization');
    }

    _ensureInfoNameIsString(normalizedInfo);
    _ensureAnnounceFieldsAreString(normalizedInfo);
    _ensureFilePathsAreString(normalizedInfo);

    _normalizePiecesField(normalizedInfo);
    final torrentMap = <String, dynamic>{'info': normalizedInfo};

    return dt.TorrentParser.parseFromMap(torrentMap);
  }

  void _normalizePiecesField(Map<String, dynamic> info) {
    final piecesValue = info['pieces'];
    if (piecesValue is List) {
      // Some decoders can return piece bytes as List<int> segments, assemble to Uint8List.
      try {
        final bytes = <int>[];
        for (final segment in piecesValue) {
          if (segment is int) {
            bytes.add(segment);
          } else if (segment is Uint8List) {
            bytes.addAll(segment);
          } else if (segment is List<int>) {
            bytes.addAll(segment);
          }
        }
        info['pieces'] = Uint8List.fromList(bytes);
      } catch (_) {
        // If conversion fails, leave as-is and allow parser to report a better error.
      }
    }
  }

  void _ensureInfoNameIsString(Map<String, dynamic> info) {
    final decoded = _decodeBencodeString(name: info['name']);
    if (decoded != null && decoded.isNotEmpty) {
      info['name'] = decoded;
    }
  }

  void _ensureAnnounceFieldsAreString(Map<String, dynamic> info) {
    final announce = _decodeBencodeString(name: info['announce']);
    if (announce != null && announce.isNotEmpty) {
      info['announce'] = announce;
    }

    if (info['announce-list'] is List) {
      info['announce-list'] = (info['announce-list'] as List).map((tier) {
        if (tier is List) {
          return tier.map((url) {
            final decoded = _decodeBencodeString(name: url);
            return decoded ?? url;
          }).toList();
        }
        return tier;
      }).toList();
    }
  }

  void _ensureFilePathsAreString(Map<String, dynamic> info) {
    if (info['files'] is List) {
      for (final entry in (info['files'] as List)) {
        if (entry is Map && entry.containsKey('path')) {
          final pathList = entry['path'];
          if (pathList is List) {
            entry['path'] = pathList.map((component) {
              final decoded = _decodeBencodeString(name: component);
              return decoded ?? component.toString();
            }).toList();
          }
        }
      }
    }

    if (info['file tree'] is Map) {
      // Convert file tree keys and names from Uint8List to String if needed.
      info['file tree'] = _normalizeFileTreeKeys(info['file tree']);
    }
  }

  Map<String, dynamic> _normalizeFileTreeKeys(dynamic treeData) {
    if (treeData is! Map) return {};
    final result = <String, dynamic>{};
    for (final entry in treeData.entries) {
      final key = _decodeBencodeString(name: entry.key) ?? entry.key.toString();
      final value = entry.value;
      if (value is Map) {
        if (value.containsKey('')) {
          final subentry = value[''];
          if (subentry is Map) {
            final lengthValue = subentry['length'];
            final piecesRoot = subentry['pieces root'];
            final resSub = <String, dynamic>{};
            if (lengthValue is int) resSub['length'] = lengthValue;
            if (piecesRoot is Uint8List) resSub['pieces root'] = piecesRoot;
            result[key] = {'': resSub};
          } else {
            result[key] = value;
          }
        } else {
          result[key] = _normalizeFileTreeKeys(value);
        }
      } else {
        result[key] = value;
      }
    }
    return result;
  }

  dynamic _normalizeBencodeMap(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.fromEntries(
        value.entries.map((entry) {
          final key =
              _decodeBencodeString(name: entry.key) ?? entry.key.toString();
          return MapEntry(key, _normalizeBencodeMap(entry.value));
        }),
      );
    }

    if (value is List) {
      return value.map((item) => _normalizeBencodeMap(item)).toList();
    }

    if (value is Uint8List) {
      // Keep raw bytes for binary fields (pieces, roots etc), decode names separately.
      return value;
    }

    return value;
  }

  String? _decodeBencodeString({required dynamic name}) {
    if (name is String) {
      return name;
    }
    if (name is Uint8List) {
      try {
        return utf8.decode(name, allowMalformed: true);
      } catch (_) {
        return null;
      }
    }
    if (name is List<int>) {
      try {
        return utf8.decode(name, allowMalformed: true);
      } catch (_) {
        return null;
      }
    }
    if (name is List) {
      final bytes = <int>[];
      for (final item in name) {
        if (item is int) {
          bytes.add(item);
        } else {
          return null;
        }
      }
      try {
        return utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  bool _hasAllPiecesComplete(dt.TorrentTask task) {
    try {
      final dynamic t = task;
      final fileComplete = (t.fileManager?.isAllComplete as bool?) ?? false;
      final piecesMap = t.pieceManager?.pieces as Map?;
      if (piecesMap == null || piecesMap.isEmpty) {
        return fileComplete;
      }

      for (final entry in piecesMap.entries) {
        final isComplete =
            (entry.value.isCompletelyDownloaded as bool?) ?? false;
        if (!isComplete) {
          return false;
        }
      }
      return true;
    } catch (_) {
      // Fallback to task-level completion heuristics when piece map is unavailable.
      return _isTaskComplete(task);
    }
  }

  void _requestMissingPieces(dt.TorrentTask task) {
    try {
      final dynamic t = task;
      final piecesMap = t.pieceManager?.pieces as Map?;
      if (piecesMap == null || piecesMap.isEmpty) return;

      for (final entry in piecesMap.entries) {
        final isComplete =
            (entry.value.isCompletelyDownloaded as bool?) ?? false;
        if (!isComplete) {
          try {
            t.requestPiece(entry.key);
          } catch (_) {
            // Ignore per-piece request failures and continue.
          }
        }
      }
    } catch (_) {
      // Best-effort only.
    }
  }

  Future<bool> _verifyCompletionIntegrity(
    String torrentId,
    dt.TorrentTask task,
  ) async {
    await _forceStateRecovery(torrentId, task);
    final complete = _hasAllPiecesComplete(task);
    if (!complete) {
      _log(
        torrentId,
        'Completion check failed after recovery: missing/corrupt pieces detected. Resuming download.',
      );
      _requestMissingPieces(task);
      _ensureTaskRunningMode(task);
      return false;
    }
    return true;
  }

  void _wireEvents(String torrentId, dt.TorrentTask task) {
    task.createListener()
      ..on<dt.StateFileUpdated>((_) {
        unawaited(_refreshUploadedSnapshot(torrentId, task));
        _emitStats(torrentId, task);
      })
      ..on<dt.TaskCompleted>((_) async {
        _emitStats(torrentId, task);

        final hasOutput = await _verifyOutputExists(torrentId, task);
        await TorrentService.instance.updateTorrentStatus(
          torrentId,
          hasOutput ? 'seeding' : 'error_missing_output',
        );
        final torrent = await TorrentService.instance.getTorrentById(torrentId);
        if (torrent != null && hasOutput) {
          try {
            await NotificationService.instance.showDownloadComplete(
              torrent.name,
            );
          } catch (e) {
            debugPrint('Notification suppressed (non-fatal): $e');
          }
        }

        // Defer integrity verification to background so it doesn't block completion.
        // This prevents Android fork/libbinder crashes during isolate spawning for validation.
        // Verification is non-critical — files already written and marked 100% complete.
        unawaited(_verifyCompletionIntegrityDeferred(torrentId, task));
      })
      ..on<dt.TaskStopped>((_) {
        _cleanup(torrentId);
      });
  }

  /// Deferred background verification that doesn't block completion.
  /// Runs after TaskCompleted is marked so Android isolate/JNI issues don't crash the app.
  /// Returns early if task is disposed or if file manager confirms all pieces are written.
  Future<void> _verifyCompletionIntegrityDeferred(
    String torrentId,
    dt.TorrentTask task,
  ) async {
    try {
      // Skip if task is no longer active (user stopped/deleted it)
      if (!_tasks.containsKey(torrentId) || _tasks[torrentId] != task) {
        return;
      }

      // Defer this 2 seconds to let file writes complete and handles to close
      await Future.delayed(Duration(seconds: 2));

      // Double-check task still exists
      if (!_tasks.containsKey(torrentId) || _tasks[torrentId] != task) {
        return;
      }

      // If file manager confirms all pieces are on disk, skip verbose disk validation.
      // This prevents Android fork crashes from isolate spawning during heavy I/O.
      final fileManagerComplete = (task.fileManager?.isAllComplete as bool?) ?? false;
      _log(
        torrentId,
        'Deferred completion check: fileManager.isAllComplete=$fileManagerComplete',
      );
      if (fileManagerComplete) {
        _log(torrentId, 'File manager confirms all pieces written. Skipping disk validation.');
        return; // Already confirmed complete, no need for re-verification
      }

      // Only run StateRecovery if file manager doesn't confirm completion.
      // This is safest path for catching re-download scenarios.
      _log(torrentId, 'Running deferred state recovery...');
      await _forceStateRecoveryWithTimeout(torrentId, task, Duration(seconds: 30));
    } catch (e) {
      debugPrint('[DeferredVerification] $torrentId: $e');
      // Non-fatal — torrent already marked complete by task engine.
    }
  }

  /// StateRecovery with timeout to prevent hanging on Android I/O.
  Future<void> _forceStateRecoveryWithTimeout(
    String torrentId,
    dt.TorrentTask task,
    Duration timeout,
  ) async {
    try {
      await _forceStateRecovery(torrentId, task).timeout(
        timeout,
        onTimeout: () {
          _log(
            torrentId,
            'State recovery timed out after ${timeout.inSeconds}s. '
            'Skipping re-download requests (torrent already marked complete).',
          );
        },
      );
    } catch (e) {
      debugPrint('[StateRecoveryTimeout] $torrentId: $e');
    }
  }

  Future<bool> _verifyOutputExists(
    String torrentId,
    dt.TorrentTask task,
  ) async {
    final torrent = await TorrentService.instance.getTorrentById(torrentId);
    final outputPath = torrent?.filePath;
    if (outputPath == null || outputPath.trim().isEmpty) {
      return false;
    }

    final saveDir = outputPath.trim();
    final expectedFiles = task.metaInfo.files;
    if (expectedFiles.isEmpty) {
      return false;
    }

    var expectedBytes = 0;
    var existingBytes = 0;
    for (final file in expectedFiles) {
      expectedBytes += file.length;
      final relativePath = file.path.replaceAll('/', Platform.pathSeparator);
      final fullPath = p.join(saveDir, relativePath);
      final diskType = await FileSystemEntity.type(
        fullPath,
        followLinks: false,
      );
      if (diskType != FileSystemEntityType.file) {
        continue;
      }
      try {
        existingBytes += await File(fullPath).length();
      } catch (_) {
        // Ignore unreadable files in output validation.
      }
    }

    if (expectedBytes <= 0) {
      return false;
    }

    return existingBytes >= (expectedBytes * 0.98).round();
  }

  void _startPollTimer(String torrentId, dt.TorrentTask task) {
    _pollTimers[torrentId]?.cancel();
    _pollTimers[torrentId] = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!_tasks.containsKey(torrentId)) {
        _pollTimers.remove(torrentId)?.cancel();
        return;
      }
      unawaited(_refreshUploadedSnapshot(torrentId, task));
      _emitStats(torrentId, task);
    });
  }

  /// Restart the poll loop for all active tasks.
  /// Called after window restore to fix frozen progress displays.
  void restartAllPolling() {
    for (final entry in _tasks.entries.toList()) {
      _pollTimers[entry.key]?.cancel();
      _startPollTimer(entry.key, entry.value);
      _log(entry.key, 'Poll loop restarted after window restore.');
    }
    unawaited(TorrentService.instance.refreshTorrentStates());
  }

  void _emitStats(String torrentId, dt.TorrentTask task) {
    final downloaded = task.downloaded ?? 0;
    int uploaded = _uploadedBytesByTorrent[torrentId] ?? 0;
    try {
      final stateUploaded = task.stateFile?.uploaded ?? 0;
      if (stateUploaded > uploaded) {
        uploaded = stateUploaded;
      }
    } catch (_) {
      // Some task implementations may not expose a state file.
    }
    try {
      final dynamicUploaded = (task as dynamic).uploaded as int?;
      if (dynamicUploaded != null && dynamicUploaded > uploaded) {
        uploaded = dynamicUploaded;
      }
    } catch (_) {
      // Some task implementations do not expose uploaded directly.
    }
    final dlSpeed = task.currentDownloadSpeed * 1000; // bytes/ms → bytes/s
    final ulSpeed = task.uploadSpeed * 1000;
    final peers = task.connectedPeersNumber;

    int seeders = task.seederNumber;
    int leechers = (peers - seeders).clamp(0, peers);

    if (task.activePeers != null) {
      seeders = task.activePeers!.where((p) => p.isSeeder).length;
      leechers = task.activePeers!.where((p) => !p.isSeeder).length;
    }

    final scrapedSeeders = _scrapedSeedersByTorrent[torrentId] ?? 0;
    final scrapedLeechers = _scrapedLeechersByTorrent[torrentId] ?? 0;
    if (scrapedSeeders > seeders) seeders = scrapedSeeders;
    if (scrapedLeechers > leechers) leechers = scrapedLeechers;

    final progress = task.progress;
    _recordProgressSample(torrentId, progress);
    final totalLength = task.metaInfo.length ?? task.metaInfo.totalSize;
    final state = _isTaskComplete(task) ? 'seeding' : 'downloading';
    final now = DateTime.now();
    final lastSample = _lastUploadedSampleByTorrent[torrentId];
    if (lastSample != null) {
      final dtSeconds = now.difference(lastSample).inMilliseconds / 1000.0;
      if (dtSeconds > 0 && ulSpeed > 0) {
        uploaded += (ulSpeed * dtSeconds).round();
      }
    }

    _uploadedBytesByTorrent[torrentId] = uploaded;
    _lastUploadedSampleByTorrent[torrentId] = now;

    final seededRatio = totalLength > 0 ? (uploaded / totalLength) : 0.0;
    final seededPct = (seededRatio * 100).clamp(0.0, double.infinity);
    final stalledNearCompletion =
        progress >= 0.95 &&
        ((_lastProgressChangeAtByTorrent[torrentId] == null)
            ? false
            : DateTime.now()
                          .difference(
                            _lastProgressChangeAtByTorrent[torrentId]!,
                          )
                          .inSeconds >=
                      90 &&
                  state != 'seeding');
    final msg = state == 'seeding'
        ? 'Seeding • ${(seededPct).toStringAsFixed(1)}% shared back (${_formatByteCount(uploaded)}/${_formatByteCount(totalLength)}) • $peers peer${peers == 1 ? '' : 's'} connected'
        : peers == 0
        ? 'Searching for peers...'
        : stalledNearCompletion
        ? 'Stalled near completion • ${(progress * 100).toStringAsFixed(1)}% • $peers peer${peers == 1 ? '' : 's'}'
        : downloaded == 0
        ? 'Connected to $peers peer${peers == 1 ? '' : 's'}, waiting for pieces...'
        : '${(progress * 100).toStringAsFixed(1)}% — $peers peer${peers == 1 ? '' : 's'}';

    int dhtNodes = 0;
    int trackers = 0;
    String connectionMsg;

    try {
      dhtNodes = (task as dynamic).dhtNodeCount ?? dhtNodes;
    } catch (_) {
      // ignore - no available field
    }
    try {
      trackers = (task as dynamic).trackerPeersNumber ?? trackers;
    } catch (_) {
      // ignore if unavailable
    }

    if (peers > 0) {
      connectionMsg =
          'Connected to $peers peers (DHT: $dhtNodes, Trackers: $trackers)';
    } else if (dhtNodes == 0) {
      connectionMsg =
          'No DHT nodes found — Check firewall/network or try later';
    } else if (trackers == 0) {
      connectionMsg =
          'DHT active but no trackers responding — Try force refresh';
    } else {
      connectionMsg =
          'Trackers responding but no peers found — Torrent may be dead';
    }

    _statusController.add(
      TorrentEngineStatus(
        torrentId: torrentId,
        downloaded: downloaded,
        uploaded: uploaded,
        progress: progress,
        state: state,
        peers: peers,
        dhtNodes: dhtNodes,
        trackers: trackers,
        seeders: seeders,
        leechers: leechers,
        downloadSpeed: dlSpeed,
        uploadSpeed: ulSpeed,
        seedingProgress: seededRatio.clamp(0.0, 1.0),
        statusMessage: msg,
        connectionMessage: connectionMsg,
      ),
    );
  }

  String _formatByteCount(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
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
      final stats = result.getStatsForInfoHash(task.metaInfo.infoHash);
      if (stats == null) return;
      final existing = await TorrentService.instance.getTorrentById(torrentId);
      if (existing == null) return;
      await TorrentService.instance.updateTorrent(
        existing.copyWith(seeders: stats.complete, leechers: stats.incomplete),
      );
      _scrapedSeedersByTorrent[torrentId] = stats.complete;
      _scrapedLeechersByTorrent[torrentId] = stats.incomplete;
    } catch (_) {
      // Best-effort — scrape must never crash the engine.
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Disk-based state recovery
  // ─────────────────────────────────────────────────────────────────────────

  /// Rebuilds the in-memory bitfield by reading actual bytes from disk and
  /// SHA-1 validating every piece. Called when a torrent stalls near
  /// completion — fixes the cache-desync bug in Bitfield.completedPieces
  /// that causes GTA IV / large multi-file torrents to freeze at 99.x%.
  // ─────────────────────────────────────────────────────────────────────────
  // Platform helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Mark a file as hidden on Windows so .bt.state files don't confuse users.
  /// Safe no-op on non-Windows platforms.
  /// Mark a file as hidden so .bt.state files don't clutter Explorer.
  /// Uses the `attrib` shell command — no win32 FFI import needed,
  /// so this compiles cleanly on Android too. Fire-and-forget.
  void markFileHiddenOnWindows(String filePath) {
    if (!Platform.isWindows) return;
    Process.run('attrib', [
      '+h',
      filePath,
    ]).catchError((_) => ProcessResult(0, 1, '', ''));
  }

  /// Scan a directory and hide any .bt.state files found there.
  Future<void> _hideStateFilesInDir(String dirPath) async {
    if (!Platform.isWindows) return;
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) return;
      await for (final entity in dir.list(recursive: false)) {
        if (entity is File && entity.path.toLowerCase().endsWith('.bt.state')) {
          markFileHiddenOnWindows(entity.path);
        }
      }
    } catch (_) {}
  }

  Future<void> _forceStateRecovery(
    String torrentId,
    dt.TorrentTask task,
  ) async {
    try {
      _log(
        torrentId,
        'Starting disk-based state recovery (bitfield rebuild)...',
      );
      final dynamic t = task;
      String savePath = '';
      try {
        savePath = (t.savePath as String?) ?? '';
      } catch (_) {}
      if (savePath.isEmpty) {
        // Fallback: read filePath from the persisted torrent record
        final torrent = await TorrentService.instance.getTorrentById(torrentId);
        savePath = torrent?.filePath?.trim() ?? '';
      }
      if (savePath.isEmpty) {
        _log(
          torrentId,
          'StateRecovery skipped: could not determine save path.',
        );
        return;
      }

      // Verify save directory is accessible before attempting validation.
      // This prevents crashes on Android when directory is inaccessible.
      final saveDir = Directory(savePath);
      if (!await saveDir.exists()) {
        _log(
          torrentId,
          'StateRecovery skipped: save directory does not exist: $savePath',
        );
        return;
      }

      final dtModel = task.metaInfo;
      List<dt_piece.Piece> pieces = [];
      try {
        final raw = t.pieceManager?.pieces?.values?.toList() ?? [];
        pieces = raw.cast<dt_piece.Piece>();
      } catch (_) {}

      final recovery = dt.StateRecovery(dtModel, savePath, pieces);
      final result = await recovery.recoverStateFile();

      if (result == null) {
        _log(
          torrentId,
          'StateRecovery returned null — some pieces may need re-download.',
        );
        return;
      }

      final total = result.bitfield.piecesNum;
      final completed = result.bitfield.completedPieces.length;
      _log(
        torrentId,
        'StateRecovery: $completed / $total pieces verified on disk.',
      );

      if (total > 0 && completed >= total) {
        // Every piece is on disk and hash-verified — mark complete
        _log(torrentId, 'All pieces confirmed on disk — marking seeding.');
        await TorrentService.instance.updateTorrentStatus(torrentId, 'seeding');
        TorrentService.instance.invalidateDiskSnapshot(torrentId);
        unawaited(TorrentService.instance.refreshTorrentStates());
        // Cancel fast health check — no longer needed
        _fastHealthCheckTimers.remove(torrentId)?.cancel();
      } else if (total > 0) {
        final missing = total - completed;
        _log(torrentId, '$missing pieces still missing — continuing download.');
      }
    } catch (e, st) {
      _log(torrentId, 'StateRecovery error (non-fatal): $e');
      debugPrint('[StateRecovery] $torrentId: $e\n$st');
    }
  }

  /// Public entry point for the "Verify files" UI button.
  Future<void> forceStateRecovery(String torrentId) async {
    final task = _tasks[torrentId];
    if (task == null) {
      throw StateError(
        'Torrent $torrentId is not currently active. '
        'Resume it first, then verify.',
      );
    }
    await _forceStateRecovery(torrentId, task);
  }

  Future<void> _hardRestartTorrent(String torrentId) async {
    if (_hardRecoveryInFlight.contains(torrentId)) return;

    final restartCount = _hardRestartCounts[torrentId] ?? 0;
    if (restartCount >= 3) {
      _log(
        torrentId,
        'Max hard restarts reached. Marking torrent as error_stalled.',
      );
      await TorrentService.instance.updateTorrentStatus(
        torrentId,
        'error_stalled',
      );
      return;
    }

    final nextAllowed = _nextAllowedHardRestart[torrentId];
    if (nextAllowed != null && DateTime.now().isBefore(nextAllowed)) {
      _log(
        torrentId,
        'Hard restart deferred until $nextAllowed due to backoff.',
      );
      return;
    }

    final backoffMinutes = <int>[0, 10, 30][restartCount];
    _nextAllowedHardRestart[torrentId] = DateTime.now().add(
      Duration(minutes: backoffMinutes),
    );
    _hardRestartCounts[torrentId] = restartCount + 1;

    _hardRecoveryInFlight.add(torrentId);
    try {
      _log(torrentId, 'Hard restart #${restartCount + 1} of 3 starting.');
      final torrent = await TorrentService.instance.getTorrentById(torrentId);
      await stopTorrent(torrentId);
      await Future.delayed(const Duration(seconds: 1));

      final storedDownloadDir = torrent == null
          ? null
          : _storedDownloadDirForResume(torrent);
      final configured = SettingsService.instance.downloadDestination.trim();
      await startTorrent(
        torrentId,
        destinationPath:
            storedDownloadDir ?? (configured.isEmpty ? null : configured),
      );
      _log(torrentId, 'Hard restart complete.');
    } catch (e) {
      _log(torrentId, 'Hard restart failed: $e');
    } finally {
      _hardRecoveryInFlight.remove(torrentId);
    }
  }

  Future<void> _deleteBtStateFiles(
    String directoryPath,
    String torrentId,
  ) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return;
    final hash = torrentId.trim().toLowerCase();
    if (hash.isEmpty) return;

    final candidates = <FileSystemEntity>[];
    await for (final entity in dir.list(recursive: false, followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path).toLowerCase();
      final isState = name == '$hash.bt.state';
      final isBackup =
          name.startsWith('$hash.bt.state.backup.') ||
          name.startsWith('$hash.bt.state.bak');
      if (isState || isBackup) {
        candidates.add(entity);
      }
    }

    for (final entity in candidates) {
      try {
        await entity.delete();
      } catch (_) {
        // Best-effort cleanup only.
      }
    }
  }

  Future<void> _hideBtStateFilesOnWindows(
    String directoryPath, {
    String? torrentId,
  }) async {
    if (!Platform.isWindows) return;

    final dir = Directory(directoryPath);
    if (!await dir.exists()) return;

    final normalizedId = torrentId?.trim().toLowerCase();

    await for (final entity in dir.list(recursive: false, followLinks: false)) {
      if (entity is! File) continue;

      final name = p.basename(entity.path).toLowerCase();
      final isStateFile = name.endsWith('.bt.state');
      final isStateBackup =
          name.contains('.bt.state.backup.') || name.contains('.bt.state.bak');
      if (!isStateFile && !isStateBackup) continue;

      if (normalizedId != null && normalizedId.isNotEmpty) {
        final belongsToTorrent =
            name == '$normalizedId.bt.state' ||
            name.startsWith('$normalizedId.bt.state.backup.') ||
            name.startsWith('$normalizedId.bt.state.bak');
        if (!belongsToTorrent) continue;
      }

      markFileHiddenOnWindows(entity.path);
    }
  }

  String _sanitizePathSegment(String value) {
    return value
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Future<String> _createIsolatedRedownloadDir(
    String baseDir,
    String torrentName,
  ) async {
    final safeName = _sanitizePathSegment(torrentName);
    final suffix = DateTime.now().millisecondsSinceEpoch;
    final folderName = safeName.isEmpty
        ? 'redownload_$suffix'
        : '${safeName}_redownload_$suffix';
    final dir = Directory(p.join(baseDir, folderName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  bool _isPathInside(String candidatePath, String baseDir) {
    final base = p.normalize(p.absolute(baseDir));
    final candidate = p.normalize(p.absolute(candidatePath));
    return candidate == base ||
        candidate.startsWith('$base${Platform.pathSeparator}');
  }

  Future<bool> _deletePathIfExists(String targetPath) async {
    final type = await FileSystemEntity.type(targetPath, followLinks: false);
    if (type == FileSystemEntityType.notFound) return false;
    try {
      if (type == FileSystemEntityType.directory) {
        await Directory(targetPath).delete(recursive: true);
      } else {
        await File(targetPath).delete();
      }
      return true;
    } catch (e) {
      debugPrint('forceRedownload: delete failed for $targetPath: $e');
      return false;
    }
  }

  bool _isFileInUseError(Object error) {
    if (error is PathAccessException) {
      final code = error.osError?.errorCode;
      return code == 32 || code == 33;
    }
    return false;
  }

  Future<bool> _deletePathWithRetry(
    String targetPath, {
    int attempts = 2,
    Duration delay = const Duration(milliseconds: 400),
  }) async {
    final type = await FileSystemEntity.type(targetPath, followLinks: false);
    if (type == FileSystemEntityType.notFound) return true;

    for (var i = 1; i <= attempts; i++) {
      try {
        if (type == FileSystemEntityType.directory) {
          await Directory(targetPath).delete(recursive: true);
        } else {
          await File(targetPath).delete();
        }
        return true;
      } catch (e) {
        final isLocked = _isFileInUseError(e);
        debugPrint(
          'forceRedownload: delete attempt $i/$attempts failed for $targetPath: $e',
        );
        if (!isLocked || i == attempts) {
          return false;
        }
        await Future<void>.delayed(delay);
      }
    }

    return false;
  }

  Future<dt.TorrentModel?> _loadCachedModelForRedownload(
    TorrentModel torrent,
  ) async {
    try {
      final cacheKey = torrent.id.trim().toLowerCase();
      if (cacheKey.isEmpty) return null;
      final cachedMetadata = await dt.MetadataDownloader.loadFromCache(
        cacheKey,
      );
      if (cachedMetadata == null) return null;
      final decoded = decode(cachedMetadata);
      return _parseTorrentModelFromRawBencode(decoded);
    } catch (e) {
      debugPrint('forceRedownload: metadata cache unavailable: $e');
      return null;
    }
  }

  Future<dt.TorrentModel?> _loadModelFromTorrentFileForRedownload(
    TorrentModel torrent,
  ) async {
    try {
      final path = torrent.filePath?.trim() ?? '';
      if (torrent.type != 'torrent_file' || !_isTorrentFilePath(path)) {
        return null;
      }
      return dt.TorrentModel.parse(path);
    } catch (e) {
      debugPrint('forceRedownload: torrent file parse failed: $e');
      return null;
    }
  }

  Set<String> _relativeFilePathsFromModel(dt.TorrentModel model) {
    return model.files
        .map((f) => f.path.replaceAll('\\', '/').trim())
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  Future<Set<String>> _deleteTorrentContentForRedownload(
    TorrentModel torrent,
    String saveDir,
    Set<String> relativePaths,
  ) async {
    var deletedAnything = false;
    final lockedPaths = <String>{};
    var lockFailures = 0;
    const maxLockFailuresBeforeAbort = 3;
    if (relativePaths.isNotEmpty) {
      var ops = 0;
      final roots = <String>{};
      for (final relPath in relativePaths) {
        final relative = relPath.replaceAll('/', Platform.pathSeparator);
        final target = p.normalize(p.join(saveDir, relative));
        if (!_isPathInside(target, saveDir)) continue;

        final targetType = await FileSystemEntity.type(
          target,
          followLinks: false,
        );
        if (targetType == FileSystemEntityType.notFound) {
          ops++;
          continue;
        }

        final didDelete = await _deletePathWithRetry(target);
        if (!didDelete &&
            await FileSystemEntity.type(target) !=
                FileSystemEntityType.notFound) {
          lockedPaths.add(target);
          lockFailures++;
          if (lockFailures >= maxLockFailuresBeforeAbort) {
            debugPrint(
              'forceRedownload: aborting bulk delete early due to repeated file locks. Switching strategy.',
            );
            break;
          }
        }
        deletedAnything = deletedAnything || didDelete;

        final root = relPath.split('/').first;
        if (root.isNotEmpty) roots.add(root);

        ops++;
        if (ops % 20 == 0) {
          await Future<void>.delayed(Duration.zero);
        }
      }

      for (final root in roots) {
        final targetDir = p.normalize(p.join(saveDir, root));
        if (!_isPathInside(targetDir, saveDir)) continue;
        final type = await FileSystemEntity.type(targetDir, followLinks: false);
        if (type == FileSystemEntityType.directory) {
          try {
            final isEmpty = await Directory(targetDir).list().isEmpty;
            if (isEmpty) {
              await Directory(targetDir).delete();
            }
          } catch (_) {
            // Best effort cleanup only.
          }
        }
      }
    }

    if (deletedAnything) return lockedPaths;
    if (relativePaths.isNotEmpty) {
      // We already attempted exact torrent paths. Avoid re-hitting fallback
      // guesses (which can duplicate lock contention on the same file).
      return lockedPaths;
    }

    // Fallback when cached metadata is unavailable: remove common root targets.
    final safeName = _sanitizePathSegment(torrent.name);
    if (safeName.isEmpty) return lockedPaths;

    final fallbackTargets = <String>{
      p.join(saveDir, safeName),
      p.join(saveDir, '$safeName.mkv'),
      p.join(saveDir, '$safeName.exe'),
      p.join(saveDir, '$safeName.mp4'),
    };

    for (final target in fallbackTargets) {
      if (!_isPathInside(target, saveDir)) continue;
      final didDelete = await _deletePathWithRetry(target);
      if (!didDelete &&
          await FileSystemEntity.type(target) !=
              FileSystemEntityType.notFound) {
        lockedPaths.add(target);
      }
    }

    return lockedPaths;
  }

  Future<void> forceRedownload(String torrentId) async {
    if (_forceRedownloadInFlight.contains(torrentId)) {
      debugPrint(
        'forceRedownload: request ignored because another force-redownload is already running for $torrentId',
      );
      return;
    }
    _forceRedownloadInFlight.add(torrentId);
    try {
      final runningModel = _tasks[torrentId]?.metaInfo;
      await stopTorrent(torrentId);
      await Future.delayed(const Duration(milliseconds: 200));

      final torrent = await TorrentService.instance.getTorrentById(torrentId);
      if (torrent == null) throw StateError('Torrent not found: $torrentId');

      final filePath = torrent.filePath?.trim() ?? '';
      final configuredDir = SettingsService.instance.downloadDestination.trim();
      final preferredPath = configuredDir.isNotEmpty
          ? configuredDir
          : (filePath.isNotEmpty && !_isTorrentFilePath(filePath)
                ? filePath
                : null);
      final saveDir = await _resolveWritableDownloadDir(preferredPath);

      // Reset visible state immediately so UI drops to 0% without waiting for disk cleanup.
      await TorrentService.instance.updateTorrent(
        torrent.copyWith(
          status: 'downloading',
          bytesDown: 0,
          bytesUp: 0,
          completedAt: null,
          seeders: 0,
          leechers: 0,
          filePath: saveDir,
        ),
      );
      TorrentService.instance.invalidateDiskSnapshot(torrentId);
      unawaited(TorrentService.instance.refreshTorrentStates());

      await _deleteBtStateFiles(saveDir, torrentId);
      if (configuredDir.isNotEmpty && configuredDir != saveDir) {
        await _deleteBtStateFiles(configuredDir, torrentId);
      }

      final relativePaths = <String>{};
      if (runningModel != null) {
        relativePaths.addAll(_relativeFilePathsFromModel(runningModel));
      }

      if (relativePaths.isEmpty) {
        final fileModel = await _loadModelFromTorrentFileForRedownload(torrent);
        if (fileModel != null) {
          relativePaths.addAll(_relativeFilePathsFromModel(fileModel));
        }
      }

      if (relativePaths.isEmpty) {
        final cachedModel = await _loadCachedModelForRedownload(torrent);
        if (cachedModel != null) {
          relativePaths.addAll(_relativeFilePathsFromModel(cachedModel));
        }
      }

      final lockedPaths = await _deleteTorrentContentForRedownload(
        torrent,
        saveDir,
        relativePaths,
      );

      if (lockedPaths.isNotEmpty) {
        final sample = lockedPaths.take(3).join(', ');
        debugPrint(
          'forceRedownload: files are locked, switching to isolated redownload dir. Files: $sample',
        );

        final isolatedDir = await _createIsolatedRedownloadDir(
          saveDir,
          torrent.name,
        );
        await TorrentService.instance.updateTorrent(
          torrent.copyWith(
            status: 'downloading',
            bytesDown: 0,
            bytesUp: 0,
            completedAt: null,
            seeders: 0,
            leechers: 0,
            filePath: isolatedDir,
          ),
        );
        TorrentService.instance.invalidateDiskSnapshot(torrentId);
        unawaited(TorrentService.instance.refreshTorrentStates());

        await startTorrent(torrentId, destinationPath: isolatedDir);
        return;
      }

      await startTorrent(torrentId, destinationPath: saveDir);
    } finally {
      _forceRedownloadInFlight.remove(torrentId);
    }
  }

  void _cleanup(String torrentId) {
    _pollTimers.remove(torrentId)?.cancel();
    _scrapeTimers.remove(torrentId)?.cancel();
    _healthCheckTimers.remove(torrentId)?.cancel();
    _fastHealthCheckTimers.remove(torrentId)?.cancel();
    _progressTimers.remove(torrentId)?.cancel();
    _uploadedBytesByTorrent.remove(torrentId);
    _lastUploadedSampleByTorrent.remove(torrentId);
    _zeroProgressCounters.remove(torrentId);
    _peerlessCounters.remove(torrentId);
    _stallRecoveryCycles.remove(torrentId);
    _hardRecoveryInFlight.remove(torrentId);
    _scrapedSeedersByTorrent.remove(torrentId);
    _scrapedLeechersByTorrent.remove(torrentId);
    _lastReportedProgressByTorrent.remove(torrentId);
    _lastProgressChangeAtByTorrent.remove(torrentId);
    _lastRefreshAtByTorrent.remove(torrentId);
    _refreshInFlight.remove(torrentId);
    _lastDownloadedByTorrent.remove(torrentId);
    _stagnantDownloadIntervals.remove(torrentId);
    _tasks.remove(torrentId);
  }

  Future<void> stopTorrent(String torrentId) async {
    final task = _tasks[torrentId];
    if (task != null) {
      try {
        await task.stop();
      } catch (e) {
        debugPrint('stopTorrent: task stop failed (non-fatal): $e');
      }
    }
    _cleanup(torrentId);
    try {
      await TorrentService.instance.updateTorrentStatus(torrentId, 'paused');
    } catch (e) {
      debugPrint('stopTorrent: status update failed (non-fatal): $e');
    }
  }

  void pauseTorrent(String torrentId) {
    _tasks[torrentId]?.pause();
    unawaited(
      TorrentService.instance
          .updateTorrentStatus(torrentId, 'paused')
          .catchError(
            (Object e) => debugPrint('pauseTorrent status write failed: $e'),
          ),
    );
  }

  void resumeTorrent(String torrentId) {
    final task = _tasks[torrentId];
    task?.resume();
    final status = task != null && _isTaskComplete(task)
        ? 'seeding'
        : 'downloading';
    unawaited(
      TorrentService.instance
          .updateTorrentStatus(torrentId, status)
          .catchError(
            (Object e) => debugPrint('resumeTorrent status write failed: $e'),
          ),
    );
  }

  bool _isTorrentFilePath(String? path) {
    if (path == null) return false;
    final normalized = path.trim().toLowerCase();
    return normalized.isNotEmpty && normalized.endsWith('.torrent');
  }

  void _forceAllFilesNormalPriority(dt.TorrentTask task) {
    try {
      final files = task.metaInfo.files;
      if (files.isEmpty) return;
      final priorities = <int, dt.FilePriority>{
        for (var i = 0; i < files.length; i++) i: dt.FilePriority.normal,
      };
      task.setFilePriorities(priorities);
    } catch (e) {
      debugPrint('Could not normalize file priorities (non-fatal): $e');
    }
  }

  String? _storedDownloadDirForResume(TorrentModel torrent) {
    final path = torrent.filePath?.trim();
    if (path == null || path.isEmpty) return null;
    if (_isTorrentFilePath(path)) return null;
    return path;
  }

  bool _isTaskComplete(dt.TorrentTask task) {
    if (_hasAllPiecesComplete(task)) {
      return true;
    }

    try {
      final dynamicTask = task as dynamic;
      final isAllComplete = dynamicTask.fileManager?.isAllComplete as bool?;
      if (isAllComplete == true) return true;
    } catch (_) {
      // Fallback to downloaded/progress checks below.
    }

    final totalLength = task.metaInfo.length ?? task.metaInfo.totalSize;
    final downloaded = task.downloaded ?? 0;
    if (totalLength > 0 &&
        downloaded >= totalLength &&
        task.progress >= 0.999) {
      return true;
    }
    return false;
  }

  void _ensureTaskRunningMode(dt.TorrentTask task) {
    if (_isTaskComplete(task)) {
      return;
    }
    try {
      (task as dynamic).download();
    } catch (_) {
      // Older API surfaces may not expose download().
    }
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

    // Aggregate stats across all tasks
    int totalDownloaded = 0;
    int totalUploaded = 0;
    double totalProgress = 0.0;
    int totalPeers = 0;
    int totalDhtNodes = 0;
    int totalTrackers = 0;
    double totalDownloadSpeed = 0.0;
    double totalUploadSpeed = 0.0;
    int taskCount = _tasks.length;

    String title = '';
    String state = 'downloading';

    for (final entry in _tasks.entries) {
      final torrentId = entry.key;
      final task = entry.value;
      final downloaded = task.downloaded ?? 0;
      final uploaded = _uploadedBytesByTorrent[torrentId] ?? 0;
      final progress = task.progress;
      final peers = task.connectedPeersNumber;
      final dlSpeed = task.currentDownloadSpeed * 1000;
      final ulSpeed = task.uploadSpeed * 1000;

      totalDownloaded += downloaded;
      totalUploaded += uploaded;
      totalProgress += progress;
      totalPeers += peers;
      totalDownloadSpeed += dlSpeed;
      totalUploadSpeed += ulSpeed;

      try {
        final dynamic t = task;
        final dhtNodes = (t.dhtNodeCount as int?) ?? 0;
        totalDhtNodes += dhtNodes;
      } catch (_) {
        // ignore if not available
      }

      try {
        final dynamic t = task;
        final trackers = (t.trackerPeersNumber as int?) ?? 0;
        totalTrackers += trackers;
      } catch (_) {
        // ignore if not available
      }

      // Use first task name for title
      if (title.isEmpty) {
        title = task.metaInfo.name;
      }
    }

    final avgProgress = taskCount > 0 ? totalProgress / taskCount : 0.0;

    return TorrentEngineStatus(
      torrentId: title,
      downloaded: totalDownloaded,
      uploaded: totalUploaded,
      progress: avgProgress,
      state: state,
      peers: totalPeers,
      dhtNodes: totalDhtNodes,
      trackers: totalTrackers,
      downloadSpeed: totalDownloadSpeed,
      uploadSpeed: totalUploadSpeed,
    );
  }

  bool shouldStopService() => _tasks.isEmpty;

  Future<void> stopAll() async {
    final ids = _tasks.keys.toList();
    for (final id in ids) {
      await stopTorrent(id);
    }
  }

  Future<String> _defaultDownloadDir() async {
    final configured = SettingsService.instance.downloadDestination.trim();
    if (configured.isNotEmpty) {
      final configuredDir = Directory(configured);
      if (!await configuredDir.exists()) {
        await configuredDir.create(recursive: true);
      }
      return configuredDir.path;
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(
      '${docs.path}${Platform.pathSeparator}TorrentSpireAI',
    );
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  String _augmentMagnetWithFallbackTrackers(String magnetLink) {
    try {
      final uri = Uri.parse(magnetLink);
      if (uri.scheme.toLowerCase() != 'magnet') return magnetLink;

      final params = Map<String, List<String>>.from(uri.queryParametersAll);
      final existing = <String>{...(params['tr'] ?? const <String>[])};
      for (final tracker in _fallbackTrackers) {
        if (existing.add(tracker)) {
          params.putIfAbsent('tr', () => <String>[]).add(tracker);
        }
      }

      return uri.replace(queryParameters: params).toString();
    } catch (_) {
      return magnetLink;
    }
  }

  Future<String> _resolveWritableDownloadDir(String? preferredPath) async {
    final candidates = <String>[];
    if (preferredPath != null && preferredPath.trim().isNotEmpty) {
      candidates.add(preferredPath.trim());
    }

    final configured = SettingsService.instance.downloadDestination.trim();
    if (configured.isNotEmpty && !candidates.contains(configured)) {
      candidates.add(configured);
    }

    final docs = await getApplicationDocumentsDirectory();
    final appPrivate = '${docs.path}${Platform.pathSeparator}TorrentSpireAI';
    if (!candidates.contains(appPrivate)) {
      candidates.add(appPrivate);
    }

    for (final path in candidates) {
      if (await _canWriteToDirectory(path)) {
        if (Platform.isAndroid &&
            preferredPath != null &&
            preferredPath.trim().isNotEmpty &&
            path != preferredPath.trim()) {
          debugPrint(
            '[Android] Download path "$preferredPath" is not writable. Falling back to "$path".',
          );
        }
        if (Platform.isAndroid &&
            SettingsService.instance.downloadDestination.trim() != path) {
          await SettingsService.instance.setDownloadDestination(path);
        }
        return path;
      }
    }

    // Last-resort fallback should always be app-private docs.
    final fallback = Directory(appPrivate);
    if (!await fallback.exists()) {
      await fallback.create(recursive: true);
    }
    if (Platform.isAndroid) {
      debugPrint(
        '[Android] All configured download paths failed write test. Using app-private "$fallback".',
      );
      await SettingsService.instance.setDownloadDestination(fallback.path);
    }
    return fallback.path;
  }

  Future<bool> _canWriteToDirectory(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final probe = File(
        '${dir.path}${Platform.pathSeparator}.vts_write_probe_${DateTime.now().microsecondsSinceEpoch}',
      );
      await probe.writeAsString('ok', flush: true);
      if (await probe.exists()) {
        await probe.delete();
      }
      return true;
    } catch (e) {
      return false;
    }
  }
}
