import 'dart:convert';

import 'package:vault_the_spire/models/contact.dart';

class SignalQrImport {
  static Contact? tryParse(String qrData) {
    final normalized = qrData.trim();

    final signalMatch = RegExp(
      r'signal\.me/#p/([A-Za-z0-9_\-]+)',
    ).firstMatch(normalized);
    if (signalMatch != null) {
      final encoded = signalMatch.group(1)!;
      try {
        final normalizedBase64 = base64Url.normalize(encoded);
        final decoded = base64Url.decode(normalizedBase64);

        // Signal uses protobuf-encoded payloads; to avoid unsafe assumptions,
        // only accept an explicit raw 32-byte X25519 key or a JSON fallback.
        if (decoded.length == 32) {
          final publicKey = base64Url.encode(decoded);
          return Contact(
            id: 'signal_import_${publicKey.substring(0, 8)}',
            username: 'signal_${publicKey.substring(0, 8)}',
            publicKey: publicKey,
            avatarSeed: publicKey.substring(0, 8),
            displayName: 'Signal contact',
            importedFrom: 'signal',
          );
        }
      } catch (_) {
        // invalid signal payload
      }

      // No safe decoding path for unknown protobuf formats; reject.
      return null;
    }

    try {
      final jsonObj = jsonDecode(qrData) as Map<String, dynamic>;
      if (jsonObj.containsKey('public_key')) {
        return Contact.fromJson(jsonObj);
      }
    } catch (_) {
      // ignore
    }

    return null;
  }
}
