import 'dart:async';
import 'dart:io';
// import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';
import 'piece_manager.dart';
import 'package:flutter/foundation.dart';

enum PeerMessageType {
  choke,
  unchoke,
  interested,
  notInterested,
  have,
  bitfield,
  request,
  piece,
  cancel,
  port,
  handshake,
  keepAlive,
}

class PeerConnection {
  final String ip;
  final int port;
  final Uint8List infoHash;
  final Uint8List peerId;
  final int totalPieces;
  final int pieceLength;
  final int totalSize;
  final PieceManager pieceManager;
  final void Function(int pieceIndex, int bytes) onPieceDownloaded;
  final void Function(String ip) onDisconnected;

  Socket? _socket;
  bool _choked = true;
  bool _interested = false;
  final List<bool> _peerHasPiece;
  final Map<int, Map<int, Uint8List>> _pendingBlocks = {};
  static const int _blockSize = 16384; // 16KB
  bool _handshakeDone = false;
  final _receiveBuffer = <int>[];
  bool _disposed = false;

  PeerConnection({
    required this.ip,
    required this.port,
    required this.infoHash,
    required this.peerId,
    required this.totalPieces,
    required this.pieceLength,
    required this.totalSize,
    required this.pieceManager,
    required this.onPieceDownloaded,
    required this.onDisconnected,
  }) : _peerHasPiece = List.filled(totalPieces, false);

  // Build the 68-byte handshake
  Uint8List _buildHandshake() {
    final buf = Uint8List(68);
    buf[0] = 19;
    buf.setRange(1, 20, utf8.encode('BitTorrent protocol'));
    // Reserved bytes 20-27: set DHT bit (byte 27, bit 0)
    buf[27] = 0x01;
    buf.setRange(28, 48, infoHash);
    buf.setRange(48, 68, peerId);
    return buf;
  }

  // Build a peer wire message
  Uint8List _buildMessage(int type, [Uint8List? payload]) {
    final payloadLen = payload?.length ?? 0;
    final buf = Uint8List(4 + 1 + payloadLen);
    final view = ByteData.view(buf.buffer);
    view.setUint32(0, 1 + payloadLen, Endian.big);
    buf[4] = type;
    if (payload != null) buf.setRange(5, 5 + payloadLen, payload);
    return buf;
  }

  // Build a request message
  Uint8List _buildRequest(int pieceIndex, int begin, int length) {
    final payload = Uint8List(12);
    final view = ByteData.view(payload.buffer);
    view.setUint32(0, pieceIndex, Endian.big);
    view.setUint32(4, begin, Endian.big);
    view.setUint32(8, length, Endian.big);
    return _buildMessage(6, payload);
  }

  Future<void> connect() async {
    try {
      debugPrint('[Peer] Connecting to $ip:$port');
      _socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 10),
      );
      // Send handshake immediately
      _socket!.add(_buildHandshake());
      // Listen for data
      _socket!.listen(
        _onData,
        onError: (_) => dispose(),
        onDone: () => dispose(),
      );
    } catch (e) {
      debugPrint('[Error] PeerConnection: failed to connect $ip:$port — $e');
      dispose();
    }
  }

  void _onData(Uint8List data) {
    _receiveBuffer.addAll(data);
    _processBuffer();
  }

  void _processBuffer() {
    if (_disposed) return;
    if (!_handshakeDone) {
      if (_receiveBuffer.length < 68) return;
      // Validate handshake
      final pstrLen = _receiveBuffer[0];
      if (pstrLen != 19) {
        dispose();
        return;
      }
      final receivedHash = Uint8List.fromList(_receiveBuffer.sublist(28, 48));
      // Verify info_hash matches
      for (int i = 0; i < 20; i++) {
        if (receivedHash[i] != infoHash[i]) {
          dispose();
          return;
        }
      }
      _receiveBuffer.removeRange(0, 68);
      _handshakeDone = true;
      debugPrint('[Peer] Handshake OK with $ip:$port');
      // Send interested
      _socket!.add(_buildMessage(2)); // 2 = interested
      _processBuffer();
      return;
    }
    // Parse length-prefixed messages
    while (_receiveBuffer.length >= 4) {
      final view = ByteData.view(
        Uint8List.fromList(_receiveBuffer.sublist(0, 4)).buffer,
      );
      final msgLen = view.getUint32(0, Endian.big);
      if (msgLen == 0) {
        // keep-alive
        _receiveBuffer.removeRange(0, 4);
        continue;
      }
      if (_receiveBuffer.length < 4 + msgLen) break;
      final msgId = _receiveBuffer[4];
      final payload = Uint8List.fromList(_receiveBuffer.sublist(5, 4 + msgLen));
      _receiveBuffer.removeRange(0, 4 + msgLen);
      _handleMessage(msgId, payload);
    }
  }

  void _handleMessage(int id, Uint8List payload) {
    switch (id) {
      case 0: // choke
        _choked = true;
        break;
      case 1: // unchoke
        _choked = false;
        debugPrint('[Peer] Unchoked by $ip:$port — requesting pieces');
        _requestNextBlocks();
        break;
      case 4: // have
        if (payload.length >= 4) {
          final view = ByteData.view(payload.buffer);
          final idx = view.getUint32(0, Endian.big);
          if (idx < totalPieces) _peerHasPiece[idx] = true;
        }
        break;
      case 5: // bitfield
        for (int i = 0; i < payload.length; i++) {
          for (int bit = 7; bit >= 0; bit--) {
            final pieceIdx = i * 8 + (7 - bit);
            if (pieceIdx < totalPieces) {
              _peerHasPiece[pieceIdx] = (payload[i] >> bit) & 1 == 1;
            }
          }
        }
        _requestNextBlocks();
        break;
      case 7: // piece
        if (payload.length >= 8) {
          final view = ByteData.view(payload.buffer);
          final pieceIdx = view.getUint32(0, Endian.big);
          final begin = view.getUint32(4, Endian.big);
          final block = payload.sublist(8);
          _onBlockReceived(pieceIdx, begin, block);
        }
        break;
    }
  }

  Future<void> _requestNextBlocks() async {
    if (_choked || _disposed) return;
    // Find next piece we need that this peer has
    for (int i = 0; i < totalPieces; i++) {
      if (!_peerHasPiece[i]) continue;
      if (await pieceManager.hasPiece(i)) continue;
      if (_pendingBlocks.containsKey(i)) continue;
      _requestPieceBlocks(i);
      break; // Request one piece at a time
    }
  }

  void _requestPieceBlocks(int pieceIdx) {
    final isLast = pieceIdx == totalPieces - 1;
    final thisPieceLength = isLast
        ? totalSize - (pieceIdx * pieceLength)
        : pieceLength;
    _pendingBlocks[pieceIdx] = {};
    int offset = 0;
    while (offset < thisPieceLength) {
      final blockLen = min(_blockSize, thisPieceLength - offset);
      _socket!.add(_buildRequest(pieceIdx, offset, blockLen));
      offset += blockLen;
    }
  }

  void _onBlockReceived(int pieceIdx, int begin, Uint8List block) {
    _pendingBlocks.putIfAbsent(pieceIdx, () => {})[begin] = block;
    // Check if all blocks for this piece are received
    final isLast = pieceIdx == totalPieces - 1;
    final thisPieceLength = isLast
        ? totalSize - (pieceIdx * pieceLength)
        : pieceLength;
    int totalReceived = 0;
    for (final b in _pendingBlocks[pieceIdx]!.values) {
      totalReceived += b.length;
    }
    if (totalReceived >= thisPieceLength) {
      // Assemble piece from blocks
      final pieceData = Uint8List(thisPieceLength);
      for (final entry in _pendingBlocks[pieceIdx]!.entries) {
        pieceData.setRange(
          entry.key,
          entry.key + entry.value.length,
          entry.value,
        );
      }
      _pendingBlocks.remove(pieceIdx);
      _savePiece(pieceIdx, pieceData);
    }
  }

  Future<void> _savePiece(int pieceIdx, Uint8List data) async {
    final ok = await pieceManager.savePiece(pieceIdx, data);
    if (ok) {
      debugPrint('[Piece] Piece $pieceIdx verified and saved');
      onPieceDownloaded(pieceIdx, data.length);
      _requestNextBlocks(); // Request next piece
    } else {
      debugPrint('[Error] Piece $pieceIdx failed verification — discarding');
      _requestPieceBlocks(pieceIdx); // Re-request
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _socket?.destroy();
    onDisconnected(ip);
  }
}
