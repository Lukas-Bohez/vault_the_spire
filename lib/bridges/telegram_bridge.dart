import 'dart:convert';
import 'package:http/http.dart' as http;

const String kBaseUrl = 'https://quizthespire.com/vault/api';

class TelegramBridgeException implements Exception {
  final String message;
  TelegramBridgeException([this.message = 'Telegram bridge error']);

  @override
  String toString() => 'TelegramBridgeException: $message';
}

class PrivateChannelException extends TelegramBridgeException {
  PrivateChannelException() : super('Private channel');
}

class TelegramChannelData {
  final String username;
  final String name;
  final String description;
  final List<ChannelPost> posts;

  TelegramChannelData({
    required this.username,
    required this.name,
    required this.description,
    required this.posts,
  });

  factory TelegramChannelData.fromJson(Map<String, dynamic> json) {
    return TelegramChannelData(
      username: json['username'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      posts: (json['posts'] as List<dynamic>? ?? [])
          .map((e) => ChannelPost.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ChannelPost {
  final String id;
  final String text;
  final DateTime date;

  ChannelPost({required this.id, required this.text, required this.date});

  factory ChannelPost.fromJson(Map<String, dynamic> json) {
    return ChannelPost(
      id: json['id'].toString(),
      text: json['text'] as String? ?? '',
      date: DateTime.parse(json['date'] as String),
    );
  }
}

class TelegramBridge {
  static String? extractChannelName(String input) {
    final normalized = input.trim();

    if (normalized.startsWith('@')) {
      final name = normalized.substring(1);
      if (RegExp(r'^[A-Za-z0-9_]+$').hasMatch(name)) {
        return name;
      }
      return null;
    }

    final patterns = [
      RegExp(r'https?://t\.me/([^/?#]+)'),
      RegExp(r't\.me/([^/?#]+)'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(normalized);
      if (match != null && match.groupCount > 0) {
        return match.group(1);
      }
    }
    return null;
  }

  Future<TelegramChannelData> fetchChannel(String channelName) async {
    final uri = Uri.parse('kBaseUrl/telegram/channel/$channelName');
    final response = await http.get(uri);

    if (response.statusCode == 403) {
      throw PrivateChannelException();
    }
    if (response.statusCode != 200) {
      throw TelegramBridgeException('HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return TelegramChannelData.fromJson(data);
  }
}
