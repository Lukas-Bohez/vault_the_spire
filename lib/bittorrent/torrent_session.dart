
import 'dart:async';
import 'dart:convert';
import 'dart:math';
// import 'dart:typed_data';
import 'dart:io';
// import 'bencode.dart';
import 'tracker.dart';
import 'peer_connection.dart';
import 'piece_manager.dart';
import 'package:flutter/foundation.dart';


class TorrentStatus {
  final String name;
  final double progress;        // 0.0 to 1.0
  final double downloadSpeed;   // bytes/sec
  final int connectedPeers;
  final int totalPieces;
  final int completedPieces;
  final String statusText;      // 'connecting', 'downloading', 'complete', 'error'
  const TorrentStatus({
    required this.name,
    required this.progress,
    required this.downloadSpeed,
    required this.connectedPeers,
    required this.totalPieces,
    required this.completedPieces,
    required this.statusText,
  });
}


class TorrentSession {
  final String infoHash;        // 40-char hex
  final String name;
  final List<String> trackers;
  final int totalSize;
  final int pieceLength;
  final int totalPieces;
  final List<String> pieceHashesHex; // SHA-1 per piece, hex strings

  late final Uint8List _infoHashBytes; // parsed from hex
  late final Uint8List _peerId;
  final List<PeerConnection> _connections = [];
  int _completedPieces = 0;
  int _bytesDownloaded = 0;
  DateTime _lastSpeedCheck = DateTime.now();
  int _bytesLastCheck = 0;
  final _statusController = StreamController<TorrentStatus>.broadcast();
  Stream<TorrentStatus> get statusStream => _statusController.stream;
  late final PieceManager _pieceManager;
  bool _started = false;

  TorrentSession({
    required this.infoHash,
    required this.name,
    required this.trackers,
    required this.totalSize,
    required this.pieceLength,
    required this.totalPieces,
    required this.pieceHashesHex,
  });

  Future<void> start() async {
    if (_started) return;
    _started = true;

    // Parse infoHash hex to raw bytes
    _infoHashBytes = Uint8List(20);
    for (int i = 0; i < 20; i++) {
      _infoHashBytes[i] = int.parse(
        infoHash.substring(i * 2, i * 2 + 2), radix: 16);
    }

    // Generate peer ID: -VT0001-<12 random bytes>
    final rand = Random();
    _peerId = Uint8List(20);
    final prefix = utf8.encode('-VT0001-');
    _peerId.setRange(0, 8, prefix);
    for (int i = 8; i < 20; i++) {
      _peerId[i] = rand.nextInt(256);
    }

    // Init piece manager
    _pieceManager = PieceManager(
      infoHash: infoHash,
      pieceLength: pieceLength,
      totalPieces: totalPieces,
      appDirectory: Directory('.'), // TODO: pass correct app directory
    );
    await _pieceManager.initialize();

    debugPrint('[Session] Starting torrent: $name ($infoHash)');
    debugPrint('[Session] Trackers: $trackers');

    _emitStatus('connecting');

    // Announce to trackers
    final peers = await TrackerClient.announceAll(
      trackers: trackers,
      infoHash: _infoHashBytes,
      peerId: _peerId,
      left: totalSize,
    );

    debugPrint('[Session] Connecting to ${peers.length} peers');

    if (peers.isEmpty) {
      _emitStatus('no peers found');
      return;
    }

    _emitStatus('downloading');

    // Connect to first 30 peers
    for (final peer in peers.take(30)) {
      final conn = PeerConnection(
        ip: peer.ip,
        port: peer.port,
        infoHash: _infoHashBytes,
        peerId: _peerId,
        totalPieces: totalPieces,
        pieceLength: pieceLength,
        totalSize: totalSize,
        pieceManager: _pieceManager,
        onPieceDownloaded: _onPieceDownloaded,
        onDisconnected: _onPeerDisconnected,
      );
      _connections.add(conn);
      conn.connect(); // fire and forget
    }
  }

  void _onPieceDownloaded(int pieceIndex, int bytes) {
    _completedPieces++;
    _bytesDownloaded += bytes;
    _emitStatus(
      _completedPieces >= totalPieces ? 'complete' : 'downloading');
  }

  void _onPeerDisconnected(String ip) {
    _connections.removeWhere((c) => c.ip == ip);
  }

  void _emitStatus(String text) {
    final now = DateTime.now();
    final elapsed = now.difference(_lastSpeedCheck).inMilliseconds;
    double speed = 0;
    if (elapsed > 1000) {
      speed = (_bytesDownloaded - _bytesLastCheck) * 1000 / elapsed;
      _bytesLastCheck = _bytesDownloaded;
      _lastSpeedCheck = now;
    }
      _statusController.add(TorrentStatus(
        name: name,
        progress: totalPieces > 0 ? _completedPieces / totalPieces : 0,
        downloadSpeed: speed,
        connectedPeers: _connections.length,
        totalPieces: totalPieces,
        completedPieces: _completedPieces,
        statusText: text,
      ));
    }
  }
