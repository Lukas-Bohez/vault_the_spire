import 'dart:typed_data';

class PeerWireMessage {
  final int? id; // null for keep-alive
  final Uint8List payload;

  PeerWireMessage._(this.id, this.payload);

  factory PeerWireMessage.keepAlive() => PeerWireMessage._(null, Uint8List(0));

  factory PeerWireMessage.choke() => PeerWireMessage._(0, Uint8List(0));
  factory PeerWireMessage.unchoke() => PeerWireMessage._(1, Uint8List(0));
  factory PeerWireMessage.interested() => PeerWireMessage._(2, Uint8List(0));
  factory PeerWireMessage.notInterested() => PeerWireMessage._(3, Uint8List(0));
  factory PeerWireMessage.have(int pieceIndex) {
    final p = ByteData(4);
    p.setUint32(0, pieceIndex);
    return PeerWireMessage._(4, p.buffer.asUint8List());
  }

  factory PeerWireMessage.bitfield(Uint8List bitfield) =>
      PeerWireMessage._(5, bitfield);

  factory PeerWireMessage.request(int index, int begin, int length) {
    final p = ByteData(12);
    p.setUint32(0, index);
    p.setUint32(4, begin);
    p.setUint32(8, length);
    return PeerWireMessage._(6, p.buffer.asUint8List());
  }

  factory PeerWireMessage.piece(int index, int begin, Uint8List block) {
    final p = ByteData(8 + block.length);
    p.setUint32(0, index);
    p.setUint32(4, begin);
    p.buffer.asUint8List().setRange(8, 8 + block.length, block);
    return PeerWireMessage._(7, p.buffer.asUint8List());
  }

  factory PeerWireMessage.cancel(int index, int begin, int length) {
    final p = ByteData(12);
    p.setUint32(0, index);
    p.setUint32(4, begin);
    p.setUint32(8, length);
    return PeerWireMessage._(8, p.buffer.asUint8List());
  }

  factory PeerWireMessage.port(int listenPort) {
    final p = ByteData(2);
    p.setUint16(0, listenPort);
    return PeerWireMessage._(9, p.buffer.asUint8List());
  }

  bool get isKeepAlive => id == null;

  Uint8List encode() {
    if (isKeepAlive) {
      return Uint8List.fromList([0, 0, 0, 0]);
    }

    final payloadLength = payload.length;
    final buffer = ByteData(4 + 1 + payloadLength);
    buffer.setUint32(0, payloadLength + 1);
    buffer.setUint8(4, id!);
    if (payloadLength > 0) {
      buffer.buffer.asUint8List().setRange(5, 5 + payloadLength, payload);
    }
    return buffer.buffer.asUint8List();
  }

  static PeerWireMessage decode(Uint8List data) {
    if (data.length < 4) {
      throw FormatException('Message too short for length prefix');
    }
    final len = ByteData.sublistView(data, 0, 4).getUint32(0);
    if (len == 0) {
      return PeerWireMessage.keepAlive();
    }
    if (data.length < 4 + len) {
      throw FormatException('Incomplete message');
    }

    final id = data[4];
    final payload = data.sublist(5, 4 + len);
    return PeerWireMessage._(id, payload);
  }

  static const String protocolString = 'BitTorrent protocol';

  static Uint8List buildHandshake(
    Uint8List infoHash,
    Uint8List peerId, [
    Uint8List? reserved,
  ]) {
    if (infoHash.length != 20) throw ArgumentError('infoHash must be 20 bytes');
    if (peerId.length != 20) throw ArgumentError('peerId must be 20 bytes');

    final reservedBytes = reserved ?? Uint8List(8);
    if (reservedBytes.length != 8) {
      throw ArgumentError('reserved must be 8 bytes');
    }

    final pstr = protocolString;
    final out = Uint8List(1 + pstr.length + 8 + 20 + 20);
    out[0] = pstr.length;
    out.setRange(1, 1 + pstr.length, pstr.codeUnits);
    out.setRange(1 + pstr.length, 1 + pstr.length + 8, reservedBytes);
    out.setRange(1 + pstr.length + 8, 1 + pstr.length + 8 + 20, infoHash);
    out.setRange(1 + pstr.length + 8 + 20, out.length, peerId);
    return out;
  }

  static bool isHandshake(Uint8List data) {
    if (data.isEmpty) return false;
    final pstrlen = data[0];
    if (data.length < 49 + pstrlen) return false;
    final pstrCandidate = String.fromCharCodes(data.sublist(1, 1 + pstrlen));
    return pstrCandidate == protocolString;
  }

  static Handshake parseHandshake(Uint8List data) {
    if (!isHandshake(data)) throw FormatException('Invalid handshake');

    final pstrlen = data[0];
    final reservedStart = 1 + pstrlen;
    final infoHashStart = reservedStart + 8;
    final peerIdStart = infoHashStart + 20;

    final reserved = data.sublist(reservedStart, reservedStart + 8);
    final infoHash = data.sublist(infoHashStart, infoHashStart + 20);
    final peerId = data.sublist(peerIdStart, peerIdStart + 20);

    return Handshake(reserved: reserved, infoHash: infoHash, peerId: peerId);
  }
}

class Handshake {
  final Uint8List reserved;
  final Uint8List infoHash;
  final Uint8List peerId;

  Handshake({
    required this.reserved,
    required this.infoHash,
    required this.peerId,
  });
}
