import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_the_spire/bittorrent/piece_manager.dart';

void main() {
  test('piece manager write/read/verify clear operations', () async {
    final tempDir = await Directory.systemTemp.createTemp(
      'vault_the_spire_test',
    );
    final manager = PieceManager(
      infoHash: 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
      pieceLength: 16384,
      totalPieces: 10,
      appDirectory: tempDir,
    );
    await manager.initialize();

    final piece = Uint8List.fromList(List<int>.generate(100, (i) => i % 256));
    await manager.writePiece(0, piece);

    expect(await manager.hasPiece(0), isTrue);

    final read = await manager.readPiece(0);
    expect(read, piece);

    final hash = sha1.convert(piece).bytes;
    expect(await manager.verifyPiece(0, hash), isTrue);

    await manager.removePiece(0);
    expect(await manager.hasPiece(0), isFalse);

    await manager.clearAll();
    expect(await manager.hasPiece(0), isFalse);
    await tempDir.delete(recursive: true);
  });
}
