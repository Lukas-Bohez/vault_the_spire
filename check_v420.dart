import 'dart:io';

void check(String file, String needle, String label) {
  final content = File(file).readAsStringSync();
  final ok = content.contains(needle);
  print('${ok ? "✓" : "✗ MISSING"} $label');
  if (!ok) exit(1);
}

void main() {
  check('lib/services/torrent_engine_service.dart',
      'stream: true', 'stream=true in newTask (CRITICAL)');
  check('lib/services/torrent_engine_service.dart',
      '_forceStateRecovery', '_forceStateRecovery method');
  check('lib/services/torrent_engine_service.dart',
      'forceStateRecovery(String torrentId)',
      'public forceStateRecovery API');
  check('lib/services/torrent_engine_service.dart',
      '_fastHealthCheckTimers', 'fast health check timer');
  check('lib/services/torrent_engine_service.dart',
      "Process.run('attrib'", 'markFileHiddenOnWindows uses attrib');
  check('lib/services/torrent_engine_service.dart',
      'lookAheadSize: 8', 'non-media sequential config');
  check('lib/services/torrent_engine_service.dart',
      'unawaited(_forceStateRecovery', 'StateRecovery in health check');
  check('lib/services/torrent_service.dart',
      "'checking') return 'Checking'", 'Checking status label');
  check('lib/services/torrent_service.dart',
      '_hideAllBtStateFiles', 'startup bt.state scan');
  check('lib/screens/torrent_detail_screen.dart',
      "'Verify files'", 'Verify files button');
  check('lib/screens/torrent_detail_screen.dart',
      "statusLabel == 'Checking'", 'pulsing progress bar');
  check('lib/screens/torrents_screen.dart',
      'ETA', 'ETA in torrent list');
  check('pubspec.yaml', 'version: 4.2.0+1', 'version 4.2.0+1');
    print('\nAll checks passed - safe to build.');
}
