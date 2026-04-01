import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const _kUseSystemTray = 'use_system_tray';
  static const _kMinimizeToTrayOnClose = 'minimize_to_tray_on_close';
  static const _kLaunchOnStartup = 'launch_on_startup';
  static const _kSoundEffectsEnabled = 'sound_effects_enabled';
  static const _kUsePersistentSidebar = 'use_persistent_sidebar';
  static const _kDownloadDestination = 'download_destination';
  static const _kDisplayName = 'display_name';
  static const _kWindowX = 'window_x';
  static const _kWindowY = 'window_y';
  static const _kWindowW = 'window_w';
  static const _kWindowH = 'window_h';
  static const _kTorrentSortMode = 'torrent_sort_mode';
  static const _kBrowserHomeUrl = 'browser_home_url';
  static const _kBrowserFavorites = 'browser_favorites';
  static const _kBrowserLastUrl = 'browser_last_url';
  static const _kBrowserHistory = 'browser_history';
  static const _kAiOllamaUrl = 'ai_ollama_url';
  static const _kAiDefaultModel = 'ai_default_model';

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
  String displayName = 'Anonymous';
  double windowX = 0.0;
  double windowY = 0.0;
  double windowW = 0.0;
  double windowH = 0.0;
  String browserLastUrl = '';
  List<String> browserHistory = <String>[];
  String aiOllamaUrl = 'http://localhost:11434';
  String aiDefaultModel = 'llama3';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    displayName = prefs.getString(_kDisplayName) ?? 'Anonymous';
    useSystemTray = prefs.getBool(_kUseSystemTray) ?? true;
    minimizeToTrayOnClose = prefs.getBool(_kMinimizeToTrayOnClose) ?? true;
    launchOnStartup = prefs.getBool(_kLaunchOnStartup) ?? false;
    soundEffectsEnabled = prefs.getBool(_kSoundEffectsEnabled) ?? true;
    usePersistentSidebar = prefs.getBool(_kUsePersistentSidebar) ?? false;
    downloadDestination = prefs.getString(_kDownloadDestination) ?? '';
    windowX = prefs.getDouble(_kWindowX) ?? 0.0;
    windowY = prefs.getDouble(_kWindowY) ?? 0.0;
    windowW = prefs.getDouble(_kWindowW) ?? 0.0;
    windowH = prefs.getDouble(_kWindowH) ?? 0.0;
    torrentSortMode = prefs.getInt(_kTorrentSortMode) ?? 0;
    browserHomeUrl = prefs.getString(_kBrowserHomeUrl) ?? browserHomeUrl;
    browserFavorites =
        prefs.getStringList(_kBrowserFavorites) ?? browserFavorites;
    browserLastUrl = prefs.getString(_kBrowserLastUrl) ?? '';
    browserHistory = prefs.getStringList(_kBrowserHistory) ?? <String>[];
    aiOllamaUrl = prefs.getString(_kAiOllamaUrl) ?? 'http://localhost:11434';
    aiDefaultModel = prefs.getString(_kAiDefaultModel) ?? 'llama3';
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

  Future<void> setDisplayName(String name) async {
    displayName = name;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDisplayName, name);
  }

  Future<void> setWindowGeometry(double x, double y, double w, double h) async {
    final prefs = await SharedPreferences.getInstance();
    windowX = x;
    windowY = y;
    windowW = w;
    windowH = h;
    await prefs.setDouble(_kWindowX, x);
    await prefs.setDouble(_kWindowY, y);
    await prefs.setDouble(_kWindowW, w);
    await prefs.setDouble(_kWindowH, h);
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

  Future<void> setAiOllamaUrl(String url) async {
    aiOllamaUrl = url.trim().isEmpty ? 'http://localhost:11434' : url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAiOllamaUrl, aiOllamaUrl);
  }

  Future<void> setAiDefaultModel(String model) async {
    aiDefaultModel = model.trim().isEmpty ? 'llama3' : model.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAiDefaultModel, aiDefaultModel);
  }
}
