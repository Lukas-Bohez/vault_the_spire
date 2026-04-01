import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

class PieceManager {
  final String infoHash;
  final int pieceLength;
  final int totalPieces;
  final Directory baseDir;

  PieceManager({
    required this.infoHash,
    required this.pieceLength,
    required this.totalPieces,
    required Directory appDirectory,
  }) : baseDir = Directory(
         path.join(appDirectory.path, 'torrent_pieces', infoHash),
       );

  Future<void> initialize() async {
    if (!await baseDir.exists()) {
      await baseDir.create(recursive: true);
    }
  }

  File _pieceFile(int index) {
    return File(path.join(baseDir.path, 'piece_$index.part'));
  }

  Future<void> writePiece(int index, Uint8List data) async {
    if (index < 0 || index >= totalPieces) {
      throw RangeError.index(
        index,
        null,
        'index',
        'Piece index out of bounds',
        totalPieces,
      );
    }
    if (data.length > pieceLength) {
      throw ArgumentError.value(
        data.length,
        'data.length',
        'piece payload too large',
      );
    }
    final file = _pieceFile(index);
    await file.writeAsBytes(data, flush: true);
  }

  Future<bool> savePiece(int index, Uint8List data) async {
    await writePiece(index, data);
    // In a real implementation, verify hash here
    return true;
  }

  Future<bool> hasPiece(int index) async {
    final file = _pieceFile(index);
    return file.exists();
  }

  Future<Uint8List?> readPiece(int index) async {
    final file = _pieceFile(index);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return bytes;
  }

  Future<bool> verifyPiece(int index, List<int> expectedHash) async {
    final piece = await readPiece(index);
    if (piece == null) return false;

    final hash = sha1.convert(piece).bytes;
    if (hash.length != expectedHash.length) return false;
    for (var i = 0; i < hash.length; i++) {
      if (hash[i] != expectedHash[i]) return false;
    }
    return true;
  }

  Future<List<bool>> getPieceMap() async {
    final results = <bool>[];
    for (var i = 0; i < totalPieces; i++) {
      results.add(await hasPiece(i));
    }
    return results;
  }

  Future<void> removePiece(int index) async {
    final file = _pieceFile(index);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> clearAll() async {
    if (await baseDir.exists()) {
      await baseDir.delete(recursive: true);
    }
    await initialize();
  }
}
