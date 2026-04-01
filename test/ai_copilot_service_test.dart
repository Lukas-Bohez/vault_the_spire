import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vault_the_spire/services/ai_copilot_service.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }
}

void main() {
  test('chatChunkStream parses ndjson chunks and done signal', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost:11434'));
    dio.httpClientAdapter = _FakeAdapter((options) async {
      final lines = [
        '{"message":{"content":"Hello "},"done":false}\n',
        '{"message":{"content":"world"},"done":true}\n',
      ].join();
      return ResponseBody.fromString(
        lines,
        200,
        headers: {
          Headers.contentTypeHeader: ['application/x-ndjson'],
        },
      );
    });

    final service = AiCopilotService(dio: dio);
    final stream = await service.chatChunkStream(
      model: 'llama3',
      messages: const [
        {'role': 'user', 'content': 'hi'},
      ],
    );

    final items = await stream.toList();
    expect(items.length, 2);
    expect(items.first.content, 'Hello ');
    expect(items.last.done, isTrue);
  });

  test('verifyTorrentIntent returns true for YES', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost:11434'));
    dio.httpClientAdapter = _FakeAdapter((options) async {
      final body = jsonEncode({
        'message': {'content': 'YES'},
      });
      return ResponseBody.fromString(
        body,
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    });

    final service = AiCopilotService(dio: dio);
    final ok = await service.verifyTorrentIntent(
      model: 'llama3',
      userMessage: 'search for ubuntu',
    );

    expect(ok, isTrue);
  });

  test('checkVersion returns false on connection failure', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://localhost:11434'));
    dio.httpClientAdapter = _FakeAdapter((options) async {
      throw DioException.connectionError(
        requestOptions: options,
        reason: 'offline',
      );
    });

    final service = AiCopilotService(dio: dio);
    expect(await service.checkVersion(), isFalse);
  });
}
