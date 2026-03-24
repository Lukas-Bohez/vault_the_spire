import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vault_the_spire/bittorrent/piece_manager.dart';
import 'package:vault_the_spire/bittorrent/torrent_file.dart';
import 'package:vault_the_spire/bittorrent/torrent_session.dart';
import 'package:vault_the_spire/bittorrent/dht.dart';
import 'package:vault_the_spire/vault_swarm/vault_piece.dart';

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

  test('StandardTorrentSession writes and reads pieces', () async {
    final metadata = TorrentMetadata(
      infoHashV1: 'abcd1234abcd1234abcd1234abcd1234abcd1234',
      infoHashV2: null,
      name: 'test',
      pieceLength: 2,
      pieceHashes: [],
      files: [],
      trackers: [],
      webSeeds: [],
    );
    final pieceManager = PieceManager(
      infoHash: metadata.infoHashV1,
      pieceLength: 2,
      totalPieces: 1,
      appDirectory: tempDir,
    );
    await pieceManager.initialize();
    final dhtEngine = DhtEngine(DhtRoutingTable(DhtEngine.generateNodeId()));

    final session = StandardTorrentSession(
      metadata: metadata,
      pieceManager: pieceManager,
      dhtEngine: dhtEngine,
    );

    await session.onPieceReceived(0, Uint8List.fromList([1, 2]));
    final stored = await pieceManager.readPiece(0);

    expect(stored, isNotNull);
    expect(stored, Uint8List.fromList([1, 2]));
  });

  test('VaultTorrentSession decrypts piece on receive', () async {
    final metadata = TorrentMetadata(
      infoHashV1: 'abcd1234abcd1234abcd1234abcd1234abcd1234',
      infoHashV2: null,
      name: 'vault',
      pieceLength: 2,
      pieceHashes: [],
      files: [],
      trackers: [],
      webSeeds: [],
    );
    final pieceManager = PieceManager(
      infoHash: metadata.infoHashV1,
      pieceLength: 2,
      totalPieces: 1,
      appDirectory: tempDir,
    );
    await pieceManager.initialize();

    // vault key is 32 bytes, but decrypt is identity in this variant (from existing vault_piece). 
    final vaultKey = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final session = VaultTorrentSession(
      metadata: metadata,
      key: vaultKey,
      pieceManager: pieceManager,
      dhtEngine: DhtEngine(DhtRoutingTable(DhtEngine.generateNodeId())),
    );

    // Encrypt the input first, because VaultSession.decryptPiece expects an encrypted payload.
    final encryptedPiece = VaultPiece.encryptPiece(Uint8List.fromList([5, 6]), vaultKey);
    await session.onPieceReceived(0, encryptedPiece);
    final stored = await pieceManager.readPiece(0);

    expect(stored, isNotNull);
    expect(stored, Uint8List.fromList([5, 6]));
  });
}
