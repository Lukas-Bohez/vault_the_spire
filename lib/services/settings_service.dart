import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const _kUseSystemTray = 'use_system_tray';
  static const _kMinimizeToTrayOnClose = 'minimize_to_tray_on_close';
  static const _kLaunchOnStartup = 'launch_on_startup';

  static final SettingsService instance = SettingsService._();

  SettingsService._();

  bool useSystemTray = true;
  bool minimizeToTrayOnClose = true;
  bool launchOnStartup = false;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    useSystemTray = prefs.getBool(_kUseSystemTray) ?? true;
    minimizeToTrayOnClose = prefs.getBool(_kMinimizeToTrayOnClose) ?? true;
    launchOnStartup = prefs.getBool(_kLaunchOnStartup) ?? false;
  }

  Future<void> setUseSystemTray(bool value) async {
    useSystemTray = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kUseSystemTray, value);
  }

  Future<void> setMinimizeToTrayOnClose(bool value) async {
    minimizeToTrayOnClose = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kMinimizeToTrayOnClose, value);
  }

  Future<void> setLaunchOnStartup(bool value) async {
    launchOnStartup = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kLaunchOnStartup, value);
  }
}
