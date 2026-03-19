import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:vault_the_spire/crypto/identity.dart';

class IdentityService {
  IdentityService._();

  static final IdentityService instance = IdentityService._();

  static const _kIdentityKey = 'vault_the_spire_identity';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  Identity? _identity;

  Identity? get identity => _identity;

  Future<void> initialize() async {
    final raw = await _secureStorage.read(key: _kIdentityKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _identity = Identity.fromJson(data);
        return;
      } catch (_) {
        // fallback to regeneration
      }
    }

    final identity = await Identity.generate();
    _identity = identity;
    await _secureStorage.write(key: _kIdentityKey, value: jsonEncode(identity.toJson()));
  }
}
