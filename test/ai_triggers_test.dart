import 'package:flutter_test/flutter_test.dart';
import 'package:vault_the_spire/services/ai_triggers.dart';
import 'package:vault_the_spire/services/search_service.dart';

void main() {
  final triggers = AiTriggers();

  test('result selected trigger emits stable dedupe key', () {
    final result = SearchResult(
      torrentId: 'abc',
      name: 'Torrent One',
      magnetLink: 'magnet:?xt=urn:btih:abc',
      responderId: 'local',
      source: 'local',
    );

    final first = triggers.onResultSelected(result);
    final second = triggers.onResultSelected(result);

    expect(first.key, 'result:abc');
    expect(second.key, first.key);
    expect(first.auto, isTrue);
  });

  test('download and zero-result events include expected templates', () {
    final started = triggers.onDownloadStarted(name: 'File', size: '1 GB');
    final zero = triggers.onZeroResults('ubuntu');

    expect(started.prompt, contains('started downloading'));
    expect(zero.prompt, contains('no results'));
  });
}
