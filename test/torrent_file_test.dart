import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_the_spire/bittorrent/bencode.dart';
import 'package:vault_the_spire/bittorrent/torrent_file.dart';
import 'package:vault_the_spire/services/torrent_service.dart';

void main() {
  test('parse simple single-file torrent', () {
    final info = {
      'name': 'test.txt',
      'piece length': 16384,
      'pieces': Uint8List.fromList(List.generate(20, (i) => i)),
      'length': 12345,
    };

    final torrentMap = {'info': info};

    final data = bencode(torrentMap);
    final metadata = TorrentFileParser.parse(data);

    expect(metadata.name, 'test.txt');
    expect(metadata.pieceLength, 16384);
    expect(metadata.files.length, 1);
    expect(metadata.files.first.path, 'test.txt');
    expect(metadata.files.first.length, 12345);
    expect(metadata.pieceHashes.length, 1);
  });

  test('create magnet link with trackers', () {
    const infoHash = '0123456789abcdef0123456789abcdef01234567';
    const name = 'Example File';
    final trackers = [
      'http://tracker1.example/announce',
      'udp://tracker2.example:80/announce',
    ];

    final magnet = TorrentService.createMagnetLink(infoHash, name, trackers);

    expect(magnet, startsWith('magnet:?xt=urn:btih:$infoHash'));
    expect(magnet.contains('dn=Example%20File'), isTrue);
    expect(
      magnet.contains('tr=http%3A%2F%2Ftracker1.example%2Fannounce'),
      isTrue,
    );
    expect(
      magnet.contains('tr=udp%3A%2F%2Ftracker2.example%3A80%2Fannounce'),
      isTrue,
    );
  });
}
