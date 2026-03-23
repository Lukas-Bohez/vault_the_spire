import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vault_the_spire/services/settings_service.dart';

class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  final AudioPlayer _player = AudioPlayer();

  Future<void> _play(String asset) async {
    if (!SettingsService.instance.soundEffectsEnabled) return;
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      HapticFeedback.lightImpact();
    }
    try {
      await _player.play(AssetSource(asset), volume: 0.85);
    } catch (e) {
      // non-fatal, just keep UX moving
      debugPrint('Sound play error: $e');
    }
  }

  Future<void> playClick() async => _play('sounds/click.wav');
  Future<void> playSend() async => _play('sounds/send.wav');
  Future<void> playNotification() async => _play('sounds/notification.wav');
  Future<void> playMention() async => _play('sounds/mention.wav');
}
