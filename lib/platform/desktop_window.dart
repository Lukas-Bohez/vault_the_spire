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
    try {
      // Try to set the native window icon from the app icon asset (Windows/Linux)
      // This requires the window_manager plugin to support setIcon.
      await windowManager.setIcon('assets/icons/app_icon.ico');
    } catch (e) {
      // Not all platforms/plugins support runtime icon changes.
    }
  });
}

Future<void> toggleDesktopFullScreen() async {
  final isFull = await windowManager.isFullScreen();
  await windowManager.setFullScreen(!isFull);
}
