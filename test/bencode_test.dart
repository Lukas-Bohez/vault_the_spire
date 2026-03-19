import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vault_the_spire/bittorrent/bencode.dart';

void main() {
  test('bencode and bdecode integer', () {
    final encoded = bencode(123);
    expect(utf8.decode(encoded), 'i123e');
    final decoded = bdecode(encoded);
    expect(decoded, 123);
  });

  test('bencode and bdecode string', () {
    final encoded = bencode('spam');
    expect(utf8.decode(encoded), '4:spam');
    final decoded = bdecode(encoded);
    expect(decoded, isA<Uint8List>());
    expect(utf8.decode(decoded as Uint8List), 'spam');
  });

  test('bencode and bdecode list', () {
    final encoded = bencode([1, 'a']);
    expect(utf8.decode(encoded), 'li1e1:ae');
    final decoded = bdecode(encoded);
    expect(decoded, isA<List>());
    expect((decoded as List).first, 1);
  });

  test('bencode and bdecode dict', () {
    final encoded = bencode({'bar': 'spam', 'foo': 42});
    expect(utf8.decode(encoded), 'd3:bar4:spam3:fooi42ee');
    final decoded = bdecode(encoded);
    expect(decoded, isA<Map>());
    final map = decoded as Map;
    expect(utf8.decode(map['bar'] as Uint8List), 'spam');
    expect(map['foo'], 42);
  });
}
