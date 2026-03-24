import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as webview_windows;
import 'package:win32/win32.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/settings_service.dart';
import '../services/torrent_service.dart';

class BrowserScreen extends StatefulWidget {
  final String initialUrl;
  final bool inTab;

  const BrowserScreen({
    super.key,
    this.initialUrl = 'https://duckduckgo.com/',
    this.inTab = false,
  });

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  static bool _windowsWebViewEnvironmentInitialized = false;

  final TextEditingController _addressController = TextEditingController();

  // Browser controls.
  late String _homeUrl;
  bool _showHomeScreen = true;
  late List<String> _favorites;
  bool _showHistory = false;
  final List<String> _history = [];

  // Flutter WebView for non-Windows platforms (or fallback).
  WebViewController? _webViewController;
  bool _isLoading = true;
  double _progress = 0.0;
  bool _canGoBack = false;
  bool _canGoForward = false;

  // Windows WebView2 controller path.
  webview_windows.WebviewController? _windowsWebViewController;
  bool _windowsCanGoBack = false;
  bool _windowsCanGoForward = false;
  bool _windowsIsLoading = true;
  String? _lastLoadError;

  Timer? _memoryPollTimer;

  @override
  void initState() {
    super.initState();

    _homeUrl = SettingsService.instance.browserHomeUrl;
    _favorites = List<String>.from(SettingsService.instance.browserFavorites);
    _addressController.text = widget.initialUrl.isNotEmpty
        ? widget.initialUrl
        : _homeUrl;

    if (Platform.isWindows) {
      _initWindowsWebView();
    } else {
      _initWebView();
    }
    _startMemoryMonitor();
  }

  void _initWebView() {
    final controller = WebViewController();
    controller
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
            _captureCrashDump('WebResourceError', error);
            if (kDebugMode) {
              debugPrint('Web resource error: ${error.description}');
            }
          },
        ),
      );

    _webViewController = controller;
  }

  Future<void> _initWindowsWebView() async {
    try {
      if (!_windowsWebViewEnvironmentInitialized) {
        try {
          await webview_windows.WebviewController.initializeEnvironment();
        } on PlatformException catch (e) {
          if (e.code != 'environment_already_initialized') {
            rethrow;
          }
        }
        _windowsWebViewEnvironmentInitialized = true;
      }

      final controller = webview_windows.WebviewController();

      controller.url.listen((url) async {
        if (!mounted) return;

        if (_isTorrentOrMagnetUrl(url)) {
          await controller.stop();
          await _handleTorrentOrMagnetUrl(url);
          setState(() {
            _showHomeScreen = true;
          });
          return;
        }

        setState(() {
          _addressController.text = url;
          _showHomeScreen = false;
          _history.insert(0, '${DateTime.now().toIso8601String()} $url');
          if (_history.length > 100) {
            _history.removeRange(100, _history.length);
          }
        });
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
        setState(() {
          _lastLoadError = '${error.name}: ${error.toString()}';
        });
      });

      controller.webMessage.listen((message) async {
        if (message is String && _isTorrentOrMagnetUrl(message)) {
          await _handleTorrentOrMagnetUrl(message);
          await controller.stop();
          setState(() {
            _showHomeScreen = true;
          });
        }
      });

      await controller.initialize();

      try {
        await controller.addScriptToExecuteOnDocumentCreated('''
        function _vaultHandleTorrentProtocol(url) {
          if (!url) return false;
          if (url.startsWith('magnet:') || url.endsWith('.torrent')) {
            if (window.chrome && chrome.webview) {
              chrome.webview.postMessage(url);
            }
            return true;
          }
          return false;
        }

        document.addEventListener('click', function(event) {
          var target = event.target;
          while (target && target.tagName !== 'A') {
            target = target.parentElement;
          }
          if (!target || target.tagName !== 'A') return;
          var href = target.getAttribute('href');
          if (!href) return;
          if (_vaultHandleTorrentProtocol(href)) {
            event.preventDefault();
          }
        }, true);

        var originalOpen = window.open;
        window.open = function(url, name, specs) {
          if (_vaultHandleTorrentProtocol(String(url))) {
            return null;
          }
          return originalOpen.apply(this, arguments);
        };

        var originalAssign = window.location.assign;
        window.location.assign = function(url) {
          if (_vaultHandleTorrentProtocol(String(url))) {
            return;
          }
          return originalAssign.apply(this, arguments);
        };

        var originalReplace = window.location.replace;
        window.location.replace = function(url) {
          if (_vaultHandleTorrentProtocol(String(url))) {
            return;
          }
          return originalReplace.apply(this, arguments);
        };
      ''');
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Could not inject magnet handler script: $e');
        }
      }

      if (mounted) {
        setState(() {
          _windowsWebViewController = controller;
          _lastLoadError = null;
        });
      }

      if (!_showHomeScreen) {
        if (_isTorrentOrMagnetUrl(widget.initialUrl)) {
          await _handleTorrentOrMagnetUrl(widget.initialUrl);
        } else {
          await controller.loadUrl(widget.initialUrl);
        }
      }
    } catch (e, st) {
      var reason = 'Windows WebView initialization failed: $e';
      if (e is PlatformException &&
          e.code == 'environment_already_initialized') {
        reason = 'Windows WebView environment already initialized';
      }
      if (kDebugMode) {
        debugPrint(reason);
        debugPrint(st.toString());
      }
      _captureCrashDump(reason);
    }
  }
  Future<void> _startMemoryMonitor() async {
    if (!Platform.isWindows) return; // focus on WebView2 Windows crash-dump target

    _memoryPollTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      try {
        final rssBytes = ProcessInfo.currentRss;
        if (rssBytes > 1200 * 1024 * 1024) {
          await _captureCrashDump('HighMemoryUsage (RSS ${rssBytes ~/ (1024 * 1024)}MB)');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('Memory monitor failed: $e');
      }
    });
  }

  Future<void> _captureCrashDump(String reason, [WebResourceError? error]) async {
    try {
      final directory = await getApplicationSupportDirectory();
      final file = File('${directory.path}${Platform.pathSeparator}webview_crash_dump.log');
      final now = DateTime.now();

      final lines = <String>[
        '--- Crash dump @ $now ---',
        'Reason: $reason',
        'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
        'Memory RSS: ${ProcessInfo.currentRss} bytes',
        'Available virtual memory: ${ProcessInfo.maxRss} bytes',
        if (error != null) 'WebResourceError: ${error.description} (${error.errorCode})',
        'Current URL: ${_addressController.text}',
        '-------------------------',
      ];

      await file.writeAsString('${lines.join('\n')}\n', mode: FileMode.append);

      if (kDebugMode) {
        debugPrint('WebView crash dump saved to ${file.path}');
      }

      if (Platform.isWindows) {
        await _captureWindowsMiniDump(reason);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to write crash dump: $e');
    }
  }

  Future<void> _captureWindowsMiniDump(String reason) async {
    try {
      final directory = await getApplicationSupportDirectory();
      final filename =
          'webview_crash_${DateTime.now().toIso8601String().replaceAll(':', '-')}.dmp';
      final path = '${directory.path}${Platform.pathSeparator}$filename';

      final hFile = CreateFile(TEXT(path), GENERIC_WRITE, 0,
          Pointer<SECURITY_ATTRIBUTES>.fromAddress(0), CREATE_ALWAYS,
          FILE_ATTRIBUTE_NORMAL, NULL);
      if (hFile == INVALID_HANDLE_VALUE) {
        if (kDebugMode) {
          debugPrint('Could not create dump file at $path');
        }
        return;
      }

      final process = GetCurrentProcess();
      final pid = GetCurrentProcessId();
      final dbghelp = DynamicLibrary.open('Dbghelp.dll');

      final miniDumpWriteDump = dbghelp.lookupFunction<
          Int32 Function(IntPtr, Uint32, IntPtr, Uint32, IntPtr, IntPtr, IntPtr),
          int Function(int, int, int, int, int, int, int)>('MiniDumpWriteDump');

      const int miniDumpWithDataSegs = 0x00000001;
      const int miniDumpWithHandleData = 0x00000004;
      const int dumpType = miniDumpWithDataSegs | miniDumpWithHandleData;

      final success = miniDumpWriteDump(process, pid, hFile, dumpType, 0, 0, 0);

      CloseHandle(hFile);

      if (success == 0) {
        if (kDebugMode) {
          debugPrint('MiniDumpWriteDump failed: ${GetLastError()}');
        }
      } else {
        if (kDebugMode) {
          debugPrint('MiniDump written to $path for reason: $reason');
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to capture mini dump: $e');
    }
  }

  bool _isTorrentOrMagnetUrl(String url) {
    final lower = url.trim().toLowerCase();
    return lower.startsWith('magnet:') || lower.endsWith('.torrent');
  }

  Future<void> _handleTorrentOrMagnetUrl(String url) async {
    if (url.trim().isEmpty) return;

    try {
      if (url.toLowerCase().startsWith('magnet:')) {
        await TorrentService.instance.addTorrentFromMagnetLink(url);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Magnet link added to torrent queue')),
          );
        }
        return;
      }

      if (url.toLowerCase().endsWith('.torrent')) {
        if (kIsWeb) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Torrent file download is not supported on web.')),
            );
          }
          return;
        }

        final uri = Uri.parse(url);
        final client = HttpClient();
        try {
          final request = await client.getUrl(uri);
          final response = await request.close();
          if (response.statusCode != HttpStatus.ok) {
            throw HttpException('Failed to download torrent file', uri: uri);
          }

          final fileBytes = await consolidateHttpClientResponseBytes(response);

          final filename = uri.pathSegments.isNotEmpty
              ? uri.pathSegments.last
              : 'downloaded.torrent';
          final tempFile = File(
            '${Directory.systemTemp.path}${Platform.pathSeparator}vault_the_spire_${DateTime.now().millisecondsSinceEpoch}_$filename',
          );
          await tempFile.writeAsBytes(fileBytes);
          await TorrentService.instance.addTorrentFromTorrentFile(tempFile.path);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Torrent file added from URL: ${uri.toString()}')),
            );
          }
        } finally {
          client.close(force: true);
        }
        return;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to handle torrent link: ')),
        );
      }
    }
  }

  String _normalizeUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    return 'https://';
  }

  Future<void> _navigateTo(String value) async {
    final url = _normalizeUrl(value);
    if (url.isEmpty) return;
    _addressController.text = url;

    if (_isTorrentOrMagnetUrl(url)) {
      await _handleTorrentOrMagnetUrl(url);
      return;
    }

    _showHomeScreen = false;

    if (Platform.isWindows && _windowsWebViewController != null) {
      await _windowsWebViewController?.loadUrl(url);
      setState(() {
        _showHomeScreen = false;
        _history.insert(0, '${DateTime.now().toIso8601String()} $url');
        if (_history.length > 100) {
          _history.removeRange(100, _history.length);
        }
      });
      return;
    }

    await _webViewController?.loadRequest(Uri.parse(url));
    await _refreshNavigationState();
    setState(() {
      _showHomeScreen = false;
      _history.insert(0, '${DateTime.now().toIso8601String()} $url');
      if (_history.length > 100) {
        _history.removeRange(100, _history.length);
      }
    });
  }

  Future<void> _refreshNavigationState() async {
    if (Platform.isWindows && _windowsWebViewController != null) {
      // History updates are pushed via historyChanged stream.
      return;
    }

    if (_webViewController == null) return;
    final canGoBack = await _webViewController!.canGoBack();
    final canGoForward = await _webViewController!.canGoForward();
    setState(() {
      _canGoBack = canGoBack;
      _canGoForward = canGoForward;
    });
  }

  Future<void> _openExternally() async {
    final url = _addressController.text.trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void dispose() {
    _memoryPollTimer?.cancel();
    _windowsWebViewController?.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Widget _buildBrowserContent(ThemeData theme) {
    return Column(
      children: [
        _buildBrowserTopBar(theme),
        if (Platform.isWindows ? _windowsIsLoading : _isLoading)
          LinearProgressIndicator(
            value: Platform.isWindows ? null : _progress,
            minHeight: 3,
          ),
        Expanded(
          child: _showHomeScreen
              ? SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Home', style: theme.textTheme.headlineMedium),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _showHistory = false;
                                  });
                                },
                                child: const Text('Favorites'),
                              ),
                              TextButton(
                                onPressed: () {
                                  setState(() {
                                    _showHistory = true;
                                  });
                                },
                                child: const Text('History'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_showHistory)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: _history.map((entry) {
                            return ListTile(
                              dense: true,
                              title: Text(entry,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 12)),
                              onTap: () {
                                final url = entry.split(' ').last;
                                _navigateTo(url);
                              },
                            );
                          }).toList(),
                        )
                      else
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: _favorites.map((url) {
                            return InputChip(
                              label: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 180),
                                child: Text(url,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: false),
                              ),
                              onPressed: () {
                                _navigateTo(url);
                              },
                              deleteIcon: const Icon(Icons.close),
                              onDeleted: () async {
                                setState(() {
                                  _favorites.remove(url);
                                });
                                await SettingsService.instance
                                    .setBrowserFavorites(_favorites);
                              },
                            );
                          }).toList(),
                        ),
                      const SizedBox(height: 20),
                      const Text('Quick links',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          'https://www.startpage.com/',
                          'https://www.duckduckgo.com/',
                          'https://news.ycombinator.com/',
                          'https://www.wikipedia.org/',
                        ].map((url) {
                          return ElevatedButton(
                            onPressed: () {
                              _navigateTo(url);
                            },
                            child: Text(url.replaceAll('https://', ''),
                                overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                )
              : (Platform.isWindows
                  ? (_windowsWebViewController == null
                      ? const Center(child: CircularProgressIndicator())
                      : webview_windows.Webview(_windowsWebViewController!))
                  : (_webViewController == null
                      ? const Center(child: CircularProgressIndicator())
                      : WebViewWidget(controller: _webViewController!))),
        ),
      ],
    );
  }

  Widget _buildBrowserTopBar(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _addressController,
              textInputAction: TextInputAction.go,
              onSubmitted: _navigateTo,
              decoration: const InputDecoration(
                hintText: 'Enter URL or magnet link',
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: (Platform.isWindows ? _windowsCanGoBack : _canGoBack)
                ? () async {
                    if (Platform.isWindows) {
                      await _windowsWebViewController?.goBack();
                    } else {
                      await _webViewController?.goBack();
                      await _refreshNavigationState();
                    }
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: (Platform.isWindows ? _windowsCanGoForward : _canGoForward)
                ? () async {
                    if (Platform.isWindows) {
                      await _windowsWebViewController?.goForward();
                    } else {
                      await _webViewController?.goForward();
                      await _refreshNavigationState();
                    }
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              if (Platform.isWindows) {
                await _windowsWebViewController?.reload();
              } else {
                await _webViewController?.reload();
              }
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget content = _buildBrowserContent(theme);

    if (widget.inTab) {
      return content;
    }

    return Scaffold(
      appBar: AppBar(
        title: SizedBox(
          height: 36,
          child: TextField(
            controller: _addressController,
            textInputAction: TextInputAction.go,
            onSubmitted: _navigateTo,
            decoration: const InputDecoration(
              hintText: 'Enter URL or magnet link',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: (Platform.isWindows ? _windowsCanGoBack : _canGoBack)
                ? () async {
                    if (Platform.isWindows) {
                      await _windowsWebViewController?.goBack();
                    } else {
                      await _webViewController?.goBack();
                      await _refreshNavigationState();
                    }
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: (Platform.isWindows ? _windowsCanGoForward : _canGoForward)
                ? () async {
                    if (Platform.isWindows) {
                      await _windowsWebViewController?.goForward();
                    } else {
                      await _webViewController?.goForward();
                      await _refreshNavigationState();
                    }
                  }
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              if (Platform.isWindows) {
                await _windowsWebViewController?.reload();
              } else {
                await _webViewController?.reload();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () async {
              _showHomeScreen = true;
              _addressController.text = _homeUrl;
              await _navigateTo(_homeUrl);
            },
            tooltip: 'Go home',
          ),
          IconButton(
            icon: const Icon(Icons.home_filled),
            onPressed: () async {
              final current = _addressController.text.trim();
              if (current.isEmpty) return;
              final messenger = ScaffoldMessenger.of(context);
              await SettingsService.instance.setBrowserHomeUrl(current);
              if (!mounted) return;
              setState(() {
                _homeUrl = current;
              });
              messenger.showSnackBar(
                const SnackBar(content: Text('Home URL updated')),
              );
            },
            tooltip: 'Set current page as home',
          ),
          IconButton(
            icon: Icon(_favorites.contains(_addressController.text.trim())
                ? Icons.star
                : Icons.star_border),
            onPressed: () async {
              final url = _addressController.text.trim();
              if (url.isEmpty) return;
              setState(() {
                if (_favorites.contains(url)) {
                  _favorites.remove(url);
                } else {
                  _favorites.add(url);
                }
              });
              await SettingsService.instance.setBrowserFavorites(_favorites);
            },
            tooltip: 'Toggle favorite',
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new),
            onPressed: _openExternally,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _handleTorrentOrMagnetUrl(_addressController.text),
            tooltip: 'Add URL to torrents if valid magnet/.torrent',
          ),
        ],
      ),
      body: Column(
        children: [
          if (Platform.isWindows ? _windowsIsLoading : _isLoading)
            LinearProgressIndicator(
              value: Platform.isWindows ? null : _progress,
              minHeight: 3,
            ),
          Expanded(
            child: _showHomeScreen
                ? SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Home', style: theme.textTheme.headlineMedium),
                            Row(
                              children: [
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _showHistory = false;
                                    });
                                  },
                                  child: const Text('Favorites'),
                                ),
                                TextButton(
                                  onPressed: () {
                                    setState(() {
                                      _showHistory = true;
                                    });
                                  },
                                  child: const Text('History'),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_showHistory)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _history.map((entry) {
                              return ListTile(
                                dense: true,
                                title: Text(entry,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12)),
                                onTap: () {
                                  final url = entry.split(' ').last;
                                  _navigateTo(url);
                                },
                              );
                            }).toList(),
                          )
                        else
                          Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: _favorites.map((url) {
                            return InputChip(
                              label: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 180),
                                child: Text(url,
                                    overflow: TextOverflow.ellipsis,
                                    softWrap: false),
                              ),
                              onPressed: () {
                                _navigateTo(url);
                              },
                              deleteIcon: const Icon(Icons.close),
                              onDeleted: () async {
                                setState(() {
                                  _favorites.remove(url);
                                });
                                await SettingsService.instance.setBrowserFavorites(_favorites);
                              },
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 20),
                        const Text('Quick links', style: TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            'https://www.startpage.com/',
                            'https://www.duckduckgo.com/',
                            'https://news.ycombinator.com/',
                            'https://www.wikipedia.org/',
                          ].map((url) {
                            return ElevatedButton(
                              onPressed: () {
                                _navigateTo(url);
                              },
                              child: Text(url.replaceAll('https://', ''), overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  )
                : _lastLoadError != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Load error: $_lastLoadError',
                                  style: const TextStyle(color: Colors.red)),
                              const SizedBox(height: 12),
                              ElevatedButton(
                                onPressed: () {
                                  _navigateTo(_addressController.text);
                                },
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : (Platform.isWindows
                        ? (_windowsWebViewController == null
                            ? const Center(child: CircularProgressIndicator())
                            : webview_windows.Webview(_windowsWebViewController!))
                        : (_webViewController == null
                            ? const Center(child: CircularProgressIndicator())
                            : WebViewWidget(controller: _webViewController!))),
          ),
        ],
      ),
    );
  }
}
