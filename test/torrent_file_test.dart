import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_the_spire/bittorrent/bencode.dart';
import 'package:vault_the_spire/bittorrent/torrent_file.dart';

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
}
