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
  double get seedingProgress {
    final total = model.totalSize ?? 0;
    if (total <= 0) return 0.0;
    return (uploaded / total).clamp(0.0, 1.0);
  }
}

class _DiskReconcileSnapshot {
  final int bytesOnDisk;
  final bool isComplete;
  final DateTime checkedAt;

  const _DiskReconcileSnapshot({
    required this.bytesOnDisk,
    required this.isComplete,
    required this.checkedAt,
  });
}

class TorrentService {
  TorrentService._();

  static final TorrentService instance = TorrentService._();

  final StreamController<List<TorrentViewState>> _torrentStatesController =
      StreamController<List<TorrentViewState>>.broadcast();
  StreamSubscription<TorrentEngineStatus>? _engineStatusSubscription;
  Timer? _stateRefreshTimer;
  Timer? _diskReconcileTimer;
  final Map<String, TorrentEngineStatus> _runtimeByTorrentId =
      <String, TorrentEngineStatus>{};
  final Map<String, TorrentViewState> _latestStatesByTorrentId =
      <String, TorrentViewState>{};
  final Map<String, _DiskReconcileSnapshot> _diskSnapshots =
      <String, _DiskReconcileSnapshot>{};
  final Map<String, DateTime> _pendingMetadataRetryAfter =
      <String, DateTime>{};
  bool _stateSyncStarted = false;
  bool _stateRefreshInFlight = false;
  bool _stateRefreshQueued = false;

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
    await _refreshMergedTorrentStates(force: true);
  }

  void _ensureStateSyncStarted() {
    if (_stateSyncStarted) return;
    _stateSyncStarted = true;

    _engineStatusSubscription = TorrentEngineService.instance.statusStream
        .listen((status) {
          if (status.torrentId.isEmpty) return;
          _runtimeByTorrentId[status.torrentId] = status;
          _queueStateRefresh();
        });

    _stateRefreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _queueStateRefresh(),
    );

    _diskReconcileTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => unawaited(_reconcileDiskState(force: true)),
    );

    // If we already have cached merged states, emit them immediately.
    // Do not emit an empty list here, otherwise UI may show a false
    // "no torrents" state while DB/runtime refresh is still loading.
    if (_latestStatesByTorrentId.isNotEmpty) {
      _torrentStatesController.add(_latestStatesByTorrentId.values.toList());
    }

    // First refresh should be lightweight (no forced recursive disk scan).
    _queueStateRefresh(force: false);

    // Reconcile disk truth in background after initial UI is visible.
    unawaited(_reconcileDiskState(force: true));
  }

  void _queueStateRefresh({bool force = false}) {
    unawaited(_refreshMergedTorrentStates(force: force));
  }

  Future<void> _refreshMergedTorrentStates({bool force = false}) async {
    if (_stateRefreshInFlight) {
      _stateRefreshQueued = true;
      return;
    }

    _stateRefreshInFlight = true;
    try {
      final torrents = await TorrentsDao.instance.getAllTorrents();
      final merged = <TorrentViewState>[];

      for (final torrent in torrents) {
        await _retryPendingMetadataIfDue(torrent);
        final diskSnapshot = await _getDiskSnapshot(torrent, force: force);
        final runtime = _runtimeByTorrentId[torrent.id];

        var downloaded = [
          runtime?.downloaded ?? 0,
          torrent.bytesDown,
          diskSnapshot.bytesOnDisk,
        ].reduce(math.max);

        final totalSize = torrent.totalSize ?? 0;
        final persistedSeeding =
          (torrent.status?.toLowerCase() ?? '').contains('seed');
        final runtimeComplete = runtime != null &&
            (runtime.state.toLowerCase().contains('seed') ||
                (totalSize > 0 && runtime.downloaded >= totalSize) ||
                runtime.progress >= 0.999);
        final isComplete = diskSnapshot.isComplete ||
            runtimeComplete ||
          persistedSeeding ||
            (totalSize > 0 && downloaded >= totalSize);

        if (isComplete && totalSize > 0) {
          downloaded = math.max(downloaded, totalSize);
        }

        final uploaded = runtime?.uploaded ?? torrent.bytesUp;
        final state = _deriveState(torrent.status, runtime?.state, isComplete);
        final progress = isComplete
            ? 1.0
            : totalSize > 0
                ? (downloaded / totalSize).clamp(0.0, 1.0)
                : (runtime?.progress ?? torrent.progress).clamp(0.0, 1.0);

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
          statusMessage: runtime?.statusMessage ??
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
          isCompleteOnDisk: diskSnapshot.isComplete,
        );

        await _persistReconciledTorrent(mergedState);
        merged.add(mergedState);
      }

      _latestStatesByTorrentId
        ..clear()
        ..addEntries(merged.map((s) => MapEntry(s.id, s)));
      _torrentStatesController.add(merged);
    } finally {
      _stateRefreshInFlight = false;
      if (_stateRefreshQueued) {
        _stateRefreshQueued = false;
        _queueStateRefresh();
      }
    }
  }

  Future<void> _persistReconciledTorrent(TorrentViewState view) async {
    final existing = await TorrentsDao.instance.getTorrentById(view.id);
    if (existing == null) return;

    final updatedStatus = view.state;
    final completedAt = view.isComplete
        ? (existing.completedAt ?? DateTime.now().millisecondsSinceEpoch)
        : existing.completedAt;

    final shouldUpdate =
        existing.bytesDown != view.downloaded ||
            existing.bytesUp != view.uploaded ||
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
    for (final torrent in torrents) {
      await _getDiskSnapshot(torrent, force: force);
    }
    _queueStateRefresh(force: true);
  }

  Future<_DiskReconcileSnapshot> _getDiskSnapshot(
    TorrentModel torrent, {
    bool force = false,
  }) async {
    final cached = _diskSnapshots[torrent.id];
    if (!force &&
        cached != null &&
        DateTime.now().difference(cached.checkedAt) <
            const Duration(seconds: 45)) {
      return cached;
    }

    // Fast non-forced path: avoid expensive recursive storage scan during
    // initial state hydration. Background reconcile will correct this later.
    if (!force && cached == null) {
      final total = torrent.totalSize ?? 0;
      final bytes = torrent.bytesDown;
      final status = torrent.status?.toLowerCase() ?? '';
      final seeded = status.contains('seed');
      final done = seeded || (total > 0 && bytes >= total);
      final snap = _DiskReconcileSnapshot(
        bytesOnDisk: done && total > 0 ? total : bytes,
        isComplete: done,
        checkedAt: DateTime.now(),
      );
      _diskSnapshots[torrent.id] = snap;
      return snap;
    }

    final totalSize = torrent.totalSize ?? 0;
    final outputPath = torrent.filePath?.trim();
    if (totalSize <= 0 || outputPath == null || outputPath.isEmpty) {
      final snap = _DiskReconcileSnapshot(
        bytesOnDisk: torrent.bytesDown,
        isComplete: false,
        checkedAt: DateTime.now(),
      );
      _diskSnapshots[torrent.id] = snap;
      return snap;
    }

    final lower = outputPath.toLowerCase();
    if (lower.endsWith('.torrent')) {
      final snap = _DiskReconcileSnapshot(
        bytesOnDisk: torrent.bytesDown,
        isComplete: false,
        checkedAt: DateTime.now(),
      );
      _diskSnapshots[torrent.id] = snap;
      return snap;
    }

    var bytesOnDisk = 0;
    try {
      final entityType = await FileSystemEntity.type(outputPath);
      if (entityType == FileSystemEntityType.directory) {
        await for (final entity in Directory(outputPath).list(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is! File) continue;
          final lp = entity.path.toLowerCase();
          if (lp.endsWith('.bt.state') || lp.endsWith('.torrent')) {
            continue;
          }
          final stat = await entity.stat();
          bytesOnDisk += stat.size;
        }
      } else if (entityType == FileSystemEntityType.file) {
        final file = File(outputPath);
        final lp = file.path.toLowerCase();
        if (!lp.endsWith('.bt.state') && !lp.endsWith('.torrent')) {
          final stat = await file.stat();
          bytesOnDisk = stat.size;
        }
      }
    } catch (_) {
      // Keep last known bytes if a scan fails.
      bytesOnDisk = cached?.bytesOnDisk ?? torrent.bytesDown;
    }

    final snap = _DiskReconcileSnapshot(
      bytesOnDisk: bytesOnDisk,
      isComplete: totalSize > 0 && bytesOnDisk >= totalSize,
      checkedAt: DateTime.now(),
    );
    _diskSnapshots[torrent.id] = snap;
    return snap;
  }

  String _deriveState(String? persistedState, String? runtimeState, bool complete) {
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
    if (state.contains('download')) return 'Downloading';
    if (state.contains('pause')) return 'Paused';
    if (state.contains('pending_metadata')) return 'Pending Metadata';
    if (state.contains('queue')) return 'Queued';
    if (state.contains('error')) return 'Error';
    return state;
  }

  String _fallbackStatusMessage(String state, double progress, int peers) {
    if (state.contains('pending_metadata')) {
      return 'Waiting for peers to provide metadata...';
    }
    if (state.contains('seed')) {
      return 'Seeding • ${(progress * 100).toStringAsFixed(1)}%';
    }
    if (state.contains('pause')) {
      return 'Paused • ${(progress * 100).toStringAsFixed(1)}%';
    }
    if (state.contains('download')) {
      if (peers <= 0) {
        return 'Searching for peers...';
      }
      return 'Downloading • ${(progress * 100).toStringAsFixed(1)}% • $peers peers';
    }
    if (state.contains('error')) {
      return 'Torrent error';
    }
    return '${(progress * 100).toStringAsFixed(1)}%';
  }

  Future<void> _retryPendingMetadataIfDue(TorrentModel torrent) async {
    final status = torrent.status?.toLowerCase() ?? '';
    if (!status.contains('pending_metadata')) return;
    if (TorrentEngineService.instance.isRunning(torrent.id)) return;

    final now = DateTime.now();
    final nextTry = _pendingMetadataRetryAfter[torrent.id];
    if (nextTry != null && now.isBefore(nextTry)) return;
    _pendingMetadataRetryAfter[torrent.id] = now.add(const Duration(seconds: 90));

    try {
      await TorrentEngineService.instance.startTorrent(torrent.id);
      await updateTorrentStatus(torrent.id, 'downloading');
    } on TimeoutException {
      await updateTorrentStatus(torrent.id, 'pending_metadata');
    } catch (_) {
      // Keep pending state; retry later.
    }
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
    _queueStateRefresh(force: true);
  }

  Future<TorrentModel?> getTorrentById(String id) =>
      TorrentsDao.instance.getTorrentById(id);

  Future<void> updateTorrent(TorrentModel torrent) async {
    await TorrentsDao.instance.updateTorrent(torrent);
    _queueStateRefresh(force: true);
  }

  Future<void> removeTorrent(String id) async {
    await TorrentsDao.instance.deleteTorrent(id);
    _runtimeByTorrentId.remove(id);
    _latestStatesByTorrentId.remove(id);
    _diskSnapshots.remove(id);
    _pendingMetadataRetryAfter.remove(id);
    _queueStateRefresh(force: true);
  }

  Future<void> resumeActiveTorrents() async {
    final torrents = await allTorrents();
    final active = torrents.where((torrent) {
      final status = torrent.status?.toLowerCase() ?? '';
      // Only resume downloading/seeding torrents, not error states
      return (status == 'downloading' || status == 'seeding') &&
             !status.contains('error');
    });

    for (final torrent in active) {
      try {
        // Try to resume through the engine service
        await TorrentEngineService.instance.startTorrent(torrent.id);
      } catch (e, st) {
        debugPrint('Failed to resume torrent ${torrent.id}: $e');
        debugPrint(st.toString());
        // Update status to error so we don't keep retrying forever
        await updateTorrentStatus(torrent.id, 'error_resume_failed');
      }
    }
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
    if (existing == null) {
      throw StateError('Torrent not found: $id');
    }

    bool shouldDelete = existing.deleteAfterRatioReached;
    String updatedStatus = existing.status ?? 'downloading';

    if (existing.maxSeedRatio != null && existing.maxSeedRatio! > 0) {
      final ratio = existing.bytesDown > 0 ? bytesUp / existing.bytesDown : 0.0;
      if (ratio >= existing.maxSeedRatio!) {
        updatedStatus = 'seed_ratio_reached';
        if (existing.deleteAfterRatioReached) {
          shouldDelete = true;
        }
      }
    }

    final updated = TorrentModel(
      id: existing.id,
      name: existing.name,
      type: existing.type,
      totalSize: existing.totalSize,
      totalPieces: existing.totalPieces,
      pieceLength: existing.pieceLength,
      piecesHave: existing.piecesHave,
      status: updatedStatus,
      vaultKey: existing.vaultKey,
      filePath: existing.filePath,
      vaultLink: existing.vaultLink,
      magnetLink: existing.magnetLink,
      bytesDown: bytesDown,
      bytesUp: bytesUp,
      addedAt: existing.addedAt,
      completedAt: existing.completedAt,
      isSequential: existing.isSequential,
      selectedFiles: existing.selectedFiles,
      maxSeedRatio: existing.maxSeedRatio,
      deleteAfterRatioReached: shouldDelete,
    );

    await TorrentsDao.instance.updateTorrent(updated);
    _queueStateRefresh();

    if (shouldDelete && updatedStatus == 'seed_ratio_reached') {
      await TorrentsDao.instance.deleteTorrent(id);
      _runtimeByTorrentId.remove(id);
      _latestStatesByTorrentId.remove(id);
      _diskSnapshots.remove(id);
      _pendingMetadataRetryAfter.remove(id);
      _queueStateRefresh(force: true);
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
      TorrentEngineService.instance.stopTorrent(id);
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
      isSequential: false,
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
      isSequential: false,
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
        _pendingMetadataRetryAfter[infoHash] =
            DateTime.now().add(const Duration(seconds: 90));
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