import 'package:flutter/foundation.dart';
import 'package:vault_the_spire/models/torrent.dart';
import 'package:vault_the_spire/services/search_service.dart';
import 'package:vault_the_spire/services/torrent_engine_service.dart';

class TorrentContextService extends ChangeNotifier {
  String currentQuery = '';
  String category = 'All';
  SearchResult? selectedResult;
  List<TorrentModel> activeDownloads = const <TorrentModel>[];
  List<TorrentModel> library = const <TorrentModel>[];
  final Map<String, TorrentEngineStatus> _runtimeStatusById =
      <String, TorrentEngineStatus>{};

  void updateQuery(String value) {
    currentQuery = value;
    notifyListeners();
  }

  void updateCategory(String value) {
    category = value;
    notifyListeners();
  }

  void updateSelected(SearchResult? result) {
    selectedResult = result;
    notifyListeners();
  }

  void updateTorrents(List<TorrentModel> all) {
    activeDownloads = all.where((t) {
      final status = (t.status ?? '').toLowerCase();
      return status.contains('download') ||
          status.contains('seed') ||
          status.contains('queued');
    }).toList();

    library = all.where((t) {
      final status = (t.status ?? '').toLowerCase();
      return status.contains('complete');
    }).toList();
    notifyListeners();
  }

  void updateRuntimeStatus(TorrentEngineStatus status) {
    if (status.torrentId.isEmpty) return;
    _runtimeStatusById[status.torrentId] = status;
    notifyListeners();
  }

  String getContext() {
    final selected = selectedResult;
    final selectedText = selected == null
        ? 'No torrent selected.'
      : '${selected.name} | size: ${selected.size ?? 0} bytes | '
          'seeders: ${selected.seeders?.toString() ?? 'unknown'} | '
          'leechers: ${selected.leechers?.toString() ?? 'unknown'} | '
          'source: ${selected.source.isEmpty ? selected.responderId : selected.source} | '
          'category: $category';

    final active = activeDownloads.isEmpty
        ? 'No active downloads.'
      : activeDownloads.map((t) {
        final runtime = _runtimeStatusById[t.id];
        final progress = runtime == null
          ? '${_pct(t)}%'
          : runtime.state.toLowerCase().contains('seed')
          ? '${(runtime.seedingProgress * 100).toStringAsFixed(1)}% seeded-back'
          : '${(runtime.progress * 100).toStringAsFixed(1)}%';
        final peers = runtime?.peers ?? 0;
        final seeders = runtime?.seeders ?? t.seeders;
        final leechers = runtime?.leechers ?? t.leechers;
        final state = runtime?.state ?? t.status ?? 'unknown';
        return '${t.name} [$state] $progress | peers: $peers | seeders: $seeders | leechers: $leechers';
        }).join(', ');

    final completed = library.isEmpty
        ? 'Library is empty.'
        : library.map((t) => t.name).join(', ');

    final queryText = currentQuery.isEmpty ? 'No active search.' : currentQuery;

    return 'Current torrent search query: $queryText\n'
        'Selected torrent: $selectedText\n'
        'Active downloads: $active\n'
        'Library contents: $completed';
  }

  String _pct(TorrentModel torrent) {
    if (torrent.totalSize == null || torrent.totalSize == 0) return '0.0';
    final value = (torrent.bytesDown / torrent.totalSize!) * 100;
    return value.clamp(0, 100).toStringAsFixed(1);
  }
}
