import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vault_the_spire/services/settings_service.dart';
import 'package:vault_the_spire/services/torrent_engine_service.dart';
import 'package:vault_the_spire/services/torrent_service.dart';

void main() {
  test('isTorrentOrMagnetUrl identifies magnet and torrent URLs', () {
    expect(TorrentService.isTorrentOrMagnetUrl('magnet:?xt=urn:btih:abc'), isTrue);
    expect(TorrentService.isTorrentOrMagnetUrl('http://example.com/file.torrent'), isTrue);
    expect(TorrentService.isTorrentOrMagnetUrl('file:///tmp/foo.torrent'), isTrue);
    expect(TorrentService.isTorrentOrMagnetUrl('https://example.com/'), isFalse);
    expect(TorrentService.isTorrentOrMagnetUrl('just some text'), isFalse);
  });

  test('TorrentEngineStatus has peers and can report peer count', () {
    final status = TorrentEngineStatus(
      torrentId: 'test',
      downloaded: 1024,
      uploaded: 512,
      progress: 0.5,
      state: 'downloading',
      peers: 3,
      dhtNodes: 4,
      seeders: 1,
      leechers: 2,
      downloadSpeed: 1234,
      uploadSpeed: 567,
      statusMessage: 'downloading',
    );

    expect(status.peers, equals(3));
    expect(status.seeders, equals(1));
  });

  test('SettingsService can persist browser favorites through SharedPreferences', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    const favorites = ['https://example.com', 'https://dart.dev'];
    await SettingsService.instance.setBrowserFavorites(favorites);

    final prefs = await SharedPreferences.getInstance();
    final persisted = prefs.getStringList('browser_favorites');

    expect(persisted, isNotNull);
    expect(persisted, equals(favorites));

    // Reload from prefs into instance to validate load() behavior.
    SettingsService.instance.browserFavorites = [];
    await SettingsService.instance.load();
    expect(SettingsService.instance.browserFavorites, equals(favorites));
  });

  test('normalizeTorrentUrl preserves magnet and local torrent and adds scheme for plain URLs', () {
    expect(TorrentService.normalizeTorrentUrl('magnet:?xt=urn:btih:abc'), 'magnet:?xt=urn:btih:abc');
    expect(TorrentService.normalizeTorrentUrl('file:///tmp/foo.torrent'), 'file:///tmp/foo.torrent');
    expect(TorrentService.normalizeTorrentUrl('http://example.com/file.torrent'), 'http://example.com/file.torrent');
    expect(TorrentService.normalizeTorrentUrl('example.com'), 'https://example.com');
    expect(TorrentService.normalizeTorrentUrl('  '), '');
  });
}
