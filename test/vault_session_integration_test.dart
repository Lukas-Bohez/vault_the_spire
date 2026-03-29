import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vault_the_spire/bittorrent/piece_manager.dart';
// import 'package:vault_the_spire/bittorrent/torrent_file.dart';
import 'package:vault_the_spire/bittorrent/torrent_session.dart';
// import 'package:vault_the_spire/bittorrent/dht.dart';
import 'package:vault_the_spire/vault_swarm/vault_piece.dart';
import 'package:vault_the_spire/vault_swarm/vault_session.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vault_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('TorrentSession writes and reads pieces', () async {
    final infoHash = 'abcd1234abcd1234abcd1234abcd1234abcd1234';
    final pieceManager = PieceManager(
      infoHash: infoHash,
      pieceLength: 2,
      totalPieces: 1,
      appDirectory: tempDir,
    );
    await pieceManager.initialize();
    final session = TorrentSession(
      infoHash: infoHash,
      name: 'test',
      trackers: [],
      totalSize: 2,
      pieceLength: 2,
      totalPieces: 1,
      pieceHashesHex: ['00' * 20],
    );
    await pieceManager.writePiece(0, Uint8List.fromList([1, 2]));
    final stored = await pieceManager.readPiece(0);
    expect(stored, isNotNull);
    expect(stored, Uint8List.fromList([1, 2]));
  });

  test('VaultSession decrypts piece on receive', () async {
    final infoHash = 'abcd1234abcd1234abcd1234abcd1234abcd1234';
    final pieceManager = PieceManager(
      infoHash: infoHash,
      pieceLength: 2,
      totalPieces: 1,
      appDirectory: tempDir,
    );
    await pieceManager.initialize();
    final vaultKey = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final session = VaultSession(
      link: null as dynamic, // Not used in this test
      key: vaultKey,
      infoHash: infoHash,
      name: 'vault',
      trackers: [],
      totalSize: 2,
      pieceLength: 2,
      totalPieces: 1,
      pieceHashesHex: ['00' * 20],
      appDirectory: tempDir,
    );
    final encryptedPiece = VaultPiece.encryptPiece(
      Uint8List.fromList([5, 6]),
      vaultKey,
    );
    await session.onPieceReceived(0, encryptedPiece);
    final stored = await pieceManager.readPiece(0);
    expect(stored, isNotNull);
    expect(stored, Uint8List.fromList([5, 6]));
  });
}
