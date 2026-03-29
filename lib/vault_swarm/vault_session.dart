import 'dart:typed_data';

import 'dart:io';

import 'package:collection/collection.dart';
import 'package:vault_the_spire/bittorrent/piece_manager.dart';
import 'package:vault_the_spire/bittorrent/torrent_session.dart';
import 'package:vault_the_spire/vault_swarm/vault_link.dart';
import 'package:vault_the_spire/vault_swarm/vault_piece.dart';


class VaultSession extends TorrentSession {
  final VaultLink link;
  final Uint8List key;
  final PieceManager pieceManager;

  VaultSession({
    required this.link,
    required this.key,
    required String infoHash,
    required String name,
    required List<String> trackers,
    required int totalSize,
    required int pieceLength,
    required int totalPieces,
    required List<String> pieceHashesHex,
    required Directory appDirectory,
  })  : pieceManager = PieceManager(
          infoHash: infoHash,
          pieceLength: pieceLength,
          totalPieces: totalPieces,
          appDirectory: appDirectory,
        ),
        super(
          infoHash: infoHash,
          name: name,
          trackers: trackers,
          totalSize: totalSize,
          pieceLength: pieceLength,
          totalPieces: totalPieces,
          pieceHashesHex: pieceHashesHex,
        );

  Future<void> onPieceReceived(int index, Uint8List data) async {
    final decryptedPiece = VaultPiece.decryptPiece(data, key);
    await pieceManager.writePiece(index, decryptedPiece);
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
