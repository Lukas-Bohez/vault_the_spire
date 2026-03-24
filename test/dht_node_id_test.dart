import 'package:flutter_test/flutter_test.dart';
import 'package:vault_the_spire/crypto/identity.dart';

void main() {
  test('Identity generates unique node IDs per identity generation', () async {
    final identity1 = await Identity.generate();
    final identity2 = await Identity.generate();

    expect(identity1.nodeId, isNotEmpty);
    expect(identity2.nodeId, isNotEmpty);
    expect(identity1.nodeId, isNot(identity2.nodeId));
    expect(identity1.nodeId.length, 40);
    expect(identity2.nodeId.length, 40);
  });
}
