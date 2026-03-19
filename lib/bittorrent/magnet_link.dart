import 'dart:core';

class MagnetLink {
  final String? infoHashV1;
  final String? infoHashV2;
  final String? displayName;
  final List<String> trackers;
  final List<String> peers;

  MagnetLink({
    this.infoHashV1,
    this.infoHashV2,
    this.displayName,
    List<String>? trackers,
    List<String>? peers,
  }) : trackers = trackers ?? [],
       peers = peers ?? [];

  factory MagnetLink.parse(String uri) {
    final parsed = Uri.parse(uri);
    if (parsed.scheme != 'magnet') {
      throw FormatException('Not a magnet link');
    }

    final params = parsed.queryParametersAll;
    String? infoHashV1;
    String? infoHashV2;
    String? displayName;
    final trackers = <String>[];
    final peers = <String>[];

    for (final entry in params.entries) {
      final key = entry.key;
      for (final value in entry.value) {
        if (key == 'xt') {
          if (value.startsWith('urn:btih:')) {
            infoHashV1 = value.substring(9).toLowerCase();
          } else if (value.startsWith('urn:btmh:')) {
            var hash = value.substring(9);
            if (hash.startsWith('1220')) {
              hash = hash.substring(4);
            }
            infoHashV2 = hash.toLowerCase();
          }
        } else if (key == 'dn') {
          displayName = value;
        } else if (key == 'tr') {
          trackers.add(value);
        } else if (key == 'x.pe') {
          peers.add(value);
        }
      }
    }

    return MagnetLink(
      infoHashV1: infoHashV1,
      infoHashV2: infoHashV2,
      displayName: displayName,
      trackers: trackers,
      peers: peers,
    );
  }

  String toUri() {
    final params = <String>[];
    if (infoHashV1 != null) {
      params.add('xt=urn:btih:$infoHashV1');
    }
    if (infoHashV2 != null) {
      params.add('xt=urn:btmh:$infoHashV2');
    }
    if (displayName != null) {
      params.add('dn=${Uri.encodeComponent(displayName!)}');
    }
    for (final t in trackers) {
      params.add('tr=${Uri.encodeComponent(t)}');
    }
    for (final p in peers) {
      params.add('x.pe=${Uri.encodeComponent(p)}');
    }
    return 'magnet:?${params.join('&')}';
  }
}
