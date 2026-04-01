import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:bittorrent_dht/bittorrent_dht.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart' as dt;
import 'package:flutter/foundation.dart';
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
  ];

  final Map<String, dt.TorrentTask> _tasks = {};
  final Map<String, Timer> _pollTimers = {};
  final Map<String, Timer> _scrapeTimers = {};
  final Map<String, Timer> _healthCheckTimers = {};
  final Map<String, Timer> _progressTimers = {};
  final Map<String, int> _peerlessCounters = {};
  final Map<String, List<Uri>> _torrentTrackers = {};
  final Map<String, List<String>> _connectionLogs = {};
  final Map<String, DateTime> _lastProgressLogTimes = {};
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
    _connectionLogs
        .putIfAbsent(torrentId, () => [])
        .add('[${DateTime.now().toIso8601String()}] $message');
  }

  void _logPeerEventThrottled(String label, dt.TorrentTask task) {
    _peerEventsSinceLastLog++;
    final now = DateTime.now();
    if (now.difference(_lastPeerLogTime).inSeconds >= 10) {
      final peers = task.connectedPeersNumber;
      debugPrint(
        '[TorrentEngine] $label | peers: $peers | '
        'events last 10s: $_peerEventsSinceLastLog',
      );
      _peerEventsSinceLastLog = 0;
      _lastPeerLogTime = now;
    }
  }

  void _logDhtThrottled(dt.TorrentTask task) {
    _dhtNodesSinceLastLog++;
    final now = DateTime.now();
    if (now.difference(_lastDhtLogTime).inSeconds >= 10) {
      int routingSize = 0;
      try {
        routingSize = ((task as dynamic).dhtNodeCount as int?) ?? 0;
      } catch (_) {
        routingSize = 0;
      }
      debugPrint(
        '[DHT] nodes seen last 10s: $_dhtNodesSinceLastLog | '
        'routing table size: $routingSize',
      );
      _dhtNodesSinceLastLog = 0;
      _lastDhtLogTime = now;
    }
  }

  void _logProgressThrottled(String torrentId, dt.TorrentTask task) {
    final now = DateTime.now();
    final last = _lastProgressLogTimes[torrentId] ??
        DateTime.fromMillisecondsSinceEpoch(0);
    if (now.difference(last).inSeconds >= 5) {
      final dynamic t = task;
      final downloaded = (t.downloaded as int?) ?? 0;
      final total = (t.metaInfo?.length as int?) ?? 0;
      final speed = ((t.currentDownloadSpeed as num?) ?? 0).toDouble() / 1024;
      final peers = (t.connectedPeersNumber as int?) ?? 0;
      final pct = total > 0 ? (downloaded / total * 100).toStringAsFixed(1) : '0.0';
      debugPrint(
        '[Download] $torrentId | $pct% | '
        'speed: ${speed.toStringAsFixed(0)} KB/s | peers: $peers',
      );
      _lastProgressLogTimes[torrentId] = now;
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

  void _announceTrackers(
    String torrentId,
    dt.TorrentTask task,
  ) {
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

          // Announce to all trackers
          for (final trackerUri in trackers) {
            try {
              await _announceUrlWithRetry(task, trackerUri, infoHash);
            } catch (e) {
              _log(torrentId, 'Tracker announce failed for $trackerUri: $e');
            }
          }
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
      _log(torrentId, 'Successfully announced to $trackerSuccesses tracker(s).');
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

  void _startHealthCheckTimer(String torrentId, dt.TorrentTask task) {
    _healthCheckTimers[torrentId]?.cancel();
    _peerlessCounters[torrentId] = 0;

    _healthCheckTimers[torrentId] = Timer.periodic(const Duration(seconds: 30), (
      timer,
    ) async {
      try {
        final peers = task.connectedPeersNumber;
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
          if (_peerlessCounters[torrentId]! >= 4) {
            _peerlessCounters[torrentId] = 0;
            await _refreshConnection(torrentId, task);
          }
        } else {
          if ((_peerlessCounters[torrentId] ?? 0) > 0) {
            _log(torrentId, 'Peers returned at $peers connections');
          }
          _peerlessCounters[torrentId] = 0;
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
    await _refreshConnection(torrentId, task);
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

  Future<void> _startFromFile(
    TorrentModel torrent, {
    String? destinationPath,
  }) async {
    final dtModel = await dt.TorrentModel.parse(torrent.filePath!);
    final saveDir = destinationPath?.trim().isNotEmpty == true
        ? destinationPath!
        : await _defaultDownloadDir();

    if (!Directory(saveDir).existsSync()) {
      await Directory(saveDir).create(recursive: true);
    }

    final totalBytes = dtModel.files.fold<int>(0, (s, f) => s + f.length);
    if (totalBytes > 0 && (torrent.totalSize ?? 0) != totalBytes) {
      await TorrentService.instance.updateTorrent(
        torrent.copyWith(totalSize: totalBytes),
      );
    }

    // Aggressive peer connectivity: enable DHT, PEX, and use fallback trackers
    final task = dt.TorrentTask.newTask(dtModel, saveDir);
    _tasks[torrent.id] = task;
    _wireEvents(torrent.id, task);
    await _configureTask(task);
    _torrentTrackers[torrent.id] = dtModel.announces
        .map<Uri>((u) => Uri.parse(u.toString()))
        .toList();
    _startHealthCheckTimer(torrent.id, task);

    // Task configuration (port/NAT) already applied in _configureTask.
    await task.start();

    // Use all announce URLs and fallback public trackers
    final seenUrls = <String>{};
    for (final url in dtModel.announces) {
      if (seenUrls.add(url.toString())) {
        try {
          await _announceUrlWithRetry(
            task,
            Uri.parse(url.toString()),
            dtModel.infoHashBuffer,
          );
        } catch (e) {
          debugPrint('Tracker announce error: $url $e');
        }
      }
    }
    // Fallback public trackers
    const fallbackTrackers = [
      'udp://tracker.openbittorrent.com:80/announce',
      'udp://tracker.opentrackr.org:1337/announce',
      'udp://tracker.coppersurfer.tk:6969/announce',
      'udp://tracker.leechers-paradise.org:6969/announce',
      'udp://tracker.internetwarriors.net:1337/announce',
      'udp://exodus.desync.com:6969/announce',
      'http://tracker.openbittorrent.com:80/announce',
      'http://tracker.opentrackr.org:1337/announce',
    ];
    for (final url in fallbackTrackers) {
      if (seenUrls.add(url)) {
        try {
          await _announceUrlWithRetry(
            task,
            Uri.parse(url),
            dtModel.infoHashBuffer,
          );
        } catch (e) {
          debugPrint('Fallback tracker error: $url $e');
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

    await TorrentService.instance.updateTorrentStatus(
      torrent.id,
      'downloading',
    );
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

    var dtModel = await completer.future.timeout(
      const Duration(minutes: 3),
      onTimeout: () =>
          throw TimeoutException('Metadata timed out for ${torrent.id}'),
    );

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

    final saveDir = destinationPath?.trim().isNotEmpty == true
        ? destinationPath!
        : await _defaultDownloadDir();

    if (!Directory(saveDir).existsSync()) {
      await Directory(saveDir).create(recursive: true);
    }

    final totalBytes = dtModel.files.fold<int>(0, (s, f) => s + f.length);
    if (totalBytes > 0) {
      await TorrentService.instance.updateTorrent(
        torrent.copyWith(totalSize: totalBytes),
      );
    }

    // Aggressive peer connectivity: enable DHT, PEX, and use fallback trackers
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
    await _configureTask(task);
    _torrentTrackers[torrent.id] = [
      ...magnet.trackers
          .map<Uri>((s) => Uri.parse(s.toString()))
          .where((u) => u.toString().isNotEmpty),
      ...dtModel.announces.map<Uri>((u) => Uri.parse(u.toString())),
    ];
    _startHealthCheckTimer(torrent.id, task);

    // Start task in background without blocking UI
    try {
      await task.start();
    } catch (_) {
      _cleanup(torrent.id);
      rethrow;
    }

    try {
      (task as dynamic).resume();
    } catch (_) {}
    try {
      (task as dynamic).unpause();
    } catch (_) {}
    try {
      (task as dynamic).download();
    } catch (_) {}

    _progressTimers[torrent.id]?.cancel();
    _progressTimers[torrent.id] = Timer.periodic(const Duration(seconds: 5), (_) {
      _logProgressThrottled(torrent.id, task);
    });

    // Set up DHT event listeners
    final dht = task.dht;
    if (dht != null) {
      dht.createListener()?..on<NewPeerEvent>((event) {
        _logDhtThrottled(task);
        try {
          task.addPeer(event.address, dt.PeerSource.dht, type: dt.PeerType.TCP);
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

    // Announce to trackers in background without blocking UI
    _announceTrackers(torrent.id, task);

    // Hand off peers from metadata fetch so download starts immediately.
    for (final peer in downloader.activePeers) {
      try {
        task.addPeer(peer.address, dt.PeerSource.manual, type: peer.type);
      } catch (e, st) {
        debugPrint('Peer add error: ${peer.address} $e');
        debugPrint(st.toString());
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

    await TorrentService.instance.updateTorrentStatus(
      torrent.id,
      'downloading',
    );
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
    final nameValue = info['name'];
    if (nameValue is List) {
      final nameParts = nameValue.where((e) => e != null).map((e) {
        if (e is String) return e;
        if (e is Uint8List) {
          try {
            return utf8.decode(e);
          } catch (_) {
            return e.toString();
          }
        }
        return e.toString();
      }).toList();
      info['name'] = nameParts.join('/');
    } else if (nameValue is Uint8List) {
      try {
        info['name'] = utf8.decode(nameValue);
      } catch (_) {
        info['name'] = nameValue.toString();
      }
    }
  }

  void _ensureAnnounceFieldsAreString(Map<String, dynamic> info) {
    if (info['announce'] is Uint8List) {
      try {
        info['announce'] = utf8.decode(info['announce'] as Uint8List);
      } catch (_) {}
    }

    if (info['announce-list'] is List) {
      info['announce-list'] = (info['announce-list'] as List).map((tier) {
        if (tier is List) {
          return tier.map((url) {
            if (url is Uint8List) {
              try {
                return utf8.decode(url);
              } catch (_) {
                return url.toString();
              }
            }
            return url;
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
              if (component is Uint8List) {
                try {
                  return utf8.decode(component);
                } catch (_) {
                  return component.toString();
                }
              }
              return component;
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
      final key = entry.key is String
          ? entry.key as String
          : entry.key is Uint8List
          ? utf8.decode(entry.key as Uint8List)
          : entry.key.toString();
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
          final key = entry.key is String
              ? entry.key as String
              : entry.key.toString();
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

  void _wireEvents(String torrentId, dt.TorrentTask task) {
    task.createListener()
      ..on<dt.StateFileUpdated>((_) {
        _emitStats(torrentId, task, 'downloading');
      })
      ..on<dt.TaskCompleted>((_) async {
        _emitStats(torrentId, task, 'completed');
        await TorrentService.instance.updateTorrentStatus(
          torrentId,
          'completed',
        );
        final torrent = await TorrentService.instance.getTorrentById(torrentId);
        if (torrent != null) {
          await NotificationService.instance.showDownloadComplete(torrent.name);
        }
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
      connectionMsg = 'No DHT nodes found — Check firewall/network or try later';
    } else if (trackers == 0) {
      connectionMsg = 'DHT active but no trackers responding — Try force refresh';
    } else {
      connectionMsg = 'Trackers responding but no peers found — Torrent may be dead';
    }

    _statusController.add(
      TorrentEngineStatus(
        torrentId: torrentId,
        downloaded: downloaded,
        uploaded: 0,
        progress: progress,
        state: state,
        peers: peers,
        dhtNodes: dhtNodes,
        trackers: trackers,
        seeders: seeders,
        leechers: leechers,
        downloadSpeed: dlSpeed,
        uploadSpeed: ulSpeed,
        statusMessage: msg,
        connectionMessage: connectionMsg,
      ),
    );

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
      final stats = result.getStatsForInfoHash(task.metaInfo.infoHash);
      if (stats == null) return;
      final existing = await TorrentService.instance.getTorrentById(torrentId);
      if (existing == null) return;
      await TorrentService.instance.updateTorrent(
        existing.copyWith(seeders: stats.complete, leechers: stats.incomplete),
      );
    } catch (_) {
      // Best-effort — scrape must never crash the engine.
    }
  }

  void _cleanup(String torrentId) {
    _pollTimers.remove(torrentId)?.cancel();
    _scrapeTimers.remove(torrentId)?.cancel();
    _healthCheckTimers.remove(torrentId)?.cancel();
    _progressTimers.remove(torrentId)?.cancel();
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
    final configured = SettingsService.instance.downloadDestination.trim();
    if (configured.isNotEmpty) {
      final configuredDir = Directory(configured);
      if (!await configuredDir.exists()) {
        await configuredDir.create(recursive: true);
      }
      return configuredDir.path;
    }
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}${Platform.pathSeparator}TorrentSpireAI');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }
}
