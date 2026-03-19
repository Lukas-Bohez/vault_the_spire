import 'dart:convert';
import 'dart:typed_data';

Uint8List bencode(dynamic value) {
  if (value is int) {
    return Uint8List.fromList(utf8.encode('i${value}e'));
  }
  if (value is String) {
    final bytes = utf8.encode(value);
    final prefix = utf8.encode('${bytes.length}:');
    return Uint8List.fromList([...prefix, ...bytes]);
  }
  if (value is Uint8List) {
    final prefix = utf8.encode('${value.length}:');
    return Uint8List.fromList([...prefix, ...value]);
  }
  if (value is List) {
    final parts = <int>[];
    parts.addAll(utf8.encode('l'));
    for (final element in value) {
      parts.addAll(bencode(element));
    }
    parts.addAll(utf8.encode('e'));
    return Uint8List.fromList(parts);
  }
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((a, b) {
        final ak = _toUint8ListKey(a.key);
        final bk = _toUint8ListKey(b.key);
        return _compareBytes(ak, bk);
      });
    final parts = <int>[];
    parts.addAll(utf8.encode('d'));
    for (final entry in entries) {
      final keyBytes = _toUint8ListKey(entry.key);
      parts.addAll(bencode(keyBytes));
      parts.addAll(bencode(entry.value));
    }
    parts.addAll(utf8.encode('e'));
    return Uint8List.fromList(parts);
  }
  throw ArgumentError.value(value, 'value', 'Unsupported bencode type');
}

dynamic bdecode(Uint8List data) {
  int index = 0;

  dynamic decodeNext() {
    if (index >= data.length) throw FormatException('Unexpected end of data');
    final byte = data[index];

    if (byte == 0x69) {
      // 'i'
      index++;
      final end = data.indexOf(0x65, index);
      if (end == -1) throw FormatException('Invalid integer encoding');
      final number = int.parse(utf8.decode(data.sublist(index, end)));
      index = end + 1;
      return number;
    }

    if (byte == 0x6c) {
      // 'l'
      index++;
      final list = <dynamic>[];
      while (data[index] != 0x65) {
        list.add(decodeNext());
      }
      index++;
      return list;
    }

    if (byte == 0x64) {
      // 'd'
      index++;
      final map = <String, dynamic>{};
      while (data[index] != 0x65) {
        final keyBytes = decodeNext();
        if (keyBytes is! Uint8List) {
          throw FormatException('Map key must be bytes');
        }
        final key = utf8.decode(keyBytes);
        final value = decodeNext();
        map[key] = value;
      }
      index++;
      return map;
    }

    if (byte >= 0x30 && byte <= 0x39) {
      final colon = data.indexOf(0x3a, index);
      if (colon == -1) throw FormatException('Invalid string length encoding');
      final len = int.parse(utf8.decode(data.sublist(index, colon)));
      index = colon + 1;
      final result = data.sublist(index, index + len);
      index += len;
      return result;
    }

    throw FormatException(
      'Invalid bencode prefix: ${String.fromCharCode(byte)}',
    );
  }

  final result = decodeNext();
  if (index != data.length) {
    throw FormatException('Extra bytes after valid bencode');
  }
  return result;
}

Uint8List _toUint8ListKey(dynamic key) {
  if (key is String) return Uint8List.fromList(utf8.encode(key));
  if (key is Uint8List) return key;
  throw ArgumentError.value(key, 'key', 'Unsupported map key type');
}

int _compareBytes(Uint8List a, Uint8List b) {
  final len = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < len; i++) {
    final diff = a[i] - b[i];
    if (diff != 0) return diff;
  }
  return a.length - b.length;
}
