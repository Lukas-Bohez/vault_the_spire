import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vault_the_spire/bittorrent/bencode.dart';
import 'package:vault_the_spire/bittorrent/dht.dart';
import 'package:vault_the_spire/bittorrent/torrent_session.dart';

void main() {
  test('Open simple torrent session from torrent data', () async {
    final tempDir = await Directory.systemTemp.createTemp('vault_ts');
    final dht = DhtEngine(DhtRoutingTable(DhtEngine.generateNodeId()));

    final infoDict = {
      'name': 'test',
      'piece length': 16384,
      'pieces': Uint8List.fromList(List.generate(20, (i) => i)),
      'length': 12345,
    };

    final torrentMap = {'info': infoDict};
    final torrentBytes = bencode(torrentMap);

    final session = await TorrentSession.openFromTorrentFile(
      torrentBytes,
      tempDir,
      dht,
    );
    expect(session.metadata.name, 'test');

    final statuses = <TorrentStatus>[];
    final sub = session.statusStream.listen(statuses.add);

    await session.start();
    await Future.delayed(const Duration(milliseconds: 200));

    expect(statuses.isNotEmpty, isTrue);
    expect(statuses.last.state, 'idle');

    await sub.cancel();
    session.dispose();
    await tempDir.delete(recursive: true);
  });
}
