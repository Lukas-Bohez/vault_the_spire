import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/torrent_service.dart';

class BrowserScreen extends StatefulWidget {
  final String initialUrl;

  const BrowserScreen({super.key, this.initialUrl = 'https://duckduckgo.com/'});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  final TextEditingController _addressController = TextEditingController();
  WebViewController? _webViewController;
  bool _isLoading = true;
  double _progress = 0.0;
  bool _canGoBack = false;
  bool _canGoForward = false;
  Timer? _memoryPollTimer;

  @override
  void initState() {
    super.initState();
    _addressController.text = widget.initialUrl;
    _initWebView();
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
            });
          },
          onPageFinished: (url) async {
            _addressController.text = url;
            setState(() {
              _isLoading = false;
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
      )
      ..loadRequest(Uri.parse(widget.initialUrl));

    _webViewController = controller;
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
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to write crash dump: $e');
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
    await _webViewController?.loadRequest(Uri.parse(url));
  }

  Future<void> _refreshNavigationState() async {
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
    _addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            onPressed: _canGoBack ? () => _webViewController?.goBack() : null,
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: _canGoForward ? () => _webViewController?.goForward() : null,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _webViewController?.reload(),
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
          if (_isLoading)
            LinearProgressIndicator(value: _progress, minHeight: 3),
          Expanded(
            child: _webViewController == null
                ? const Center(child: CircularProgressIndicator())
                : WebViewWidget(controller: _webViewController!),
          ),
        ],
      ),
    );
  }
}
