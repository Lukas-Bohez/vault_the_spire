import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vault_the_spire/models/server.dart';
import 'package:vault_the_spire/services/server_service.dart';

void main() {
  test('encode and decode invite roundtrip', () {
    final service = ServerService.instance;
    final server = ServerModel(
      id: 'test-server',
      name: 'Test Server',
      description: 'A server for tests',
      channels: [],
    );

    final invite = service.encodeInvite(server);
    final decoded = service.decodeInvite(invite);

    expect(decoded, isNotNull);
    expect(decoded?.id, equals(server.id));
    expect(decoded?.name, equals(server.name));
    expect(decoded?.description, equals(server.description));
  });

  test('decodeInvite accepts unencoded JSON too', () {
    final service = ServerService.instance;
    final raw = jsonEncode({
      'id': 'raw-server-id',
      'name': 'Raw Server',
      'description': 'Raw invite',
    });

    final decoded = service.decodeInvite(raw);

    expect(decoded?.id, equals('raw-server-id'));
    expect(decoded?.name, equals('Raw Server'));
  });

  test('reformatInvite outputs consistent JSON containing id', () {
    final service = ServerService.instance;
    final server = ServerModel(
      id: 'refid',
      name: 'Ref Server',
      description: 'Ref description',
      channels: [],
    );
    final reformat = jsonDecode(service.reformatInvite(server));
    expect(reformat['id'], equals('refid'));
    expect(reformat['name'], equals('Ref Server'));
  });
}
