import 'dart:convert';

import 'package:vault_the_spire/models/contact.dart';

class SignalQrImport {
  static Contact? tryParse(String qrData) {
    final normalized = qrData.trim();

    final signalMatch = RegExp(r'signal\.me/#p/([A-Za-z0-9_\-]+)').firstMatch(normalized);
    if (signalMatch != null) {
      final keyB64 = signalMatch.group(1)!;
      return Contact(
        id: 'signal_import_${keyB64.substring(0, 8)}',
        username: 'signal_${keyB64.substring(0, 8)}',
        publicKey: keyB64,
        avatarSeed: keyB64.substring(0, 8),
        displayName: 'Signal contact',
        importedFrom: 'signal',
      );
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
