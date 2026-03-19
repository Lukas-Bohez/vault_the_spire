import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_the_spire/vault_swarm/vault_link.dart';
import 'package:vault_the_spire/vault_swarm/vault_piece.dart';

void main() {
  test('VaultLink parse and serialize', () {
    final key = base64Url.encode(Uint8List.fromList(List.filled(32, 1)));
    final infoHash =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
    final uri = 'vault://$infoHash#$key';

    final link = VaultLink.parse(uri);
    expect(link.infoHash, infoHash);
    expect(link.keyBase64, key);
    expect(link.toUri(), uri);

    final magnet = link.toMagnetUri();
    expect(magnet.startsWith('magnet:?xt=urn:btmh:1220$infoHash'), isTrue);
  });

  test('VaultPiece encrypt/decrypt/hash', () {
    final piece = Uint8List.fromList(List.generate(100, (i) => i));
    final key = Uint8List.fromList(List.filled(32, 7));

    final encrypted = VaultPiece.encryptPiece(piece, key);
    final decrypted = VaultPiece.decryptPiece(encrypted, key);
    expect(decrypted, piece);

    final hash = VaultPiece.pieceHash(piece);
    final expected = sha256.convert(piece).bytes;
    expect(hash, Uint8List.fromList(expected));
  });
}
