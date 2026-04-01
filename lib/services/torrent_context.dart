import 'package:flutter/foundation.dart';
import 'package:vault_the_spire/models/torrent.dart';
import 'package:vault_the_spire/services/search_service.dart';

class TorrentContextService extends ChangeNotifier {
  String currentQuery = '';
  String category = 'All';
  SearchResult? selectedResult;
  List<TorrentModel> activeDownloads = const <TorrentModel>[];
  List<TorrentModel> library = const <TorrentModel>[];

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
      return status.contains('download') || status.contains('seed') || status.contains('queued');
    }).toList();

    library = all.where((t) {
      final status = (t.status ?? '').toLowerCase();
      return status.contains('complete');
    }).toList();
    notifyListeners();
  }

  String getContext() {
    final selected = selectedResult;
    final selectedText = selected == null
        ? 'None'
        : '${selected.name} | size: ${selected.size ?? 0} bytes | seeders: unknown | leechers: unknown | source: ${selected.responderId} | category: $category';

    final active = activeDownloads.isEmpty
        ? 'None'
        : activeDownloads
            .map((t) => '${t.name} (${_pct(t)}%)')
            .join(', ');

    final completed = library.isEmpty
        ? 'None'
        : library.map((t) => t.name).join(', ');

    return 'Current torrent search query: ${currentQuery.isEmpty ? 'None' : currentQuery}\n'
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
