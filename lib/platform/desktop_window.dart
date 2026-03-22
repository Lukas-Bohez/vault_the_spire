import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

Future<void> setupDesktopWindow() async {
  await windowManager.ensureInitialized();

  const options = WindowOptions(
    size: Size(1100, 700),
    minimumSize: Size(800, 600),
    center: true,
    title: 'VaultTheSpire',
    titleBarStyle: TitleBarStyle.normal,
  );

  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}

Future<void> toggleDesktopFullScreen() async {
  final isFull = await windowManager.isFullScreen();
  await windowManager.setFullScreen(!isFull);
}
