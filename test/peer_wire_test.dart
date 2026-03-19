import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vault_the_spire/bittorrent/peer_wire.dart';

void main() {
  test('handshake encode/decode works', () {
    final infoHash = Uint8List.fromList(List.filled(20, 1));
    final peerId = Uint8List.fromList(List.filled(20, 2));

    final handshake = PeerWireMessage.buildHandshake(infoHash, peerId);
    expect(PeerWireMessage.isHandshake(handshake), isTrue);

    final parsed = PeerWireMessage.parseHandshake(handshake);
    expect(parsed.infoHash, infoHash);
    expect(parsed.peerId, peerId);
  });

  test('peer wire keepalive encode/decode', () {
    final msg = PeerWireMessage.keepAlive();
    final encoded = msg.encode();
    expect(encoded, Uint8List.fromList([0, 0, 0, 0]));

    final decoded = PeerWireMessage.decode(encoded);
    expect(decoded.isKeepAlive, isTrue);
  });

  test('have message encode/decode', () {
    final msg = PeerWireMessage.have(123);
    final encoded = msg.encode();
    final decoded = PeerWireMessage.decode(encoded);

    expect(decoded.id, 4);
    expect(decoded.payload.length, 4);
    final index = ByteData.sublistView(decoded.payload).getUint32(0);
    expect(index, 123);
  });

  test('piece message encode/decode', () {
    final block = Uint8List.fromList([1, 2, 3, 4]);
    final msg = PeerWireMessage.piece(1, 2, block);
    final decoded = PeerWireMessage.decode(msg.encode());

    expect(decoded.id, 7);
    expect(decoded.payload.length, 12); // 4 index + 4 begin + 4 block
    expect(decoded.payload.sublist(8), block);
  });
}
