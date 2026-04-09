import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:vault_the_spire/bittorrent/bencode.dart';
import 'package:vault_the_spire/bittorrent/magnet_link.dart';
import 'package:vault_the_spire/bittorrent/torrent_file.dart';
import 'package:vault_the_spire/db/torrents_dao.dart';
import 'package:vault_the_spire/models/torrent.dart';
import 'package:vault_the_spire/services/settings_service.dart';
import 'package:vault_the_spire/services/torrent_engine_service.dart';

class TorrentAlreadyExistsException implements Exception {
  final String torrentId;
  TorrentAlreadyExistsException(this.torrentId);

  @override
  String toString() => 'Torrent already exists: $torrentId';
}

enum MagnetAddOutcome { started, queued, pendingMetadata }

const double displayCompleteProgressThreshold = 0.9989;

double normalizeTorrentProgressForDisplay(double progress) {
  final clamped = progress.clamp(0.0, 1.0);
  if (clamped >= displayCompleteProgressThreshold) return 1.0;
  return clamped;
}

class TorrentViewState {
  final TorrentModel model;
  final int downloaded;
  final int uploaded;
  final double progress;
  final String state;
  final String statusLabel;
  final String statusMessage;
  final String connectionMessage;
  final int peers;
  final int seeders;
  final int leechers;
  final int dhtNodes;
  final int trackers;
  final double downloadSpeed;
  final double uploadSpeed;
  final bool isComplete;
  final bool isCompleteOnDisk;

  const TorrentViewState({
    required this.model,
    required this.downloaded,
    required this.uploaded,
    required this.progress,
    required this.state,
    required this.statusLabel,
    required this.statusMessage,
    required this.connectionMessage,
    required this.peers,
    required this.seeders,
    required this.leechers,
    required this.dhtNodes,
    required this.trackers,
    required this.downloadSpeed,
    required this.uploadSpeed,
    required this.isComplete,
    required this.isCompleteOnDisk,
  });

  String get id => model.id;
  String get name => model.name;
  bool get isSeeding => state.contains('seed');
  bool get isActive => state.contains('download') || state.contains('seed');
  double get displayProgress => normalizeTorrentProgressForDisplay(progress);
  double get seedingProgress {
    final total = model.totalSize ?? 0;
    if (total <= 0) return 0.0;
    return (uploaded / total).clamp(0.0, 1.0);
  }
}

class _DiskReconcileSnapshot {
  final int bytesOnDisk;
  final bool isComplete;
  final bool pathMissing;
  final DateTime checkedAt;

  const _DiskReconcileSnapshot({
    required this.bytesOnDisk,
    required this.isComplete,
    required this.pathMissing,
    required this.checkedAt,
  });
}

class _DiskScanInput {
  final String torrentId;
  final String torrentName;
  final String outputPath;
  final int totalSize;
  final int fallbackBytes;

  const _DiskScanInput({
    required this.torrentId,
    required this.torrentName,
    required this.outputPath,
    required this.totalSize,
    required this.fallbackBytes,
  });
}

class _DiskScanResult {
  final String torrentId;
  final int bytesOnDisk;
  final bool isComplete;
  final bool pathMissing;

  const _DiskScanResult({
    required this.torrentId,
    required this.bytesOnDisk,
    required this.isComplete,
    required this.pathMissing,
  });
}

_DiskScanResult _runDiskScanSync(_DiskScanInput input) {
  if (input.totalSize <= 0 || input.outputPath.isEmpty) {
    return _DiskScanResult(
      torrentId: input.torrentId,
      bytesOnDisk: input.fallbackBytes,
      isComplete: false,
      pathMissing: false,
    );
  }

  var bytes = 0;
  var pathMissing = false;

  int sumFileBytesRecursively(Directory directory) {
    var total = 0;
    for (final entity in directory.listSync(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) continue;
      final lowerPath = entity.path.toLowerCase();
      final isStateFile = lowerPath.endsWith('.bt.state');
      final isStateBackup =
          lowerPath.contains('.bt.state.backup.') ||
          lowerPath.contains('.bt.state.bak');
      if (isStateFile || isStateBackup || lowerPath.endsWith('.torrent')) {
        continue;
      }
      total += entity.statSync().size;
    }
    return total;
  }

  try {
    final nameToken = input.torrentName.trim().toLowerCase();
    final lowerOutputPath = input.outputPath.toLowerCase();
    if (lowerOutputPath.endsWith('.torrent')) {
      return _DiskScanResult(
        torrentId: input.torrentId,
        bytesOnDisk: 0,
        isComplete: false,
        pathMissing: false,
      );
    }

    final type = FileSystemEntity.typeSync(input.outputPath);
    if (type == FileSystemEntityType.notFound) {
      return _DiskScanResult(
        torrentId: input.torrentId,
        bytesOnDisk: 0,
        isComplete: false,
        pathMissing: true,
      );
    }

    if (type == FileSystemEntityType.directory) {
      final root = Directory(input.outputPath);

      if (nameToken.isNotEmpty) {
        final nameCandidate = input.torrentName.trim();
        final directDir = Directory(p.join(root.path, nameCandidate));
        final directFile = File(p.join(root.path, nameCandidate));

        if (directDir.existsSync()) {
          bytes = sumFileBytesRecursively(directDir);
        } else if (directFile.existsSync()) {
          final lowerPath = directFile.path.toLowerCase();
          final isStateFile = lowerPath.endsWith('.bt.state');
          final isStateBackup =
              lowerPath.contains('.bt.state.backup.') ||
              lowerPath.contains('.bt.state.bak');
          if (!isStateFile && !isStateBackup && !lowerPath.endsWith('.torrent')) {
            bytes = directFile.statSync().size;
          }
        } else {
          for (final entity in root.listSync(
            recursive: false,
            followLinks: false,
          )) {
            final base = p.basename(entity.path).toLowerCase();
            if (!base.contains(nameToken)) continue;
            if (entity is File) {
              final lowerPath = entity.path.toLowerCase();
              final isStateFile = lowerPath.endsWith('.bt.state');
              final isStateBackup =
                  lowerPath.contains('.bt.state.backup.') ||
                  lowerPath.contains('.bt.state.bak');
              if (!isStateFile && !isStateBackup && !lowerPath.endsWith('.torrent')) {
                bytes += entity.statSync().size;
              }
            } else if (entity is Directory) {
              bytes += sumFileBytesRecursively(entity);
            }
          }
        }
      } else {
        bytes = sumFileBytesRecursively(root);
      }
    } else if (type == FileSystemEntityType.file) {
      final lowerPath = input.outputPath.toLowerCase();
      final isStateFile = lowerPath.endsWith('.bt.state');
      final isStateBackup =
          lowerPath.contains('.bt.state.backup.') ||
          lowerPath.contains('.bt.state.bak');
      if (!isStateFile && !isStateBackup && !lowerPath.endsWith('.torrent')) {
        bytes = File(input.outputPath).statSync().size;
      }
    }
  } catch (_) {
    bytes = 0;
    pathMissing = false;
  }

  return _DiskScanResult(
    torrentId: input.torrentId,
    bytesOnDisk: bytes,
    isComplete: input.totalSize > 0 && bytes >= input.totalSize,
    pathMissing: pathMissing,
  );
}

class TorrentService {
  TorrentService._();

  static final TorrentService instance = TorrentService._();

  final StreamController<List<TorrentViewState>> _torrentStatesController =
      StreamController<List<TorrentViewState>>.broadcast();
  StreamSubscription<TorrentEngineStatus>? _engineStatusSubscription;
  Timer? _snapshotTimer;
  Timer? _diskReconcileTimer;
  final Map<String, TorrentEngineStatus> _runtimeByTorrentId =
      <String, TorrentEngineStatus>{};
  final Map<String, TorrentViewState> _latestStatesByTorrentId =
      <String, TorrentViewState>{};
  final Map<String, _DiskReconcileSnapshot> _diskSnapshots =
      <String, _DiskReconcileSnapshot>{};
    final Map<String, double> _progressHighWaterByTorrentId =
      <String, double>{};
    final Map<String, int> _downloadedHighWaterByTorrentId = <String, int>{};
  final Map<String, DateTime> _pendingMetadataRetryAfter = <String, DateTime>{};
  final Set<String> _pendingMetadataRetryInFlight = <String>{};
  bool _stateSyncStarted = false;
  DateTime _lastSnapshotTime = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastRefreshTrigger = DateTime.fromMillisecondsSinceEpoch(0);
  bool _snapshotInProgress = false;
  bool _snapshotPending = false;
  static const Duration _snapshotInterval = Duration(seconds: 3);
  static const Duration _minRefreshInterval = Duration(seconds: 1);
  static const Duration _diskReconcileInterval = Duration(seconds: 60);

  Stream<List<TorrentViewState>> get torrentStatesStream {
    _ensureStateSyncStarted();
    return _torrentStatesController.stream;
  }

  Stream<TorrentViewState?> torrentStateStream(String torrentId) {
    _ensureStateSyncStarted();
    return torrentStatesStream.map((states) {
      for (final state in states) {
        if (state.id == torrentId) return state;
      }
      return null;
    });
  }

  TorrentViewState? latestTorrentState(String torrentId) {
    _ensureStateSyncStarted();
    return _latestStatesByTorrentId[torrentId];
  }

  Future<void> refreshTorrentStates() async {
    _ensureStateSyncStarted();
    await _takeSnapshot(force: true);
  }

  void _ensureStateSyncStarted() {
    if (_stateSyncStarted) return;
    _stateSyncStarted = true;

    _engineStatusSubscription = TorrentEngineService.instance.statusStream
        .listen((status) {
          if (status.torrentId.isEmpty) return;
          _runtimeByTorrentId[status.torrentId] = status;
          _snapshotPending = true;
        });

    _snapshotTimer = Timer.periodic(_snapshotInterval, (_) => _takeSnapshot());

    _diskReconcileTimer = Timer.periodic(
      _diskReconcileInterval,
      (_) => unawaited(_reconcileDiskState(force: true)),
    );

    // Emit an initial value immediately so StreamBuilder consumers can render
    // a stable empty state while the first DB snapshot is still loading.
    _torrentStatesController.add(_latestStatesByTorrentId.values.toList());

    unawaited(_takeSnapshot(force: true));
  }

  void _queueStateRefresh({bool force = false}) {
    if (force) {
      _snapshotPending = true;
      unawaited(_takeSnapshot(force: true));
      return;
    }

    final now = DateTime.now();
    if (now.difference(_lastRefreshTrigger) < _minRefreshInterval) {
      return;
    }

    _lastRefreshTrigger = now;
    _snapshotPending = true;
    unawaited(_takeSnapshot(force: false));
  }

  Future<void> _takeSnapshot({bool force = false}) async {
    if (_snapshotInProgress) return;
    if (!force && !_snapshotPending) return;

    _snapshotInProgress = true;
    _snapshotPending = false;
    _lastSnapshotTime = DateTime.now();

    try {
      final torrents = await TorrentsDao.instance.getAllTorrents();
      final merged = <TorrentViewState>[];

      for (final torrent in torrents) {
        _retryPendingMetadataIfDue(torrent);
        final diskSnapshot = _diskSnapshots[torrent.id];
        final runtime = _runtimeByTorrentId[torrent.id];
        final persistedState = torrent.status?.toLowerCase() ?? '';
        final diskBytes = diskSnapshot?.bytesOnDisk ?? torrent.bytesDown;
        final diskComplete = diskSnapshot?.isComplete ?? false;
        final pathMissing = diskSnapshot?.pathMissing ?? false;
        final hasDiskSnapshot = diskSnapshot != null;

        var downloaded = [
          runtime?.downloaded ?? 0,
          torrent.bytesDown,
          diskBytes,
        ].reduce(math.max);

        final totalSize = torrent.totalSize ?? 0;
        final runtimeFarAheadOfDisk =
            hasDiskSnapshot &&
            runtime != null &&
            runtime.state.toLowerCase().contains('download') &&
            runtime.downloaded > diskBytes + (64 * 1024 * 1024) &&
            (totalSize <= 0 || diskBytes < (totalSize * 0.10).round());
        if (runtimeFarAheadOfDisk ||
            (persistedState.contains('downloading') &&
                hasDiskSnapshot &&
                diskBytes == 0)) {
          downloaded = math.max(torrent.bytesDown, diskBytes);
        }

        final missingOnDisk =
            hasDiskSnapshot &&
            pathMissing &&
            runtime == null &&
            !persistedState.contains('pending_metadata');
        if (missingOnDisk) {
          downloaded = 0;
        }

        final runtimeState = runtime?.state.toLowerCase() ?? '';
        final runtimeLooksComplete =
          runtime != null && runtimeState.contains('seed');
        final diskContradictsCompletion =
            hasDiskSnapshot &&
            totalSize > 0 &&
            !diskComplete &&
            diskBytes < (totalSize * 0.98).round();
        final runtimeComplete =
            runtimeLooksComplete && !diskContradictsCompletion;
        final diskCompleteTrusted =
          diskComplete &&
          (runtime == null ||
            runtimeState.contains('seed') ||
            runtimeState.contains('pause') ||
            runtimeState.contains('stop'));
        final isComplete =
          !missingOnDisk && (diskCompleteTrusted || runtimeComplete);

        if (diskContradictsCompletion) {
          downloaded = diskBytes;
        }

        if (isComplete && totalSize > 0) {
          downloaded = math.max(downloaded, totalSize);
        }

        final uploaded = runtime?.uploaded ?? torrent.bytesUp;
        final effectiveRuntimeState = diskContradictsCompletion
            ? 'downloading'
            : runtime?.state;
        final state = _deriveState(
          torrent.status,
          effectiveRuntimeState,
          isComplete,
          missingOnDisk: missingOnDisk,
          hasRuntime: runtime != null,
        );
        var progress = isComplete
            ? 1.0
            : totalSize > 0
            ? (downloaded / totalSize).clamp(0.0, 1.0)
            : (runtime?.progress ?? torrent.progress).clamp(0.0, 1.0);

        final allowsProgressRegression =
            missingOnDisk ||
            state.contains('checking') ||
            state.contains('error_missing_files');

        if (allowsProgressRegression) {
          _progressHighWaterByTorrentId[torrent.id] = progress;
          _downloadedHighWaterByTorrentId[torrent.id] = downloaded;
        } else {
          final previousProgress =
              _progressHighWaterByTorrentId[torrent.id] ??
              _latestStatesByTorrentId[torrent.id]?.progress ??
              torrent.progress;
          if (progress + 0.02 < previousProgress) {
            progress = previousProgress;
          }
          _progressHighWaterByTorrentId[torrent.id] = math.max(
            previousProgress,
            progress,
          );

          final previousDownloaded =
              _downloadedHighWaterByTorrentId[torrent.id] ?? torrent.bytesDown;
          if (totalSize > 0 && downloaded < previousDownloaded) {
            downloaded = previousDownloaded;
          }
          _downloadedHighWaterByTorrentId[torrent.id] = math.max(
            previousDownloaded,
            downloaded,
          );
        }

        final isSeeding = state.contains('seed');
        final dlSpeed = isSeeding ? 0.0 : (runtime?.downloadSpeed ?? 0.0);
        final ulSpeed = runtime?.uploadSpeed ?? 0.0;
        final peers = runtime?.peers ?? 0;
        final seeders = runtime?.seeders ?? torrent.seeders;
        final leechers = runtime?.leechers ?? torrent.leechers;

        final mergedState = TorrentViewState(
          model: torrent,
          downloaded: downloaded,
          uploaded: uploaded,
          progress: progress,
          state: state,
          statusLabel: _statusLabelForState(state),
          statusMessage:
              runtime?.statusMessage ??
              _fallbackStatusMessage(state, progress, peers),
          connectionMessage: runtime?.connectionMessage ?? '',
          peers: peers,
          seeders: seeders,
          leechers: leechers,
          dhtNodes: runtime?.dhtNodes ?? 0,
          trackers: runtime?.trackers ?? 0,
          downloadSpeed: dlSpeed,
          uploadSpeed: ulSpeed,
          isComplete: isComplete,
          isCompleteOnDisk: diskComplete,
        );

        merged.add(mergedState);
      }

      _latestStatesByTorrentId
        ..clear()
        ..addEntries(merged.map((s) => MapEntry(s.id, s)));
      _torrentStatesController.add(merged);

      unawaited(_persistAllReconciled(merged));
    } catch (e, st) {
      debugPrint('TorrentService snapshot error: $e\n$st');
    } finally {
      _snapshotInProgress = false;
    }
  }

  Future<void> _persistAllReconciled(List<TorrentViewState> states) async {
    for (final view in states) {
      await _persistReconciledTorrent(view);
    }
  }

  Future<void> _persistReconciledTorrent(TorrentViewState view) async {
    final existing = await TorrentsDao.instance.getTorrentById(view.id);
    if (existing == null) return;

    final updatedStatus = view.state;
    final completedAt = view.isComplete
        ? (existing.completedAt ?? DateTime.now().millisecondsSinceEpoch)
        : existing.completedAt;

    final bytesDelta = (view.downloaded - existing.bytesDown).abs();
    final shouldUpdate =
        bytesDelta > 512 * 1024 ||
        (existing.status ?? '') != updatedStatus ||
        existing.seeders != view.seeders ||
        existing.leechers != view.leechers ||
        completedAt != existing.completedAt;

    if (!shouldUpdate) return;

    await TorrentsDao.instance.updateTorrent(
      existing.copyWith(
        bytesDown: view.downloaded,
        bytesUp: view.uploaded,
        status: updatedStatus,
        completedAt: completedAt,
        seeders: view.seeders,
        leechers: view.leechers,
      ),
    );
  }

  Future<void> _reconcileDiskState({bool force = false}) async {
    final torrents = await TorrentsDao.instance.getAllTorrents();
    final futures = torrents.map((torrent) async {
      final cached = _diskSnapshots[torrent.id];
      if (!force &&
          cached != null &&
          DateTime.now().difference(cached.checkedAt) <
              _diskReconcileInterval) {
        return;
      }

      try {
        final result = await compute(
          _runDiskScanSync,
          _DiskScanInput(
            torrentId: torrent.id,
            torrentName: torrent.name,
            outputPath: torrent.filePath?.trim() ?? '',
            totalSize: torrent.totalSize ?? 0,
            fallbackBytes: cached?.bytesOnDisk ?? torrent.bytesDown,
          ),
        );
        _diskSnapshots[torrent.id] = _DiskReconcileSnapshot(
          bytesOnDisk: result.bytesOnDisk,
          isComplete: result.isComplete,
          pathMissing: result.pathMissing,
          checkedAt: DateTime.now(),
        );
      } catch (_) {
        // Keep existing cache on failures.
      }
    });

    await Future.wait(futures);
    _snapshotPending = true;
  }

  String _deriveState(
    String? persistedState,
    String? runtimeState,
    bool complete, {
    bool missingOnDisk = false,
    bool hasRuntime = false,
  }) {
    if (missingOnDisk && !hasRuntime) return 'error_missing_files';
    if (complete) return 'seeding';
    final runtime = runtimeState?.toLowerCase() ?? '';
    if (runtime.contains('error')) return runtime;
    if (runtime.contains('pause')) return 'paused';
    if (runtime.contains('queue')) return 'queued';
    if (runtime.contains('seed')) return 'seeding';
    if (runtime.contains('download')) return 'downloading';

    final persisted = persistedState?.toLowerCase() ?? '';
    if (persisted.contains('pending_metadata')) return 'pending_metadata';
    if (persisted.contains('error')) return persisted;
    if (persisted.contains('pause')) return 'paused';
    if (persisted.contains('queue')) return 'queued';
    if (persisted.contains('seed')) return 'seeding';
    if (persisted.contains('download')) return 'downloading';
    return persisted.isEmpty ? 'queued' : persisted;
  }

  String _statusLabelForState(String state) {
    if (state.contains('seed')) return 'Seeding';
    if (state == 'checking') return 'Checking';
    if (state.contains('checking')) return 'Checking';
    if (state.contains('download')) return 'Downloading';
    if (state.contains('pause')) return 'Paused';
    if (state.contains('error_file_in_use')) return 'File In Use';
    if (state.contains('error_missing_files')) return 'Missing Files';
    if (state.contains('pending_metadata')) return 'Pending Metadata';
    if (state.contains('queue')) return 'Queued';
    if (state.contains('error')) return 'Error';
    return state;
  }

  String _fallbackStatusMessage(String state, double progress, int peers) {
    final displayProgress = normalizeTorrentProgressForDisplay(progress);
    if (state.contains('error_file_in_use')) {
      return 'Redownload blocked: close programs using the file and retry.';
    }
    if (state.contains('error_missing_files')) {
      return 'Downloaded files are missing from disk. Recheck save path or redownload.';
    }
    if (state.contains('pending_metadata')) {
      return 'Waiting for peers to provide metadata...';
    }
    if (state.contains('seed')) {
      return 'Seeding • ${(displayProgress * 100).toStringAsFixed(1)}%';
    }
    if (state.contains('pause')) {
      return 'Paused • ${(displayProgress * 100).toStringAsFixed(1)}%';
    }
    if (state.contains('download')) {
      if (peers <= 0) {
        return 'Searching for peers...';
      }
      return 'Downloading • ${(displayProgress * 100).toStringAsFixed(1)}% • $peers peers';
    }
    if (state.contains('error')) {
      return 'Torrent error';
    }
    return '${(displayProgress * 100).toStringAsFixed(1)}%';
  }

  void _retryPendingMetadataIfDue(TorrentModel torrent) {
    final status = torrent.status?.toLowerCase() ?? '';
    if (!status.contains('pending_metadata')) return;
    if (TorrentEngineService.instance.isRunning(torrent.id)) return;
    if (_pendingMetadataRetryInFlight.contains(torrent.id)) return;

    final now = DateTime.now();
    final nextTry = _pendingMetadataRetryAfter[torrent.id];
    if (nextTry != null && now.isBefore(nextTry)) return;
    _pendingMetadataRetryAfter[torrent.id] = now.add(
      const Duration(seconds: 90),
    );
    _pendingMetadataRetryInFlight.add(torrent.id);

    unawaited(() async {
      try {
        await TorrentEngineService.instance.startTorrent(torrent.id);
        await updateTorrentStatus(torrent.id, 'downloading');
      } on TimeoutException {
        await updateTorrentStatus(torrent.id, 'pending_metadata');
      } catch (_) {
        // Keep pending state; retry later.
      } finally {
        _pendingMetadataRetryInFlight.remove(torrent.id);
      }
    }());
  }

  static String _ensureString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is Uint8List) {
      try {
        return utf8.decode(value, allowMalformed: true);
      } catch (e) {
        debugPrint('TorrentService._ensureString decode error: $e');
        return value.toString();
      }
    }
    try {
      return value.toString();
    } catch (e) {
      debugPrint('TorrentService._ensureString toString error: $e');
      return '';
    }
  }

  static bool isTorrentOrMagnetUrl(String url) {
    final lower = url.trim().toLowerCase();
    return lower.startsWith('magnet:') || lower.endsWith('.torrent');
  }

  static String normalizeTorrentUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';

    final lower = trimmed.toLowerCase();
    if (lower.startsWith('magnet:') || lower.startsWith('file://')) {
      return trimmed;
    }

    if (lower.endsWith('.torrent')) {
      // Keep explicit .torrent paths as-is so we can support local files and web URLs.
      return trimmed;
    }

    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return trimmed;
    }

    return 'https://$trimmed';
  }

  Future<List<TorrentModel>> allTorrents() =>
      TorrentsDao.instance.getAllTorrents();

  Future<List<TorrentModel>> findTorrents(String query) async {
    final keyword = query.toLowerCase().trim();
    final all = await allTorrents();
    return all.where((torrent) {
      final name = torrent.name.toLowerCase();
      final magnet = torrent.magnetLink?.toLowerCase() ?? '';
      return name.contains(keyword) || magnet.contains(keyword);
    }).toList();
  }

  Future<void> addTorrent(TorrentModel torrent) async {
    await TorrentsDao.instance.insertTorrent(torrent);
    _snapshotPending = true;
    unawaited(_takeSnapshot(force: true));
  }

  Future<TorrentModel?> getTorrentById(String id) =>
      TorrentsDao.instance.getTorrentById(id);

  Future<void> updateTorrent(TorrentModel torrent) async {
    await TorrentsDao.instance.updateTorrent(torrent);
    _snapshotPending = true;
  }

  Future<void> removeTorrent(String id) async {
    await TorrentsDao.instance.deleteTorrent(id);
    _runtimeByTorrentId.remove(id);
    _latestStatesByTorrentId.remove(id);
    _diskSnapshots.remove(id);
    _progressHighWaterByTorrentId.remove(id);
    _downloadedHighWaterByTorrentId.remove(id);
    _pendingMetadataRetryAfter.remove(id);
    _pendingMetadataRetryInFlight.remove(id);
    _snapshotPending = true;
    unawaited(_takeSnapshot(force: true));
  }

  void invalidateDiskSnapshot(String id) {
    _runtimeByTorrentId.remove(id);
    _latestStatesByTorrentId.remove(id);
    _diskSnapshots[id] = _DiskReconcileSnapshot(
      bytesOnDisk: 0,
      isComplete: false,
      pathMissing: false,
      checkedAt: DateTime.now(),
    );
    _snapshotPending = true;
    unawaited(_takeSnapshot(force: true));
    unawaited(_reconcileDiskState(force: true));
  }

  Future<void> purgeTorrentArtifacts(String id) async {
    final torrent = await TorrentsDao.instance.getTorrentById(id);
    if (torrent == null) return;

    final rawPath = torrent.filePath?.trim();
    final candidatePath = rawPath == null || rawPath.isEmpty
        ? SettingsService.instance.downloadDestination.trim()
        : rawPath;
    if (candidatePath.isEmpty) return;

    final lowerPath = candidatePath.toLowerCase();
    if (lowerPath.endsWith('.torrent')) {
      return;
    }

    await _deletePathWithRetry(candidatePath);
    final parent =
        FileSystemEntity.typeSync(candidatePath) == FileSystemEntityType.file
        ? File(candidatePath).parent.path
        : candidatePath;
    final stateFile = File(p.join(parent, '.bt.state'));
    if (await stateFile.exists()) {
      await _deletePathWithRetry(stateFile.path);
    }

    _diskSnapshots.remove(id);
  }

  Future<void> _deletePathWithRetry(
    String path, {
    int attempts = 5,
    Duration delay = const Duration(milliseconds: 250),
  }) async {
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        final type = await FileSystemEntity.type(path, followLinks: false);
        if (type == FileSystemEntityType.notFound) return;
        final entity = FileSystemEntity.isDirectorySync(path)
            ? Directory(path)
            : File(path);
        await entity.delete(recursive: true);
        return;
      } catch (e) {
        if (attempt == attempts) {
          debugPrint('Failed to delete torrent artifact $path: $e');
          return;
        }
        await Future.delayed(delay);
      }
    }
  }

  Future<void> resumeActiveTorrents() async {
    final torrents = await allTorrents();
    final active = torrents.where((torrent) {
      final status = torrent.status?.toLowerCase() ?? '';
      // Only resume downloading/seeding torrents, not error states
      return (status == 'downloading' || status == 'seeding') &&
          !status.contains('error');
    }).toList();

    const batchSize = 2;
    for (var i = 0; i < active.length; i += batchSize) {
      final batch = active.skip(i).take(batchSize).toList();
      await Future.wait(
        batch.map((torrent) async {
          try {
            await TorrentEngineService.instance.startTorrent(torrent.id);
          } catch (e, st) {
            debugPrint('Failed to resume torrent ${torrent.id}: $e');
            debugPrint(st.toString());
            await updateTorrentStatus(torrent.id, 'error_resume_failed');
          }
        }),
      );

      if (i + batchSize < active.length) {
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }

    // On Windows: hide any .bt.state files in the download folder so they
    // don't appear in Explorer and confuse users.
    if (Platform.isWindows) {
      unawaited(_hideAllBtStateFiles());
    }
  }

  Future<void> _hideAllBtStateFiles() async {
    final dir = SettingsService.instance.downloadDestination.trim();
    if (dir.isEmpty) return;
    try {
      await for (final entity in Directory(dir)
          .list(recursive: true, followLinks: false)) {
        if (entity is File &&
            entity.path.toLowerCase().endsWith('.bt.state')) {
          TorrentEngineService.instance.markFileHiddenOnWindows(entity.path);
        }
      }
    } catch (_) {}
  }

  Future<void> updateTorrentStatus(String id, String status) async {
    final existing = await TorrentsDao.instance.getTorrentById(id);
    if (existing == null) {
      throw StateError('Torrent not found: $id');
    }
    final updated = TorrentModel(
      id: existing.id,
      name: existing.name,
      type: existing.type,
      totalSize: existing.totalSize,
      totalPieces: existing.totalPieces,
      pieceLength: existing.pieceLength,
      piecesHave: existing.piecesHave,
      status: status,
      vaultKey: existing.vaultKey,
      filePath: existing.filePath,
      vaultLink: existing.vaultLink,
      magnetLink: existing.magnetLink,
      bytesDown: existing.bytesDown,
      bytesUp: existing.bytesUp,
      addedAt: existing.addedAt,
      completedAt: existing.completedAt,
      isSequential: existing.isSequential,
      selectedFiles: existing.selectedFiles,
      maxSeedRatio: existing.maxSeedRatio,
      deleteAfterRatioReached: existing.deleteAfterRatioReached,
    );
    await TorrentsDao.instance.updateTorrent(updated);
    _queueStateRefresh(force: true);
  }

  Future<void> setSeedRatioLimit(String id, double ratio) async {
    final existing = await TorrentsDao.instance.getTorrentById(id);
    if (existing == null) {
      throw StateError('Torrent not found: $id');
    }
    final updated = TorrentModel(
      id: existing.id,
      name: existing.name,
      type: existing.type,
      totalSize: existing.totalSize,
      totalPieces: existing.totalPieces,
      pieceLength: existing.pieceLength,
      piecesHave: existing.piecesHave,
      status: existing.status,
      vaultKey: existing.vaultKey,
      filePath: existing.filePath,
      vaultLink: existing.vaultLink,
      magnetLink: existing.magnetLink,
      bytesDown: existing.bytesDown,
      bytesUp: existing.bytesUp,
      addedAt: existing.addedAt,
      completedAt: existing.completedAt,
      isSequential: existing.isSequential,
      selectedFiles: existing.selectedFiles,
      maxSeedRatio: ratio,
      deleteAfterRatioReached: existing.deleteAfterRatioReached,
    );
    await TorrentsDao.instance.updateTorrent(updated);
    _queueStateRefresh(force: true);
  }

  Future<void> setDeleteAfterRatioReached(String id, bool value) async {
    final existing = await TorrentsDao.instance.getTorrentById(id);
    if (existing == null) {
      throw StateError('Torrent not found: $id');
    }
    final updated = TorrentModel(
      id: existing.id,
      name: existing.name,
      type: existing.type,
      totalSize: existing.totalSize,
      totalPieces: existing.totalPieces,
      pieceLength: existing.pieceLength,
      piecesHave: existing.piecesHave,
      status: existing.status,
      vaultKey: existing.vaultKey,
      filePath: existing.filePath,
      vaultLink: existing.vaultLink,
      magnetLink: existing.magnetLink,
      bytesDown: existing.bytesDown,
      bytesUp: existing.bytesUp,
      addedAt: existing.addedAt,
      completedAt: existing.completedAt,
      isSequential: existing.isSequential,
      selectedFiles: existing.selectedFiles,
      maxSeedRatio: existing.maxSeedRatio,
      deleteAfterRatioReached: value,
    );
    await TorrentsDao.instance.updateTorrent(updated);
    _queueStateRefresh(force: true);
  }

  Future<void> updateProgress(String id, int bytesDown, int bytesUp) async {
    final existing = await TorrentsDao.instance.getTorrentById(id);
    if (existing == null) return;

    if (existing.maxSeedRatio != null && existing.maxSeedRatio! > 0) {
      final ratio = existing.bytesDown > 0 ? bytesUp / existing.bytesDown : 0.0;
      if (ratio >= existing.maxSeedRatio!) {
        await TorrentsDao.instance.updateTorrent(
          existing.copyWith(
            status: 'seed_ratio_reached',
            bytesDown: bytesDown,
            bytesUp: bytesUp,
          ),
        );
        if (existing.deleteAfterRatioReached) {
          await TorrentsDao.instance.deleteTorrent(id);
          _runtimeByTorrentId.remove(id);
          _latestStatesByTorrentId.remove(id);
          _diskSnapshots.remove(id);
          _progressHighWaterByTorrentId.remove(id);
          _downloadedHighWaterByTorrentId.remove(id);
          _pendingMetadataRetryAfter.remove(id);
          _pendingMetadataRetryInFlight.remove(id);
        }
        _snapshotPending = true;
      }
    }
  }

  Future<void> downloadTorrent(String id, String destinationPath) async {
    final existing = await TorrentsDao.instance.getTorrentById(id);
    if (existing == null) {
      throw StateError('Torrent not found: $id');
    }

    if (destinationPath.trim().isEmpty) {
      throw ArgumentError('Destination path cannot be empty');
    }

    final destinationDir = Directory(destinationPath);
    if (!await destinationDir.exists()) {
      throw FileSystemException(
        'Destination folder does not exist',
        destinationPath,
      );
    }

    await updateTorrent(
      existing.copyWith(
        status: 'downloading',
        bytesDown: existing.bytesDown,
        bytesUp: existing.bytesUp,
      ),
    );

    try {
      await TorrentEngineService.instance.startTorrent(
        id,
        destinationPath: destinationPath,
      );
    } catch (e, st) {
      debugPrint('TorrentEngine startTorrent failed: $e');
      debugPrint('$st');
      rethrow;
    }

    final completer = Completer<void>();
    StreamSubscription<TorrentEngineStatus>? subscription;
    subscription = TorrentEngineService.instance.statusStream
        .where((status) => status.torrentId == id)
        .listen((status) async {
          if (status.state == 'completed') {
            if (!completer.isCompleted) completer.complete();
          } else if (status.state == 'error') {
            if (!completer.isCompleted) {
              completer.completeError(
                StateError('Download failed for torrent $id'),
              );
            }
          }

          if (status.downloaded > 0) {
            await updateProgress(id, status.downloaded, status.uploaded);
          }
        });

    try {
      await completer.future.timeout(
        const Duration(hours: 12),
        onTimeout: () => throw TimeoutException('Torrent download timed out'),
      );
    } finally {
      await subscription.cancel();
      await TorrentEngineService.instance.stopTorrent(id);
    }

    final completed = await getTorrentById(id);
    if (completed != null) {
      await updateTorrent(
        completed.copyWith(
          status: 'completed',
          completedAt: DateTime.now().millisecondsSinceEpoch,
          isSequential: true,
        ),
      );
    }
  }

  // ignore: unused_element
  Future<TorrentMetadata?> _loadTorrentMetadata(TorrentModel torrent) async {
    if (torrent.type == 'torrent_file' && torrent.filePath != null) {
      final file = File(torrent.filePath!);
      if (await file.exists()) {
        try {
          return TorrentFileParser.parse(await file.readAsBytes());
        } catch (_) {
          // fallback
        }
      }
    }
    return null;
  }

  // ignore: unused_element
  Future<void> _prepareTargetFiles(
    TorrentModel torrent,
    Directory destinationDir,
    TorrentMetadata? metadata,
    int totalSize,
  ) async {
    if (metadata != null && metadata.files.isNotEmpty) {
      for (final fileEntry in metadata.files) {
        final targetPath = p.join(destinationDir.path, fileEntry.path);
        final targetFile = File(targetPath);
        await targetFile.parent.create(recursive: true);
        final raf = await targetFile.open(mode: FileMode.write);
        await raf.truncate(fileEntry.length);
        await raf.close();
      }
    } else {
      final name = torrent.name.isNotEmpty ? torrent.name : torrent.id;
      final sanitized = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
      final filePath = p.join(destinationDir.path, '$sanitized.bin');
      final file = File(filePath);
      await file.parent.create(recursive: true);
      final raf = await file.open(mode: FileMode.write);
      await raf.truncate(totalSize);
      await raf.close();
    }
  }

  Future<void> setDestinationAndStart(String id, String destinationPath) async {
    final torrent = await getTorrentById(id);
    if (torrent == null) {
      throw StateError('Torrent not found: $id');
    }

    await updateTorrent(torrent.copyWith(status: 'downloading'));
    await downloadTorrent(id, destinationPath);
  }

  Future<void> addTorrentFromTorrentFile(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('Torrent file does not exist', path);
    }

    final bytes = await file.readAsBytes();
    final metadata = TorrentFileParser.parse(bytes);
    final infoHash = _ensureString(metadata.infoHashV1);
    final torrentName = _ensureString(metadata.name);

    final existing = await TorrentsDao.instance.getTorrentById(infoHash);
    if (existing != null) {
      await TorrentEngineService.instance.forceRefresh(existing.id);
      throw TorrentAlreadyExistsException(existing.id);
    }

    final totalSize = metadata.files.fold<int>(
      0,
      (sum, entry) => sum + entry.length,
    );
    final magnetLink = createMagnetLink(
      infoHash,
      torrentName,
      metadata.trackers,
    );

    final torrent = TorrentModel(
      id: infoHash,
      name: torrentName,
      type: 'torrent_file',
      totalSize: totalSize,
      totalPieces: metadata.pieceHashes.length,
      pieceLength: metadata.pieceLength,
      piecesHave: null,
      status: 'added',
      filePath: p.normalize(path),
      magnetLink: magnetLink,
      bytesDown: 0,
      bytesUp: 0,
      addedAt: DateTime.now().millisecondsSinceEpoch,
      isSequential: true,
    );

    await TorrentsDao.instance.insertTorrent(torrent);

    if (SettingsService.instance.autoStartOnAdd) {
      await updateTorrentStatus(metadata.infoHashV1, 'downloading');
      await TorrentEngineService.instance.startTorrent(metadata.infoHashV1);
    } else {
      await updateTorrentStatus(metadata.infoHashV1, 'queued');
    }
    _queueStateRefresh(force: true);
  }

  Future<MagnetAddOutcome> addTorrentFromMagnet(String uri) =>
      addTorrentFromMagnetLink(uri);

  Future<void> handleIncomingSearch(
    String query, {
    required String requesterId,
  }) async {
    // VaultSwarm transport removed.
    return;
  }

  Future<MagnetAddOutcome> addTorrentFromMagnetLink(dynamic uri) async {
    final magnetUri = _ensureString(uri);

    final magnet = MagnetLink.parse(magnetUri);
    final infoHash = magnet.infoHashV1 ?? magnet.infoHashV2;
    if (infoHash == null || infoHash.isEmpty) {
      throw FormatException('Magnet link must contain btih or btmh infohash');
    }

    final existing = await TorrentsDao.instance.getTorrentById(infoHash);
    if (existing != null) {
      await TorrentEngineService.instance.forceRefresh(existing.id);
      throw TorrentAlreadyExistsException(existing.id);
    }

    final torrent = TorrentModel(
      id: infoHash,
      name: magnet.displayName ?? 'Magnet $infoHash',
      type: 'magnet_link',
      totalSize: null,
      totalPieces: null,
      pieceLength: null,
      piecesHave: null,
      status: 'queued',
      filePath: null,
      vaultLink: null,
      magnetLink: magnetUri,
      bytesDown: 0,
      bytesUp: 0,
      addedAt: DateTime.now().millisecondsSinceEpoch,
      isSequential: true,
    );

    await TorrentsDao.instance.insertTorrent(torrent);
    if (SettingsService.instance.autoStartOnAdd) {
      await updateTorrent(torrent.copyWith(status: 'downloading'));
      try {
        await TorrentEngineService.instance.startTorrent(infoHash);
        _queueStateRefresh(force: true);
        return MagnetAddOutcome.started;
      } on TimeoutException {
        await updateTorrentStatus(infoHash, 'pending_metadata');
        _pendingMetadataRetryAfter[infoHash] = DateTime.now().add(
          const Duration(seconds: 90),
        );
        _queueStateRefresh(force: true);
        return MagnetAddOutcome.pendingMetadata;
      }
    }

    await updateTorrent(torrent.copyWith(status: 'queued'));
    _queueStateRefresh(force: true);
    return MagnetAddOutcome.queued;
  }

  static String createMagnetLink(
    String infoHash,
    String name,
    List<String> trackers,
  ) {
    final encodedName = Uri.encodeComponent(name);
    final trackersQuery = trackers
        .where((t) => t.isNotEmpty)
        .map((t) => 'tr=${Uri.encodeComponent(t)}')
        .join('&');

    final List<String> pieces = ['xt=urn:btih:$infoHash', 'dn=$encodedName'];

    if (trackersQuery.isNotEmpty) {
      pieces.addAll(trackersQuery.split('&'));
    }

    return 'magnet:?${pieces.join('&')}';
  }

  Future<void> addTorrentFromPath(
    String path, {
    int pieceLength = 262144,
  }) async {
    final type = await FileSystemEntity.type(path);
    if (type == FileSystemEntityType.notFound) {
      throw FileSystemException('Path does not exist', path);
    }

    final root = Directory(path);
    final name = p.basename(path);
    final baseDir = type == FileSystemEntityType.directory
        ? Directory(path)
        : File(path).parent;

    final List<_FileEntry> entries = [];

    if (type == FileSystemEntityType.file) {
      final file = File(path);
      final stat = await file.stat();
      entries.add(
        _FileEntry(
          file.path,
          p.relative(file.path, from: baseDir.path),
          stat.size,
        ),
      );
    } else {
      await for (var entity in root.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final rel = p.relative(entity.path, from: root.path);
          final stat = await entity.stat();
          entries.add(_FileEntry(entity.path, rel, stat.size));
        }
      }
      entries.sort((a, b) => a.relativePath.compareTo(b.relativePath));
    }

    if (entries.isEmpty) {
      throw StateError('No files to create torrent from');
    }

    final bytesBuilder = BytesBuilder();
    final pieceHashes = BytesBuilder();
    int bufferLen = 0;

    Future<void> addChunk(List<int> chunk) async {
      bytesBuilder.add(chunk);
      bufferLen += chunk.length;
      if (bufferLen >= pieceLength) {
        final pieceData = bytesBuilder.toBytes();
        final toHash = pieceData.sublist(0, pieceLength);
        final digest = sha1.convert(toHash);
        pieceHashes.add(digest.bytes);
        final remaining = pieceData.sublist(pieceLength);
        bytesBuilder.clear();
        bytesBuilder.add(remaining);
        bufferLen = remaining.length;
      }
    }

    for (final entry in entries) {
      final file = File(entry.path);
      final raf = file.openRead();
      await for (final chunk in raf) {
        await addChunk(chunk);
      }
    }

    if (bufferLen > 0) {
      final digest = sha1.convert(bytesBuilder.toBytes());
      pieceHashes.add(digest.bytes);
    }

    final info = <String, dynamic>{
      'name': name,
      'piece length': pieceLength,
      'pieces': Uint8List.fromList(pieceHashes.toBytes()),
    };

    if (type == FileSystemEntityType.file) {
      info['length'] = entries.first.length;
    } else {
      final files = entries
          .map(
            (e) => {
              'length': e.length,
              'path': e.relativePath.split(p.separator),
            },
          )
          .toList();
      info['files'] = files;
    }

    final metadict = <String, dynamic>{
      'announce': 'https://tracker.openbittorrent.com:443/announce',
      'info': info,
    };

    final torrentBytes = bencode(metadict);
    final torrentFileName = '$name.torrent';
    final torrentFilePath = p.join(baseDir.path, torrentFileName);
    final torrentFile = File(torrentFilePath);
    await torrentFile.writeAsBytes(torrentBytes, flush: true);

    await addTorrentFromTorrentFile(torrentFilePath);
  }
}

class _FileEntry {
  final String path;
  final String relativePath;
  final int length;

  _FileEntry(this.path, this.relativePath, this.length);
}