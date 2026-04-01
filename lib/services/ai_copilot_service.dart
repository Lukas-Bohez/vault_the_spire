import 'dart:convert';

import 'package:dio/dio.dart';

class AiCopilotService {
  AiCopilotService({Dio? dio})
      : _dio =
            dio ?? Dio(BaseOptions(baseUrl: 'http://localhost:11434', connectTimeout: const Duration(seconds: 20), receiveTimeout: const Duration(seconds: 120)));

  final Dio _dio;

  Future<Stream<String>> chatStream({
    required String model,
    required List<Map<String, dynamic>> messages,
  }) async {
    final response = await _dio.post<ResponseBody>(
      '/api/chat',
      data: {
        'model': model,
        'messages': messages,
        'stream': true,
      },
      options: Options(responseType: ResponseType.stream),
    );

    return utf8.decoder
        .bind(response.data!.stream)
        .transform(const LineSplitter())
        .where((line) => line.trim().isNotEmpty)
        .map((line) {
          final map = jsonDecode(line);
          if (map is Map<String, dynamic>) {
            final message = map['message'] as Map<String, dynamic>?;
            return (message?['content'] as String?) ?? '';
          }
          return '';
        })
        .where((content) => content.isNotEmpty);
  }

  Future<bool> verifyTorrentIntent({
    required String model,
    required String userMessage,
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/chat',
      data: {
        'model': model,
        'stream': false,
        'messages': [
          {
            'role': 'system',
            'content':
                'Classify if the user message is an actionable torrent command in this app. Reply with only YES or NO.',
          },
          {'role': 'user', 'content': userMessage},
        ],
      },
    );

    final content = ((response.data?['message'] as Map?)?['content'] ?? '')
        .toString()
        .trim()
        .toUpperCase();
    return content.startsWith('YES');
  }
}
