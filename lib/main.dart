import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vault_the_spire/platform/desktop_window.dart';
import 'package:vault_the_spire/platform/hotkeys.dart';
import 'package:vault_the_spire/platform/notifications_desktop.dart';
import 'package:vault_the_spire/screens/home_screen.dart';
import 'package:vault_the_spire/services/identity_service.dart';
import 'package:vault_the_spire/services/settings_service.dart';
import 'package:vault_the_spire/services/service_locator.dart';
import 'package:vault_the_spire/services/startup_service.dart';
import 'package:vault_the_spire/services/theme_service.dart';
import 'package:vault_the_spire/services/tray_service.dart';
import 'package:vault_the_spire/services/background_service.dart';
import 'package:window_manager/window_manager.dart';

Future<void> _initSqlCipherOnAndroid() async {
  if (Platform.isAndroid) {
    await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
  }
}

Future<void> _requestAndroidPermissions() async {
  if (!kIsWeb && Platform.isAndroid) {
    final perms = await [
      Permission.storage,
      Permission.photos,
      Permission.mediaLibrary,
    ].request();
    if (kDebugMode) {
      for (final e in perms.entries) {
        debugPrint('Android permission ${e.key}: ${e.value}');
      }
    }
  }
}

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await setupServiceLocator();
      await _initSqlCipherOnAndroid();
      await _requestAndroidPermissions();
      await initBackgroundService();

      if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await setupDesktopWindow();

        await ThemeService.instance.load();
        await SettingsService.instance.load();

        if (SettingsService.instance.launchOnStartup) {
          await StartupService.enable();
        } else {
          await StartupService.disable();
        }

        if (SettingsService.instance.useSystemTray) {
          await TrayService(
            shouldMinimiseToTray: () =>
                SettingsService.instance.minimizeToTrayOnClose,
            onTrayShow: () async {
              await windowManager.show();
            },
            onTrayQuit: () async {
              await windowManager.destroy();
            },
          ).init();
        }

        await setupHotkeys();
        DesktopNotificationPoller.instance.start();
      }

      await IdentityService.instance.initialize();

      runApp(const MainApp());
    },
    (error, stack) {
      debugPrint('UNCAUGHT ZONED ERROR: $error');
      debugPrint(stack.toString());
    },
  );
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final themeService = ThemeService.instance;

  @override
  void initState() {
    super.initState();
    themeService.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    themeService.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VaultTheSpire',
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFF5865F2),
        scaffoldBackgroundColor: const Color(0xFFF2F3F5),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5865F2),
          brightness: Brightness.light,
          primary: const Color(0xFF5865F2),
          secondary: const Color(0xFF2F3136),
          surface: const Color(0xFFF2F3F5),
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF5865F2),
        scaffoldBackgroundColor: const Color(0xFF0B0D14),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF5865F2),
          brightness: Brightness.dark,
          primary: const Color(0xFF5865F2),
          secondary: const Color(0xFF2F3136),
          surface: const Color(0xFF12181F),
        ),
        useMaterial3: true,
      ),
      themeMode: themeService.themeMode,
      home: const HomeScreen(),
    );
  }
}
