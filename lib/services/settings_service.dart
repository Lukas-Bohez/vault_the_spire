import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const _kUseSystemTray = 'use_system_tray';
  static const _kMinimizeToTrayOnClose = 'minimize_to_tray_on_close';
  static const _kLaunchOnStartup = 'launch_on_startup';
  static const _kSoundEffectsEnabled = 'sound_effects_enabled';
  static const _kUsePersistentSidebar = 'use_persistent_sidebar';
  static const _kDownloadDestination = 'download_destination';
  static const _kTorrentSortMode = 'torrent_sort_mode';
  static const _kBrowserHomeUrl = 'browser_home_url';
  static const _kBrowserFavorites = 'browser_favorites';
  static const _kBrowserLastUrl = 'browser_last_url';
  static const _kBrowserHistory = 'browser_history';

  static final SettingsService instance = SettingsService._();
  SettingsService._();

  bool useSystemTray = true;
  bool minimizeToTrayOnClose = true;
  bool launchOnStartup = false;
  bool soundEffectsEnabled = true;
  bool usePersistentSidebar = false;
  String downloadDestination = '';
  int torrentSortMode = 0;
  String browserHomeUrl = 'https://www.startpage.com/';
  List<String> browserFavorites = <String>[
    'https://www.startpage.com/',
    'https://news.ycombinator.com/',
    'https://www.wikipedia.org/',
  ];
  String browserLastUrl = '';
  List<String> browserHistory = <String>[];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    useSystemTray = prefs.getBool(_kUseSystemTray) ?? true;
    minimizeToTrayOnClose = prefs.getBool(_kMinimizeToTrayOnClose) ?? true;
    launchOnStartup = prefs.getBool(_kLaunchOnStartup) ?? false;
    soundEffectsEnabled = prefs.getBool(_kSoundEffectsEnabled) ?? true;
    usePersistentSidebar = prefs.getBool(_kUsePersistentSidebar) ?? false;
    downloadDestination = prefs.getString(_kDownloadDestination) ?? '';
    torrentSortMode = prefs.getInt(_kTorrentSortMode) ?? 0;
    browserHomeUrl = prefs.getString(_kBrowserHomeUrl) ?? browserHomeUrl;
    browserFavorites =
        prefs.getStringList(_kBrowserFavorites) ?? browserFavorites;
    browserLastUrl = prefs.getString(_kBrowserLastUrl) ?? '';
    browserHistory = prefs.getStringList(_kBrowserHistory) ?? <String>[];
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

  Future<void> setSoundEffectsEnabled(bool value) async {
    soundEffectsEnabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSoundEffectsEnabled, value);
  }

  Future<void> setUsePersistentSidebar(bool value) async {
    usePersistentSidebar = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kUsePersistentSidebar, value);
  }

  Future<void> setDownloadDestination(String destination) async {
    downloadDestination = destination;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDownloadDestination, destination);
  }

  Future<void> setTorrentSortMode(int value) async {
    torrentSortMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kTorrentSortMode, value);
  }

  Future<void> setBrowserHomeUrl(String url) async {
    browserHomeUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBrowserHomeUrl, url);
  }

  Future<void> setBrowserFavorites(List<String> list) async {
    browserFavorites = list;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kBrowserFavorites, list);
  }

  Future<void> setBrowserLastUrl(String url) async {
    browserLastUrl = url;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBrowserLastUrl, url);
  }

  Future<void> setBrowserHistory(List<String> history) async {
    browserHistory = history;
    final prefs = await SharedPreferences.getInstance();
    // Keep at most 200 entries persisted.
    final trimmed = history.length > 200 ? history.sublist(0, 200) : history;
    await prefs.setStringList(_kBrowserHistory, trimmed);
  }
}
