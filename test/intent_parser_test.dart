import 'package:flutter_test/flutter_test.dart';
import 'package:vault_the_spire/services/intent_parser.dart';

void main() {
  final parser = IntentParser();

  test('parses search command', () {
    final intent = parser.parse('search for ubuntu');
    expect(intent.type, TorrentIntentType.search);
    expect(intent.payload, 'ubuntu');
  });

  test('keyword gate allows command-like phrases', () {
    expect(parser.passesKeywordGate('download the top result'), isTrue);
    expect(parser.passesKeywordGate('how much space do i have left'), isTrue);
  });

  test('keyword gate rejects conversational text', () {
    expect(parser.passesKeywordGate('tell me a joke about linux'), isFalse);
    expect(parser.parse('tell me a joke').type, TorrentIntentType.none);
  });
}
