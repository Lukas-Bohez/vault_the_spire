class VaultLink {
  final String infoHash; // sha256 of encrypted content / bt v2 infohash
  final String keyBase64;

  VaultLink({required this.infoHash, required this.keyBase64});

  String toUri() => 'vault://$infoHash#$keyBase64';

  String toMagnetUri() {
    final minimal = 'magnet:?xt=urn:btmh:1220$infoHash&x.vault=1';
    return keyBase64.isNotEmpty ? '$minimal#$keyBase64' : minimal;
  }

  static VaultLink parse(String uri) {
    if (uri.startsWith('vault://')) {
      final parsed = Uri.parse(uri);
      final infoHash = parsed.host;
      final key = parsed.fragment;
      if (infoHash.isEmpty || key.isEmpty) {
        throw FormatException('Invalid vault URI');
      }

      // Security: vault URI fragment carries secret key material and can leak via
      // clipboard/history logs. Any integration using this should treat fragments as ephemeral.
      if (uri.contains(' ')) {
        throw FormatException('Vault URI fragment must not contain whitespace or be logged');
      }

      return VaultLink(infoHash: infoHash, keyBase64: key);
    }

    if (uri.startsWith('magnet:')) {
      final parsed = Uri.parse(uri);
      String? infoHash;
      final queryParametersAll = parsed.queryParametersAll;
      for (final entry in queryParametersAll.entries) {
        for (final value in entry.value) {
          if (entry.key == 'xt' && value.startsWith('urn:btmh:')) {
            var hash = value.substring('urn:btmh:'.length);
            if (hash.startsWith('1220')) hash = hash.substring(4);
            infoHash = hash;
          }
        }
      }
      final key = parsed.fragment;
      if (infoHash == null || infoHash.isEmpty || key.isEmpty) {
        throw FormatException('Invalid magnet vault link');
      }
      return VaultLink(infoHash: infoHash, keyBase64: key);
    }

    throw FormatException('Unsupported vault link format');
  }

  Map<String, dynamic> toJson() => {
    'infoHash': infoHash,
    'keyBase64': keyBase64,
  };

  factory VaultLink.fromJson(Map<String, dynamic> json) {
    return VaultLink(
      infoHash: json['infoHash'] as String,
      keyBase64: json['keyBase64'] as String,
    );
  }
}
