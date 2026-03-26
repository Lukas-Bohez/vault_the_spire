import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:window_manager/window_manager.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const linuxSettings = LinuxInitializationSettings(defaultActionName: 'Open');

    final initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      linux: linuxSettings,
      // flutter_local_notifications ^18 (as in this project) may not expose
      // windows initialization on this API level; omit to keep compatibility.
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) async {
        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          await windowManager.show();
          await windowManager.focus();
        }
      },
    );

    _initialized = true;
  }

  Future<void> showDownloadComplete(String name) async {
    await init();

    const androidDetails = AndroidNotificationDetails(
      'torrent_complete_channel',
      'Torrent Complete',
      channelDescription: 'Torrent completion notifications',
      importance: Importance.high,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails();
    const linuxDetails = LinuxNotificationDetails();

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
      linux: linuxDetails,
    );

    await _plugin.show(
      name.hashCode & 0x7fffffff,
      'Download Complete',
      'Torrent "$name" has completed downloading.',
      details,
      payload: name,
    );
  }
}
