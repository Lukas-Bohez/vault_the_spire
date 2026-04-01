import 'package:flutter_test/flutter_test.dart';
import 'package:vault_the_spire/models/torrent.dart';
import 'package:vault_the_spire/services/search_service.dart';
import 'package:vault_the_spire/services/torrent_context.dart';

void main() {
  test('getContext returns required empty-state strings', () {
    final context = TorrentContextService();

    final text = context.getContext();

    expect(text, contains('No active search.'));
    expect(text, contains('No torrent selected.'));
    expect(text, contains('No active downloads.'));
    expect(text, contains('Library is empty.'));
  });

  test('getContext includes populated values', () {
    final context = TorrentContextService();
    context.updateQuery('ubuntu iso');
    context.updateCategory('Software');
    context.updateSelected(
      SearchResult(
        torrentId: 't1',
        name: 'Ubuntu',
        magnetLink: 'magnet:?xt=urn:btih:abc',
        responderId: 'peer1',
        source: 'tracker-x',
        size: 1024,
      ),
    );
    context.updateTorrents([
      TorrentModel(
        id: 'a',
        name: 'Active',
        type: 'magnet',
        status: 'downloading',
        totalSize: 100,
        bytesDown: 50,
      ),
      TorrentModel(id: 'c', name: 'Done', type: 'magnet', status: 'completed'),
    ]);

    final text = context.getContext();

    expect(text, contains('ubuntu iso'));
    expect(text, contains('Ubuntu'));
    expect(text, contains('Active (50.0%)'));
    expect(text, contains('Done'));
  });
}
