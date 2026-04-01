import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:vault_the_spire/services/torrent_service.dart';
import 'package:vault_the_spire/vault_swarm/vault_swarm.dart';

class SearchResult {
  final String torrentId;
  final String name;
  final int? size;
  final int? seeders;
  final int? leechers;
  final int? ageYears;
  final String magnetLink;
  final String responderId;
  final String source;

  static String _asString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is Uint8List) {
      try {
        return utf8.decode(value);
      } catch (e) {
        debugPrint('SearchResult _asString decode error: $e');
        return value.toString();
      }
    }
    try {
      return value.toString();
    } catch (e) {
      debugPrint('SearchResult _asString toString error: $e');
      return '';
    }
  }

  SearchResult({
    required this.torrentId,
    required this.name,
    required this.magnetLink,
    required this.responderId,
    required this.source,
    this.size,
    this.seeders,
    this.leechers,
    this.ageYears,
  });

  factory SearchResult.fromMap(Map<String, dynamic> map) => SearchResult(
    torrentId: _asString(map['torrentId']),
    name: _asString(map['name']),
    magnetLink: _asString(map['magnetLink']),
    responderId: _asString(map['responderId']),
    source: _asString(map['source']).isEmpty
        ? _asString(map['responderId'])
        : _asString(map['source']),
    size: map['size'] is int
        ? map['size'] as int
        : int.tryParse(_asString(map['size'])),
    seeders: map['seeders'] is int
        ? map['seeders'] as int
        : int.tryParse(_asString(map['seeders'])),
    leechers: map['leechers'] is int
        ? map['leechers'] as int
        : int.tryParse(_asString(map['leechers'])),
    ageYears: map['ageYears'] is int
        ? map['ageYears'] as int
        : int.tryParse(_asString(map['ageYears'])),
  );

  Map<String, dynamic> toMap() {
    return {
      'torrentId': torrentId,
      'name': name,
      'size': size,
      'seeders': seeders,
      'leechers': leechers,
      'ageYears': ageYears,
      'magnetLink': magnetLink,
      'responderId': responderId,
      'source': source,
    };
  }
}

class SearchService {
  SearchService._() {
    _init();
  }

  static final SearchService instance = SearchService._();

  final _uuid = const Uuid();
  final _resultsController = StreamController<List<SearchResult>>.broadcast();

  Stream<List<SearchResult>> get resultsStream => _resultsController.stream;

  final List<SearchResult> _results = [];
  final String _clientId = const Uuid().v4();

  StreamSubscription<Map<String, dynamic>>? _swarmSubscription;

  void _init() {
    VaultSwarm.instance.joinSwarm('swarm_search');
    _swarmSubscription = VaultSwarm.instance.messageStream.listen(
      _onSwarmEvent,
    );
  }

  Future<void> broadcastSearch(String query) async {
    if (query.trim().isEmpty) return;

    _results.clear();
    _resultsController.add(List.unmodifiable(_results));

    await VaultSwarm.instance.joinSwarm('swarm_search');
    await VaultSwarm.instance.broadcastMessage('swarm_search', {
      'type': 'search_query',
      'payload': {'query': query, 'requesterId': _clientId},
    });
  }

  void _onSwarmEvent(Map<String, dynamic> event) {
    final type = (event['type'] ?? '').toString();
    final payload = event['payload'] as Map<String, dynamic>?;
    if (payload == null) return;

    if (type == 'search_query') {
      final query = (payload['query'] ?? '').toString();
      final requesterId = (payload['requesterId'] ?? '').toString();
      if (requesterId == _clientId) return;
      TorrentService.instance.handleIncomingSearch(
        query,
        requesterId: requesterId,
      );
      return;
    }

    if (type != 'search_response') return;

    final requesterId = (payload['requesterId'] ?? '').toString();
    if (requesterId != _clientId) return;

    final resultMap = payload['result'] as Map<String, dynamic>?;
    if (resultMap == null) return;

    final result = SearchResult.fromMap(resultMap);
    final idx = _results.indexWhere(
      (r) =>
          r.torrentId == result.torrentId &&
          r.responderId == result.responderId,
    );
    if (idx < 0) {
      _results.add(result);
      _resultsController.add(List.unmodifiable(_results));
    }
  }

  void dispose() {
    _swarmSubscription?.cancel();
    _resultsController.close();
  }
}
