import 'dart:io';
// import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vault_the_spire/bittorrent/torrent_session.dart';

void main() {
  test('TorrentSession emits status updates', () async {
    final tempDir = await Directory.systemTemp.createTemp('vault_ts');
    final session = TorrentSession(
      infoHash: '0123456789abcdef0123456789abcdef01234567',
      name: 'test',
      trackers: [],
      totalSize: 16384,
      pieceLength: 16384,
      totalPieces: 1,
      pieceHashesHex: List.generate(1, (i) => '00' * 20),
    );
    final statuses = <TorrentStatus>[];
    final sub = session.statusStream.listen(statuses.add);
    await session.start();
    await Future.delayed(const Duration(milliseconds: 200));
    expect(statuses.isNotEmpty, isTrue);
    expect(statuses.last.name, 'test');
    await sub.cancel();
    await tempDir.delete(recursive: true);
  });
}
