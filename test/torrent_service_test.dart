import 'package:flutter_test/flutter_test.dart';
import 'package:vault_the_spire/services/torrent_service.dart';

void main() {
  test('isTorrentOrMagnetUrl identifies magnet and torrent URLs', () {
    expect(TorrentService.isTorrentOrMagnetUrl('magnet:?xt=urn:btih:abc'), isTrue);
    expect(TorrentService.isTorrentOrMagnetUrl('http://example.com/file.torrent'), isTrue);
    expect(TorrentService.isTorrentOrMagnetUrl('file:///tmp/foo.torrent'), isTrue);
    expect(TorrentService.isTorrentOrMagnetUrl('https://example.com/'), isFalse);
    expect(TorrentService.isTorrentOrMagnetUrl('just some text'), isFalse);
  });

  test('normalizeTorrentUrl preserves magnet and local torrent and adds scheme for plain URLs', () {
    expect(TorrentService.normalizeTorrentUrl('magnet:?xt=urn:btih:abc'), 'magnet:?xt=urn:btih:abc');
    expect(TorrentService.normalizeTorrentUrl('file:///tmp/foo.torrent'), 'file:///tmp/foo.torrent');
    expect(TorrentService.normalizeTorrentUrl('http://example.com/file.torrent'), 'http://example.com/file.torrent');
    expect(TorrentService.normalizeTorrentUrl('example.com'), 'https://example.com');
    expect(TorrentService.normalizeTorrentUrl('  '), '');
  });
}
