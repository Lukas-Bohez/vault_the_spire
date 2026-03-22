import 'dart:io';

import 'package:flutter/material.dart';
import 'package:vault_the_spire/platform/desktop_window.dart';
import 'package:vault_the_spire/platform/hotkeys.dart';
import 'package:vault_the_spire/platform/notifications_desktop.dart';
import 'package:vault_the_spire/platform/system_tray.dart';
import 'package:vault_the_spire/screens/home_screen.dart';
import 'package:vault_the_spire/services/identity_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await setupDesktopWindow();
    await setupSystemTray();
    await setupHotkeys();
    DesktopNotificationPoller.instance.start();
  }

  await IdentityService.instance.initialize();

  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VaultTheSpire',
      theme: ThemeData(primarySwatch: Colors.indigo, useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}
