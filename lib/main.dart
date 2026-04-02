import 'dart:ui';

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vault_the_spire/db/sqlcipher_bootstrap.dart';
import 'package:vault_the_spire/platform/desktop_window.dart';
import 'package:vault_the_spire/platform/hotkeys.dart';
import 'package:vault_the_spire/platform/notifications_desktop.dart';
// import './screens/home_screen.dart';
import 'router.dart';
import 'package:vault_the_spire/services/identity_service.dart';
import 'package:vault_the_spire/services/settings_service.dart';
import 'package:vault_the_spire/services/service_locator.dart';
import 'package:vault_the_spire/services/startup_service.dart';
import 'package:vault_the_spire/services/theme_service.dart';
import 'package:vault_the_spire/services/tray_service.dart';
import 'package:vault_the_spire/services/torrent_service.dart';
import 'package:vault_the_spire/services/background_service.dart';
import 'package:window_manager/window_manager.dart';

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
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('UNCAUGHT PLATFORM ERROR: $error');
    debugPrint(stack.toString());
    return true; // handled
  };
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: Colors.red.shade100,
      child: Center(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Flutter Error:\n\n'
              '${details.exceptionAsString()}\n\n'
              '${details.stack?.toString().split('\n').take(8).join('\n') ?? ''}',
              style: const TextStyle(color: Colors.red, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  };
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await setupServiceLocator();
      await initSqlCipherOnAndroid();
      await _requestAndroidPermissions();

      if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      }

      await ThemeService.instance.load();
      await SettingsService.instance.load();

      if (!kIsWeb &&
          (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        await setupDesktopWindow();
      }

      // Render first frame before long-running startup work.
      runApp(const MainApp());

      unawaited(
        Future(() async {
          try {
            if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
              await initBackgroundService();
            }

            if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
              await StartupService.ensureDesktopShortcut();

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
                    exit(0);
                  },
                ).init();
              }

              await setupHotkeys();
              DesktopNotificationPoller.instance.start();
            }

            await IdentityService.instance.initialize();

            await TorrentService.instance.resumeActiveTorrents();
          } catch (error, stack) {
            debugPrint('DEFERRED STARTUP ERROR: $error');
            debugPrint(stack.toString());
          }
        }),
      );
    },
    (error, stack) {
      debugPrint('UNCAUGHT ZONED ERROR: $error');
      debugPrint(stack.toString());
    },
  );
}

// NOTE: Flutter on Windows may produce ui::AXTree warnings in debug mode
// (AccessibilityBridge internal logging). These are harmless engine diagnostics
// and are suppressed/optimized out in --release mode. No functional action is
// needed in production; this is a known desktop engine issue.
class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final themeService = ThemeService.instance;

  static const Color _brand = Color(0xFF0C8F66);

  ThemeData _buildTheme(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _brand,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        elevation: 0,
        height: 72,
        indicatorColor: scheme.secondaryContainer,
        backgroundColor: scheme.surface,
        labelTextStyle: MaterialStateProperty.resolveWith((states) {
          final selected = states.contains(MaterialState.selected);
          return TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 12,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
    );
  }

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
    return MaterialApp.router(
      title: 'TorrentSpire AI',
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: themeService.themeMode,
      routerConfig: appRouter,
    );
  }
}
