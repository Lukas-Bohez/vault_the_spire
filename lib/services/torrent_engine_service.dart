import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart' as dt;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:vault_the_spire/models/torrent.dart';
import 'package:vault_the_spire/services/notification_service.dart';
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

  final Map<String, dt.TorrentTask> _tasks = {};
  final Map<String, Timer> _pollTimers = {};
  final Map<String, Timer> _scrapeTimers = {};
  final Map<String, Timer> _healthCheckTimers = {};
  final Map<String, int> _peerlessCounters = {};
  final Map<String, List<Uri>> _torrentTrackers = {};
  final Map<String, List<String>> _connectionLogs = {};
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
    debugPrint('Initializing default DHT bootstrap nodes');
    for (final node in _defaultDhtBootstrapNodes) {
      debugPrint('DHT bootstrap candidate: $node');
    }
    _detectRestrictedNetwork();
  }

  Future<void> _detectRestrictedNetwork() async {
    final host = '1.1.1.1';
    final blockedPorts = <int>[];
    for (var port = 6881; port <= 6889; port++) {
      try {
        final s = await Socket.connect(
          host,
          port,
          timeout: const Duration(seconds: 3),
        );
        s.destroy();
      } catch (_) {
        blockedPorts.add(port);
      }
    }
    if (blockedPorts.length >= 7) {
      _defaultPortsBlocked = true;
      debugPrint(
        'Network restriction detected: default bittorrent ports 6881-6889 may be blocked or filtered',
      );
    } else {
      _defaultPortsBlocked = false;
      debugPrint('Port probe done; blocked ports: $blockedPorts');
    }
  }

  void _log(String torrentId, String message) {
    _connectionLogs
        .putIfAbsent(torrentId, () => [])
        .add('[${DateTime.now().toIso8601String()}] $message');
  }


  List<String> getLogs(String torrentId) {
    return List.unmodifiable(_connectionLogs[torrentId] ?? []);
  }

  void clearLogs(String torrentId) {
    _connectionLogs[torrentId]?.clear();
  }

  Future<void> _configureTask(dt.TorrentTask task) async {
    try {
      (task as dynamic).setDHTEnabled(true);
      debugPrint('Enabled DHT for torrent task');
    } catch (e, st) {
      debugPrint('Failed to setDHTEnabled: $e');
      debugPrint(st.toString());
    }
    try {
      (task as dynamic).setPEXEnabled(true);
      debugPrint('Enabled PEX for torrent task');
    } catch (e, st) {
      debugPrint('Failed to setPEXEnabled: $e');
      debugPrint(st.toString());
    }
    try {
      (task as dynamic).setTrackerEnabled(true);
      debugPrint('Enabled tracker support for torrent task');
    } catch (e, st) {
      debugPrint('Failed to setTrackerEnabled: $e');
      debugPrint(st.toString());
    }

    await _mapPorts(task);
    _addDhtBootstrapNodes(task);
  }

  Future<void> _mapPorts(dt.TorrentTask task) async {
    final random = Random.secure();
    final initialPort = _defaultPortsBlocked ? 0 : 6881;

    final candidatePorts = <int>[];
    if (initialPort > 0) {
      candidatePorts.add(initialPort);
    }
    while (candidatePorts.length < 5) {
      candidatePorts.add(49152 + random.nextInt(65535 - 49152));
    }

    bool bound = false;
    for (final candidate in candidatePorts) {
      try {
        (task as dynamic).setPort(candidate);
        if ((task as dynamic).enableUPnP != null) {
          (task as dynamic).enableUPnP(true);
        }
        if ((task as dynamic).enableNATPMP != null) {
          (task as dynamic).enableNATPMP(true);
        }
        debugPrint('Attempted port mapping on port $candidate (UPnP/NAT-PMP)');
        bound = true;
        break;
      } catch (e) {
        if (e is SocketException) {
          debugPrint(
            'Port binding failed on $candidate: $e. Retrying with port 0.',
          );
          try {
            (task as dynamic).setPort(0);
            debugPrint('Successfully rebound to random port (0).');
            bound = true;
            break;
          } catch (e2) {
            debugPrint('Failed to bind to random port: $e2');
          }
        } else {
          debugPrint('Port mapping attempt failed on port $candidate: $e');
        }
        continue;
      }
    }
    if (!bound) {
      try {
        (task as dynamic).setPort(0);
        debugPrint('Fallback: Successfully bound to random port (0).');
      } catch (e) {
        debugPrint('Fallback: Failed to bind to random port: $e');
      }
    }
  }

  void _addDhtBootstrapNodes(dt.TorrentTask task) {
    for (final endpoint in _defaultDhtBootstrapNodes) {
      final parts = endpoint.split(':');
      if (parts.length != 2) continue;
      final host = parts[0];
      final port = int.tryParse(parts[1]);
      if (port == null) continue;
      try {
        // dtorrent_task_v2 DHT API might support a simple addDHTNode method.
        (task as dynamic).addDHTNode(host, port);
        debugPrint('Added DHT bootstrap node $host:$port');
      } catch (e, st) {
        debugPrint('Failed to add DHT bootstrap node $host:$port: $e');
        debugPrint(st.toString());
      }
    }
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
        debugPrint('Announce URL success ($attempt): $url');
        return;
      } catch (e, st) {
        final msg = 'Announce URL attempt $attempt failed: $url $e';
        debugPrint(msg);
        final taskId = taskIdFromTask(task);
        if (taskId.isNotEmpty) _log(taskId, msg);
        debugPrint(st.toString());
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

  Future<void> _refreshConnection(String torrentId, dt.TorrentTask task) async {
    debugPrint(
      'Refreshing connection for $torrentId: reannounce trackers and DHT bootstrap',
    );
    _log(torrentId, 'Triggered force refresh.');

    final trackers = _torrentTrackers[torrentId] ?? [];
    final infoHash = (task as dynamic).metaInfo?.infoHash as Uint8List?;

    if (infoHash != null) {
      for (final url in trackers) {
        try {
          await _announceUrlWithRetry(task, url, infoHash);
        } catch (e) {
          debugPrint('Re-announce tracker failed for $url: $e');
        }
      }
    }

    _addDhtBootstrapNodes(task);
    try {
      for (final node in (task as dynamic).metaInfo?.nodes ?? []) {
        if (node is Map && node['host'] != null && node['port'] != null) {
          (task as dynamic).addDHTNode(node['host'], node['port']);
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
      final peers = task.connectedPeersNumber;
      if (peers == 0) {
        _peerlessCounters[torrentId] = (_peerlessCounters[torrentId] ?? 0) + 1;
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

    // Set listening port and NAT traversal hints (UPnP/NAT-PMP)
    try {
      (task as dynamic).setPort(6881);
      (task as dynamic).enableUPnP(true);
      (task as dynamic).enableNATPMP(true);
      debugPrint('Port/NAT configuration applied (6881/UPnP/NAT-PMP)');
    } catch (e, st) {
      debugPrint('Port/NAT config error: $e');
      debugPrint(st.toString());
    }

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
          debugPrint('Metadata download decoded type: ${msg.runtimeType}');
          if (msg is Map) {
            debugPrint('Metadata keys: ${msg.keys}');
            final rawName = msg['name'];
            debugPrint('Top-level name type: ${rawName?.runtimeType}, isUint8List=${rawName is Uint8List}');
            final rawPieces = msg['pieces'];
            debugPrint('Top-level pieces type: ${rawPieces?.runtimeType}, isUint8List=${rawPieces is Uint8List}');
            if (rawName is Uint8List) {
              try {
                debugPrint('Top-level name decoded: ${utf8.decode(rawName)}');
              } catch (_) {
                debugPrint('Top-level name could not decode to UTF-8');
              }
            }
            if (msg.containsKey('info')) {
              final info = msg['info'];
              debugPrint('info type: ${info?.runtimeType}');
              if (info is Map) {
                final infoName = info['name'];
                debugPrint('info.name type: ${infoName?.runtimeType}, isUint8List=${infoName is Uint8List}');
                if (infoName is Uint8List) {
                  try {
                    debugPrint('info.name decoded: ${utf8.decode(infoName)}');
                  } catch (_) {}
                }
              }
            }
          }

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

    // Set listening port and NAT traversal hints (UPnP/NAT-PMP)
    try {
      (task as dynamic).setPort(6881);
      (task as dynamic).enableUPnP(true);
      (task as dynamic).enableNATPMP(true);
      debugPrint('Port/NAT configuration applied (6881/UPnP/NAT-PMP)');
    } catch (e, st) {
      debugPrint('Port/NAT config error: $e');
      debugPrint(st.toString());
    }

    await task.start();

    // Announce to all trackers from magnet, parsed model, and fallback list
    final infoHash = dtModel.infoHashBuffer;
    final seenUrls = <String>{};
    for (final url in [...magnet.trackers, ...dtModel.announces]) {
      if (seenUrls.add(url.toString())) {
        try {
          await _announceUrlWithRetry(
            task,
            Uri.parse(url.toString()),
            infoHash,
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
          await _announceUrlWithRetry(task, Uri.parse(url), infoHash);
        } catch (e) {
          debugPrint('Fallback tracker error: $url $e');
        }
      }
    }

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
    debugPrint('Normalized info types:');
    final pieceType = normalizedInfo['pieces']?.runtimeType;
    debugPrint(' - pieces type: $pieceType');
    final filesType = normalizedInfo['files']?.runtimeType;
    debugPrint(' - files type: $filesType');

    final torrentMap = <String, dynamic>{
      'info': normalizedInfo,
    };

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
      final nameParts = nameValue
          .where((e) => e != null)
          .map((e) {
            if (e is String) return e;
            if (e is Uint8List) {
              try {
                return utf8.decode(e);
              } catch (_) {
                return e.toString();
              }
            }
            return e.toString();
          })
          .toList();
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
          final key = entry.key is String ? entry.key as String : entry.key.toString();
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
          await NotificationService.instance
              .showDownloadComplete(torrent.name);
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
      connectionMsg = 'Searching for DHT nodes...';
    } else {
      connectionMsg = 'Trackers timed out (Check VPN/Firewall)';
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
    final dir = Directory('${docs.path}${Platform.pathSeparator}VaultTheSpire');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }
}
