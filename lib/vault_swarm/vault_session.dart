import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:vault_the_spire/bittorrent/dht.dart';
import 'package:vault_the_spire/bittorrent/piece_manager.dart';
import 'package:vault_the_spire/vault_swarm/vault_link.dart';
import 'package:vault_the_spire/vault_swarm/vault_piece.dart';

class VaultSession {
  final VaultLink link;
  final Uint8List key;
  final PieceManager pieceManager;

  VaultSession._(this.link, this.key, this.pieceManager);

  static Future<VaultSession> createFromVaultLink(
    String vaultUri,
    Directory appDirectory,
    int totalPieces,
    int pieceLength,
    DhtEngine dhtEngine,
  ) async {
    final link = VaultLink.parse(vaultUri);
    final decodedKey = base64Url.decode(link.keyBase64);
    if (decodedKey.length != 32) {
      throw ArgumentError('vault key invalid length');
    }
    final manager = PieceManager(
      infoHash: link.infoHash,
      pieceLength: pieceLength,
      totalPieces: totalPieces,
      appDirectory: appDirectory,
    );
    await manager.initialize();
    return VaultSession._(link, decodedKey, manager);
  }

  Future<void> storeEncryptedPiece(int index, Uint8List encryptedPiece) async {
    await pieceManager.writePiece(index, encryptedPiece);
  }

  Future<Uint8List?> fetchDecryptedPiece(int index) async {
    final enc = await pieceManager.readPiece(index);
    if (enc == null) return null;
    return VaultPiece.decryptPiece(enc, key);
  }

  Future<bool> verifyPiece(int index, Uint8List expectedHash) async {
    final piece = await pieceManager.readPiece(index);
    if (piece == null) return false;
    final hash = VaultPiece.pieceHash(piece);
    return ListEquality().equals(hash, expectedHash);
  }
}
