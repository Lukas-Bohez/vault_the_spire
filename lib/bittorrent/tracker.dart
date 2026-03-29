import 'dart:convert';
import 'package:http/http.dart' as http;
import 'bencode.dart';
import 'package:flutter/foundation.dart';

class TrackerPeer {
  final String ip;
  final int port;
  const TrackerPeer(this.ip, this.port);
}

class TrackerClient {
  // URL-encode 20 raw bytes for use in tracker query string
  // This is NOT Uri.encodeComponent of a hex string
  static String _urlEncodeBytes(Uint8List bytes) {
    final buf = StringBuffer();
    for (final b in bytes) {
      if ((b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) ||
          (b >= 0x30 && b <= 0x39) || b == 0x2D || b == 0x5F ||
          b == 0x2E || b == 0x7E) {
        buf.writeCharCode(b);
      } else {
        buf.write('%${b.toRadixString(16).padLeft(2, '0').toUpperCase()}');
      }
    }
    return buf.toString();
  }

  // Parse compact peers: 6 bytes per peer (4 IP + 2 port, big-endian)
  static List<TrackerPeer> _parseCompactPeers(dynamic peers) {
    if (peers is! Uint8List || peers.length % 6 != 0) return [];
    final result = <TrackerPeer>[];
    for (int i = 0; i < peers.length; i += 6) {
      final ip = '${peers[i]}.${peers[i+1]}.${peers[i+2]}.${peers[i+3]}';
      final port = (peers[i+4] << 8) | peers[i+5];
      if (port > 0) result.add(TrackerPeer(ip, port));
    }
    return result;
  }

  // Announce to a single HTTP tracker and return peer list
  // infoHash: 20 raw bytes (NOT hex)
  // peerId: 20 raw bytes
  static Future<List<TrackerPeer>> announce({
    required String trackerUrl,
    required Uint8List infoHash,
    required Uint8List peerId,
    required int left,
    String event = 'started',
  }) async {
    if (!trackerUrl.startsWith('http')) return [];
    final encodedHash = _urlEncodeBytes(infoHash);
    final encodedPeerId = _urlEncodeBytes(peerId);
    final url = '$trackerUrl'
      '?info_hash=$encodedHash'
      '&peer_id=$encodedPeerId'
      '&port=6881'
      '&uploaded=0'
      '&downloaded=0'
      '&left=$left'
      '&compact=1'
      '&event=$event';
    debugPrint('[Tracker] Announcing to: $url');
    debugPrint('[Tracker] info_hash bytes: '
        '${infoHash.map((b) => b.toRadixString(16).padLeft(2, '0')).join('')}');
    try {
      final response = await http.get(Uri.parse(url))
        .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return [];
      // MUST use bodyBytes — bencode is binary, never decode to String
      final decoded = bdecode(response.bodyBytes);
      if (decoded is! Map) return [];
      // Check for failure reason
      final failure = getKey(decoded, 'failure reason');
      if (failure != null) {
        print('Tracker failure: ${utf8.decode(failure as Uint8List, allowMalformed: true)}');
        return [];
      }
      // Get peers — compact format
      final peers = getKey(decoded, 'peers');
      if (peers == null) return [];
      final peerList = _parseCompactPeers(peers);
      debugPrint('[Tracker] Found ${peerList.length} peers from $trackerUrl');
      return peerList;
    } catch (e) {
      print('Tracker announce error: $e');
      return [];
    }
  }

  // Try all trackers in parallel, return combined unique peer list
  static Future<List<TrackerPeer>> announceAll({
    required List<String> trackers,
    required Uint8List infoHash,
    required Uint8List peerId,
    required int left,
  }) async {
    final results = await Future.wait(
      trackers.map((t) => announce(
        trackerUrl: t,
        infoHash: infoHash,
        peerId: peerId,
        left: left,
      )),
    );
    final seen = <String>{};
    final peers = <TrackerPeer>[];
    for (final list in results) {
      for (final p in list) {
        final key = '${p.ip}:${p.port}';
        if (seen.add(key)) peers.add(p);
      }
    }
    return peers;
  }
}
