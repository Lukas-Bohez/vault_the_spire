import 'package:flutter_test/flutter_test.dart';
import 'package:vault_the_spire/bittorrent/magnet_link.dart';

void main() {
  test('parse magnet link v1', () {
    const uri =
        'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=Test';
    final link = MagnetLink.parse(uri);
    expect(link.infoHashV1, '0123456789abcdef0123456789abcdef01234567');
    expect(link.displayName, 'Test');
  });

  test('parse magnet link v2', () {
    const uri =
        'magnet:?xt=urn:btmh:12200123456789abcdef0123456789abcdef0123456789abcdef0123456789abcd';
    final link = MagnetLink.parse(uri);
    expect(
      link.infoHashV2,
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcd',
    );
  });

  test('toUri roundtrip', () {
    final link = MagnetLink(
      infoHashV1: '0123456789abcdef0123456789abcdef01234567',
      displayName: 'Hello',
      trackers: ['udp://tracker.example.com:80'],
    );
    final uri = link.toUri();
    expect(
      uri.contains('xt=urn:btih:0123456789abcdef0123456789abcdef01234567'),
      isTrue,
    );
    expect(uri.contains('dn=Hello'), isTrue);
    expect(uri.contains('tr=udp%3A%2F%2Ftracker.example.com%3A80'), isTrue);
  });
}
