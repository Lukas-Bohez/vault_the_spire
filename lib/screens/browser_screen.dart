import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as webview_windows;
import 'package:url_launcher/url_launcher.dart';

import '../platform/crash_dump_stub.dart'
    if (dart.library.io) '../platform/crash_dump_windows.dart';
import '../services/settings_service.dart';
import '../services/torrent_service.dart';
import '../services/torrent_engine_service.dart';
import 'torrent_detail_screen.dart';

class BrowserScreen extends StatefulWidget {
  final String initialUrl;
  final bool inTab;

  const BrowserScreen({super.key, this.initialUrl = '', this.inTab = false});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

// AutomaticKeepAliveClientMixin keeps the widget tree alive when the parent
// switches away to another tab — the WebView is not torn down and rebuilt,
// so the user returns to exactly the page they left.
class _BrowserScreenState extends State<BrowserScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  static bool _windowsWebViewEnvironmentInitialized = false;

  final TextEditingController _addressController = TextEditingController();

  late String _homeUrl;
  bool _showHomeScreen = true;
  late List<String> _favorites;
  bool _showHistory = false;
  List<String> _history = [];


  WebViewController? _webViewController;
  bool _isLoading = true;
  double _progress = 0.0;
  bool _canGoBack = false;
  bool _canGoForward = false;

  webview_windows.WebviewController? _windowsWebViewController;
  bool _windowsCanGoBack = false;
  bool _windowsCanGoForward = false;
  bool _windowsIsLoading = true;
  String? _lastLoadError;
  String? _webViewError;

  Timer? _memoryPollTimer;

  @override
  void initState() {
    super.initState();

    _homeUrl = SettingsService.instance.browserHomeUrl;
    _favorites = List<String>.from(SettingsService.instance.browserFavorites);
    _history = List<String>.from(SettingsService.instance.browserHistory);

    // Restore last visited URL — if available use it, otherwise fall back to
    // the initialUrl arg, then the home URL.
    final lastUrl = SettingsService.instance.browserLastUrl;
    final startUrl = widget.initialUrl.isNotEmpty
        ? widget.initialUrl
        : lastUrl.isNotEmpty
        ? lastUrl
        : _homeUrl;

    _addressController.text = startUrl;

    // If we have a real URL to restore (not the home page), show the webview
    // immediately rather than the home screen.
    if (startUrl.isNotEmpty && startUrl != _homeUrl) {
      _showHomeScreen = false;
    }

    if (Platform.isWindows) {
      _initWindowsWebView(startUrl);
    } else {
      _initWebView(startUrl);
    }
    _startMemoryMonitor();
  }

  void _initWebView(String startUrl) {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            setState(() {
              _progress = progress / 100.0;
              _isLoading = progress < 100;
            });
          },
          onPageStarted: (url) {
            setState(() {
              _isLoading = true;
              _showHomeScreen = false;
            });
          },
          onPageFinished: (url) async {
            _addressController.text = url;
            setState(() {
              _isLoading = false;
              _showHomeScreen = false;
            });
            _recordVisit(url);
            _refreshNavigationState();
          },
          onNavigationRequest: (request) {
            if (_isTorrentOrMagnetUrl(request.url)) {
              _handleTorrentOrMagnetUrl(request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            debugPrint(
              'WebResourceError: ${error.description} (Code: ${error.errorCode}) URL: ${error.url}',
            );
            setState(() {
              _lastLoadError =
                  '${error.description} (Error: ${error.errorCode})';
            });
            _captureCrashDump('WebResourceError', error);
          },
        ),
      );

    _webViewController = controller;

    if (!_showHomeScreen && startUrl.isNotEmpty) {
      controller.loadRequest(Uri.parse(startUrl));
    }
  }

  Future<void> _initWindowsWebView(String startUrl) async {
    try {
      if (!_windowsWebViewEnvironmentInitialized) {
        try {
          await webview_windows.WebviewController.initializeEnvironment();
        } on PlatformException catch (e) {
          if (e.code != 'environment_already_initialized') rethrow;
        }
        _windowsWebViewEnvironmentInitialized = true;
      }

      final controller = webview_windows.WebviewController();

      controller.url.listen((url) async {
        if (!mounted) return;
        if (_isTorrentOrMagnetUrl(url)) {
          await controller.stop();
          await _handleTorrentOrMagnetUrl(url);
          return;
        }
        setState(() {
          _addressController.text = url;
          _showHomeScreen = false;
        });
        _recordVisit(url);
      });

      controller.loadingState.listen((state) {
        if (!mounted) return;
        setState(() {
          _windowsIsLoading = state == webview_windows.LoadingState.loading;
        });
      });

      controller.historyChanged.listen((history) {
        if (!mounted) return;
        setState(() {
          _windowsCanGoBack = history.canGoBack;
          _windowsCanGoForward = history.canGoForward;
        });
      });

      controller.onLoadError.listen((error) {
        _captureCrashDump('WebView2 LoadError ${error.name}', null);
        setState(() => _lastLoadError = '${error.name}: ${error.toString()}');
      });

      controller.webMessage.listen((message) async {
        if (message is String && _isTorrentOrMagnetUrl(message)) {
          await _handleTorrentOrMagnetUrl(message);
          await controller.stop();
        }
      });

      try {
        await controller.initialize();
      } catch (e) {
        debugPrint('WebView init failed: $e');
        if (mounted) {
          setState(() => _webViewError = e.toString());
        }
        return;
      }

      try {
        await controller.addScriptToExecuteOnDocumentCreated('''
        function _vaultHandleTorrentProtocol(url) {
          if (!url) return false;
          if (url.startsWith('magnet:') || url.endsWith('.torrent')) {
            if (window.chrome && chrome.webview) chrome.webview.postMessage(url);
            return true;
          }
          return false;
        }
        document.addEventListener('click', function(event) {
          var target = event.target;
          while (target && target.tagName !== 'A') target = target.parentElement;
          if (!target || target.tagName !== 'A') return;
          var href = target.getAttribute('href');
          if (href && _vaultHandleTorrentProtocol(href)) event.preventDefault();
        }, true);
        var originalOpen = window.open;
        window.open = function(url, name, specs) {
          if (_vaultHandleTorrentProtocol(String(url))) return null;
          return originalOpen.apply(this, arguments);
        };
      ''');
      } catch (_) {}

      if (mounted) {
        setState(() {
          _windowsWebViewController = controller;
          _lastLoadError = null;
        });
      }

      if (!_showHomeScreen && startUrl.isNotEmpty) {
        if (_isTorrentOrMagnetUrl(startUrl)) {
          await _handleTorrentOrMagnetUrl(startUrl);
        } else {
          await controller.loadUrl(startUrl);
        }
      }
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Windows WebView init failed: $e\n$st');
      }
      _captureCrashDump('Windows WebView initialization failed: $e');
    }
  }

  // Called every time a page finishes loading — persists the URL and updates history.
  void _recordVisit(String url) {
    if (url.isEmpty || url == 'about:blank') return;

    final entry = '${DateTime.now().toIso8601String()} $url';
    setState(() {
      _history.insert(0, entry);
      if (_history.length > 500) _history.removeRange(500, _history.length);
    });

    // Persist asynchronously — never await inside listeners.
    SettingsService.instance.setBrowserLastUrl(url);
    SettingsService.instance.setBrowserHistory(_history);
  }

  bool _isFavourite(String url) => _favorites.contains(url);

  Future<void> _toggleFavourite(String url) async {
    if (url.isEmpty) return;
    setState(() {
      if (_favorites.contains(url)) {
        _favorites.remove(url);
      } else {
        _favorites.add(url);
      }
    });
    await SettingsService.instance.setBrowserFavorites(_favorites);
  }

  bool _isTorrentOrMagnetUrl(String url) =>
      TorrentService.isTorrentOrMagnetUrl(url);

  Future<String> _ensureString(dynamic value) async {
    if (value == null) return '';
    if (value is String) return value;
    if (value is Uri) return value.toString();
    if (value is Uint8List) {
      try {
        return utf8.decode(value, allowMalformed: true);
      } catch (_) {
        return value.toString();
      }
    }
    return value.toString();
  }

  Future<void> _handleTorrentOrMagnetUrl(dynamic url) async {
    final safeUrl = await _ensureString(url);
    if (safeUrl.trim().isEmpty) return;
    final normalizedUrl = safeUrl.trim();
    try {
      if (normalizedUrl.toLowerCase().startsWith('magnet:')) {
        await TorrentService.instance.addTorrentFromMagnetLink(normalizedUrl);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Magnet link added to torrent queue')),
          );
        }
        return;
      }
      if (url.toLowerCase().endsWith('.torrent')) {
        if (kIsWeb) return;
        String localPath = url;
        if (url.toLowerCase().startsWith('file://')) {
          localPath = Uri.parse(url).toFilePath();
        }
        final torrentFile = File(localPath);
        if (await torrentFile.exists()) {
          await TorrentService.instance.addTorrentFromTorrentFile(localPath);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Torrent added: $localPath')),
            );
          }
          return;
        }
        final uri = Uri.parse(url);
        if (uri.isScheme('http') || uri.isScheme('https')) {
          final client = HttpClient();
          try {
            final request = await client.getUrl(uri);
            final response = await request.close();
            if (response.statusCode != HttpStatus.ok) {
              throw HttpException('HTTP ${response.statusCode}', uri: uri);
            }
            final bytes = await consolidateHttpClientResponseBytes(response);
            final filename = uri.pathSegments.isNotEmpty
                ? uri.pathSegments.last
                : 'downloaded.torrent';
            final tmp = File(
              '${Directory.systemTemp.path}${Platform.pathSeparator}vts_${DateTime.now().millisecondsSinceEpoch}_$filename',
            );
            await tmp.writeAsBytes(bytes);
            await TorrentService.instance.addTorrentFromTorrentFile(tmp.path);
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Torrent added from $url')),
              );
            }
          } finally {
            client.close(force: true);
          }
        }
      }
    } on TorrentAlreadyExistsException catch (e) {
      final existing = await TorrentService.instance.getTorrentById(
        e.torrentId,
      );
      if (!mounted) return;
      if (existing != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Torrent already exists. Navigating to details.'),
          ),
        );
        await TorrentEngineService.instance.forceRefresh(existing.id);
        if (!mounted) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TorrentDetailScreen(torrent: existing),
          ),
        );
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Torrent exists but not found: ${e.torrentId}')),
      );
    } catch (e, st) {
      debugPrint('Failed to handle torrent link: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to handle torrent link: $e')),
        );
      }
    }
  }

  String _normalizeUrl(String value) =>
      TorrentService.normalizeTorrentUrl(value);

  Future<void> _navigateTo(String value) async {
    final url = _normalizeUrl(value.trim());
    if (url.isEmpty) return;
    _addressController.text = url;

    if (_isTorrentOrMagnetUrl(url)) {
      await _handleTorrentOrMagnetUrl(url);
      return;
    }

    setState(() => _showHomeScreen = false);

    if (Platform.isWindows && _windowsWebViewController != null) {
      await _windowsWebViewController!.loadUrl(url);
      return;
    }
    await _webViewController?.loadRequest(Uri.parse(url));
    await _refreshNavigationState();
  }

  Future<void> _refreshNavigationState() async {
    if (Platform.isWindows || _webViewController == null) return;
    final back = await _webViewController!.canGoBack();
    final fwd = await _webViewController!.canGoForward();
    if (mounted) {
      setState(() {
        _canGoBack = back;
        _canGoForward = fwd;
      });
    }
  }

  Future<void> _openExternally() async {
    final url = _addressController.text.trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _startMemoryMonitor() async {
    if (!Platform.isWindows) return;
    _memoryPollTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      try {
        if (ProcessInfo.currentRss > 1200 * 1024 * 1024) {
          await _captureCrashDump(
            'HighMemoryUsage (${ProcessInfo.currentRss ~/ (1024 * 1024)}MB)',
          );
        }
      } catch (_) {}
    });
  }

  Future<void> _captureCrashDump(
    String reason, [
    WebResourceError? error,
  ]) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File(
        '${dir.path}${Platform.pathSeparator}webview_crash_dump.log',
      );
      await file.writeAsString(
        '--- ${DateTime.now()} ---\nReason: $reason\n'
        '${error != null ? 'Error: ${error.description} (${error.errorCode})\n' : ''}'
        'URL: ${_addressController.text}\n\n',
        mode: FileMode.append,
      );
      if (Platform.isWindows) {
        await captureWindowsMiniDump(reason, dir.path);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _memoryPollTimer?.cancel();
    _windowsWebViewController?.dispose();
    _addressController.dispose();
    super.dispose();
  }

  // ── Top bar shown in BOTH tab and standalone modes ───────────────────────

  Widget _buildTopBar(ThemeData theme) {
    final currentUrl = _addressController.text.trim();
    final isFav = _isFavourite(currentUrl);
    final canBack = Platform.isWindows ? _windowsCanGoBack : _canGoBack;
    final canFwd = Platform.isWindows ? _windowsCanGoForward : _canGoForward;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            onPressed: canBack
                ? () async {
                    if (Platform.isWindows) {
                      await _windowsWebViewController?.goBack();
                    } else {
                      await _webViewController?.goBack();
                      await _refreshNavigationState();
                    }
                  }
                : null,
            tooltip: 'Back',
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward, size: 20),
            onPressed: canFwd
                ? () async {
                    if (Platform.isWindows) {
                      await _windowsWebViewController?.goForward();
                    } else {
                      await _webViewController?.goForward();
                      await _refreshNavigationState();
                    }
                  }
                : null,
            tooltip: 'Forward',
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 20),
            onPressed: () async {
              if (Platform.isWindows) {
                await _windowsWebViewController?.reload();
              } else {
                await _webViewController?.reload();
              }
            },
            tooltip: 'Reload',
          ),
          IconButton(
            icon: const Icon(Icons.home_outlined, size: 20),
            onPressed: () => setState(() => _showHomeScreen = true),
            tooltip: 'Home',
          ),
          Expanded(
            child: TextField(
              controller: _addressController,
              textInputAction: TextInputAction.go,
              onSubmitted: _navigateTo,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Enter URL or magnet link',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 7,
                ),
              ),
            ),
          ),
          // ★ Favourite toggle — fills/unfills instantly, persists on disk.
          IconButton(
            icon: Icon(
              isFav ? Icons.star : Icons.star_border,
              size: 20,
              color: isFav ? Colors.amber : null,
            ),
            onPressed: () => _toggleFavourite(currentUrl),
            tooltip: isFav ? 'Remove favourite' : 'Add favourite',
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new, size: 20),
            onPressed: _openExternally,
            tooltip: 'Open in system browser',
          ),
        ],
      ),
    );
  }

  // ── Home screen (favourites + history) ───────────────────────────────────

  Widget _buildHomeScreen(ThemeData theme) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Browser', style: theme.textTheme.headlineSmall),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.star, size: 16),
                label: const Text('Favourites'),
                onPressed: () => setState(() => _showHistory = false),
                style: TextButton.styleFrom(
                  foregroundColor: !_showHistory
                      ? theme.colorScheme.primary
                      : null,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.history, size: 16),
                label: const Text('History'),
                onPressed: () => setState(() => _showHistory = true),
                style: TextButton.styleFrom(
                  foregroundColor: _showHistory
                      ? theme.colorScheme.primary
                      : null,
                ),
              ),
              if (_showHistory && _history.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    setState(() => _history.clear());
                    await SettingsService.instance.setBrowserHistory([]);
                  },
                  child: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_showHistory)
            ..._history.map((entry) {
              final parts = entry.split(' ');
              final url = parts.length > 1 ? parts.last : entry;
              final timestamp = parts.length > 1 ? parts.first : '';
              return ListTile(
                dense: true,
                leading: const Icon(Icons.history, size: 16),
                title: Text(
                  url,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: timestamp.isNotEmpty
                    ? Text(
                        timestamp.substring(0, 10),
                        style: const TextStyle(fontSize: 11),
                      )
                    : null,
                trailing: IconButton(
                  icon: const Icon(Icons.close, size: 14),
                  onPressed: () async {
                    setState(() => _history.remove(entry));
                    await SettingsService.instance.setBrowserHistory(_history);
                  },
                ),
                onTap: () => _navigateTo(url),
              );
            })
          else ...[
            if (_favorites.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'No favourites yet. Star a page to add it.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _favorites.map((url) {
                  return InputChip(
                    avatar: const Icon(
                      Icons.star,
                      size: 14,
                      color: Colors.amber,
                    ),
                    label: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(
                        url
                            .replaceAll('https://', '')
                            .replaceAll('http://', ''),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    onPressed: () => _navigateTo(url),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () async {
                      setState(() => _favorites.remove(url));
                      await SettingsService.instance.setBrowserFavorites(
                        _favorites,
                      );
                    },
                  );
                }).toList(),
              ),
            const SizedBox(height: 20),
            const Text(
              'Quick links',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children:
                  [
                        'https://www.startpage.com/',
                        'https://duckduckgo.com/',
                        'https://news.ycombinator.com/',
                        'https://www.wikipedia.org/',
                      ]
                      .map(
                        (url) => OutlinedButton(
                          onPressed: () => _navigateTo(url),
                          child: Text(
                            url.replaceAll('https://', '').replaceAll('/', ''),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      )
                      .toList(),
            ),
          ],
        ],
      ),
    );
  }

  // ── WebView body ──────────────────────────────────────────────────────────

  Widget _buildWebViewBody() {
    if (_webViewError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.web_asset_off, size: 48, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Browser unavailable on this device'),
            const SizedBox(height: 8),
            Text(
              _webViewError!,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (Platform.isWindows) {
      if (_windowsWebViewController == null) {
        return const Center(child: CircularProgressIndicator());
      }
      return webview_windows.Webview(_windowsWebViewController!);
    }

    if (_webViewController == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return WebViewWidget(controller: _webViewController!);
  }

  Widget _buildLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Load error: $_lastLoadError',
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => _navigateTo(_addressController.text),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    final theme = Theme.of(context);
    final isLoading = Platform.isWindows ? _windowsIsLoading : _isLoading;

    final column = Column(
      children: [
        _buildTopBar(theme),
        if (isLoading)
          LinearProgressIndicator(
            value: Platform.isWindows ? null : _progress,
            minHeight: 2,
          ),
        Expanded(
          child: _showHomeScreen
              ? _buildHomeScreen(theme)
              : _lastLoadError != null
              ? _buildLoadError()
              : _buildWebViewBody(),
        ),
      ],
    );

    if (widget.inTab) return column;

    return Scaffold(body: column);
  }
}
