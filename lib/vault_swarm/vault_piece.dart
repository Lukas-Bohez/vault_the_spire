import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class VaultPiece {
  final int index;
  final Uint8List encryptedData;

  VaultPiece({required this.index, required this.encryptedData});

  static Uint8List encryptPiece(Uint8List piece, Uint8List key) {
    if (key.length != 32) {
      throw ArgumentError('Key must be 32 bytes for AES-256');
    }
    // Placeholder: use simple XOR for now (to avoid crypto libs complexity in base)
    final encrypted = Uint8List(piece.length);
    for (var i = 0; i < piece.length; i++) {
      encrypted[i] = piece[i] ^ key[i % key.length];
    }
    return encrypted;
  }

  static Uint8List decryptPiece(Uint8List encryptedPiece, Uint8List key) {
    return encryptPiece(encryptedPiece, key);
  }

  static Uint8List pieceHash(Uint8List piece) {
    final bytes = sha256.convert(piece).bytes;
    return Uint8List.fromList(bytes);
  }

  String pieceHashHex(Uint8List piece) =>
      pieceHash(piece).map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
