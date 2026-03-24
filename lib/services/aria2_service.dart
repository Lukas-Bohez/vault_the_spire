import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class Aria2Service {
  Aria2Service._();

  static final Aria2Service instance = Aria2Service._();

  Process? _process;
  final int _port = 6800;
  final String _host = '127.0.0.1';

  String get _url => 'http://$_host:$_port/jsonrpc';

  Future<String> _resolveBinary() async {
    final customPath = Platform.environment['ARIA2C_PATH'];
    if (customPath != null && customPath.isNotEmpty) {
      final file = File(customPath);
      if (await file.exists()) return file.path;
    }

    if (Platform.isWindows) {
      final exe = 'aria2c.exe';
      final localCandidate = p.join(
        Directory.current.path,
        exe,
      );
      if (await File(localCandidate).exists()) return localCandidate;
    } else {
      final localCandidate = p.join(
        Directory.current.path,
        'aria2c',
      );
      if (await File(localCandidate).exists()) return localCandidate;
    }

    return 'aria2c';
  }

  bool get isRunning => _process != null;

  Future<String> _defaultDownloadDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<bool> ensureRunning() async {
    if (isRunning) {
      return true;
    }

    try {
      final binary = await _resolveBinary();
      _process = await Process.start(binary, [
        '--enable-rpc',
        '--rpc-listen-all=false',
        '--rpc-allow-origin-all',
        '--rpc-listen-port=$_port',
        '--continue=true',
        '--max-concurrent-downloads=5',
        '--split=5',
        '--max-overall-download-limit=0',
        '--max-overall-upload-limit=0',
        '--rpc-save-upload-metadata=true',
        '--enable-dht=true',
        '--enable-peer-exchange=true',
        '--bt-enable-lsd=true',
        '--bt-enable-lpd=true',
        '--bt-save-metadata=true',
        '--bt-seed-unverified=true',
      ], mode: ProcessStartMode.detachedWithStdio);

      // Drain output to avoid pipes blocking
      _process?.stdout.transform(utf8.decoder).listen((_) {});
      _process?.stderr.transform(utf8.decoder).listen((_) {});

      // Give aria2 time to start.
      await Future.delayed(const Duration(seconds: 1));

      // Try a quick ping via JSON-RPC.
      await _rpc('aria2.getVersion');
      return true;
    } catch (_) {
      _process = null;
      return false;
    }
  }

  Future<Map<String, dynamic>> _rpc(
    String method, [
    List<dynamic>? params,
  ]) async {
    final payload = jsonEncode({
      'jsonrpc': '2.0',
      'id': 'vault_the_spire',
      'method': method,
      'params': params ?? [],
    });

    final uri = Uri.parse(_url);
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
      request.write(payload);
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('aria2 RPC responded with ${response.statusCode}');
      }

      final body = await response.transform(utf8.decoder).join();
      final map = jsonDecode(body) as Map<String, dynamic>;
      if (map.containsKey('error')) {
        throw StateError('aria2 RPC error: ${map['error']}');
      }
      return map;
    } finally {
      client.close(force: true);
    }
  }

  Future<String?> addMagnet(
    String magnetLink, {
    String? downloadDirectory,
  }) async {
    final downloadDir = downloadDirectory ?? await _defaultDownloadDirectory();
    final options = {'dir': downloadDir, 'continue': 'true'};
    final result = await _rpc('aria2.addUri', [
      [magnetLink],
      options,
    ]);
    return result['result'] as String?;
  }

  Future<String?> addTorrentFile(
    String torrentFilePath, {
    String? downloadDirectory,
  }) async {
    final torrentFile = File(torrentFilePath);
    if (!await torrentFile.exists()) {
      throw FileSystemException('Torrent file not found', torrentFilePath);
    }

    final encoded = base64.encode(await torrentFile.readAsBytes());
    final downloadDir = downloadDirectory ?? await _defaultDownloadDirectory();
    final options = {'dir': downloadDir, 'continue': 'true'};

    final result = await _rpc('aria2.addTorrent', [
      encoded,
      <String>[],
      options,
    ]);
    return result['result'] as String?;
  }

  Future<Map<String, dynamic>?> tellStatus(
    String gid,
    List<String> keys,
  ) async {
    final result = await _rpc('aria2.tellStatus', [gid, keys]);
    return result['result'] as Map<String, dynamic>?;
  }

  Future<Map<String, dynamic>?> tellStatusFull(String gid) async {
    final keys = [
      'gid',
      'status',
      'totalLength',
      'completedLength',
      'downloadSpeed',
      'uploadSpeed',
      'numSeeders',
      'numLeechers',
      'connections',
      'errorCode',
      'errorMessage',
    ];
    return tellStatus(gid, keys);
  }

  Future<void> pause(String gid) async {
    await _rpc('aria2.pause', [gid]);
  }

  Future<void> remove(String gid) async {
    await _rpc('aria2.remove', [gid]);
  }

  Future<void> shutdown() async {
    try {
      await _rpc('aria2.shutdown');
    } catch (_) {
      // ignore
    }
    _process?.kill(ProcessSignal.sigterm);
    _process = null;
  }
}
