import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:vault_the_spire/models/ai_chat_entry.dart';
import 'package:vault_the_spire/models/torrent.dart';
import 'package:vault_the_spire/services/ai_copilot_service.dart';
import 'package:vault_the_spire/services/ai_triggers.dart';
import 'package:vault_the_spire/services/intent_parser.dart';
import 'package:vault_the_spire/services/search_service.dart';
import 'package:vault_the_spire/services/settings_service.dart';
import 'package:vault_the_spire/services/torrent_context.dart';
import 'package:vault_the_spire/services/torrent_service.dart';

class TorrentSpireAiScreen extends StatefulWidget {
  const TorrentSpireAiScreen({super.key});

  @override
  State<TorrentSpireAiScreen> createState() => _TorrentSpireAiScreenState();
}

class _TorrentSpireAiScreenState extends State<TorrentSpireAiScreen> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _magnetController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScroll = ScrollController();

  final AiCopilotService _aiService = AiCopilotService();
  final TorrentContextService _contextService = TorrentContextService();
  final AiTriggers _triggers = AiTriggers();
  final IntentParser _intentParser = IntentParser();

  final List<AiChatEntry> _messages = <AiChatEntry>[];
  List<SearchResult> _results = <SearchResult>[];
  List<TorrentModel> _torrents = <TorrentModel>[];

  StreamSubscription<List<SearchResult>>? _searchSubscription;
  Timer? _torrentPoll;
  // Timer? _settingsSyncTimer; // TODO: re-enable periodic sync

  SearchResult? _selected;
  String _category = 'All';
  String _activeModel = 'llama3';
  String _cachedAiUrl = '';
  String _cachedAiModel = '';
  String _infoCardText = 'Select a torrent to generate AI analysis.';
  String _trustSignal = 'Yellow';
  bool _aiReady = false;
  bool _infoCardLoading = false;
  bool _resolvingMagnet = false;
  bool _focusMode = false;
  bool _chatMode = false;
  bool _isSending = false;
  double _splitRatio = 0.58;
  final Set<String> _triggeredEventKeys = <String>{};
  final List<AiTriggerEvent> _queuedAutoEvents = <AiTriggerEvent>[];

  @override
  void initState() {
    super.initState();
    _activeModel = SettingsService.instance.aiDefaultModel;
    _cachedAiModel = _activeModel;
    final url = SettingsService.instance.aiOllamaUrl;
    _aiService.setBaseUrl(url);
    _cachedAiUrl = url;
    _contextService.addListener(_noop);
    _searchSubscription = SearchService.instance.resultsStream.listen((items) {
      setState(() {
        _results = items;
      });
      if (items.isEmpty && _searchController.text.trim().isNotEmpty) {
        _triggerAutoEvent(
          _triggers.onZeroResults(_searchController.text.trim()),
        );
      }
    });
    _refreshTorrents();
    _torrentPoll = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshTorrents(),
    );
    // TODO: Re-enable periodic sync after debugging blank screen
    // _settingsSyncTimer = Timer.periodic(
    //   const Duration(seconds: 5),
    //   (_) {
    //     if (mounted) {
    //       try {
    //         _syncAiSettings().ignore();
    //       } catch (e) {
    //         debugPrint('Settings sync error: $e');
    //       }
    //     }
    //   },
    // );
    // Verify AI connection immediately
    _checkAiReadiness();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _magnetController.dispose();
    _chatController.dispose();
    _chatScroll.dispose();
    _searchSubscription?.cancel();
    _torrentPoll?.cancel();
    // _settingsSyncTimer?.cancel(); // TODO: re-enable
    _contextService.removeListener(_noop);
    _contextService.dispose();
    super.dispose();
  }

  void _noop() {}

  Future<void> _refreshTorrents() async {
    final all = await TorrentService.instance.allTorrents();
    final previousComplete = _torrents
        .where((t) => (t.status ?? '').toLowerCase().contains('complete'))
        .map((t) => t.id)
        .toSet();

    _contextService.updateTorrents(all);

    for (final torrent in all) {
      final nowComplete = (torrent.status ?? '').toLowerCase().contains(
        'complete',
      );
      if (nowComplete && !previousComplete.contains(torrent.id)) {
        _triggerAutoEvent(_triggers.onDownloadCompleted(torrent.name));
      }
    }

    if (mounted) {
      setState(() {
        _torrents = all;
      });
    }
  }

  Future<void> _performSearch(String query) async {
    final value = query.trim();
    if (value.isEmpty) return;

    if (value.toLowerCase().startsWith('magnet:?xt=')) {
      setState(() {
        _resolvingMagnet = true;
      });
      try {
        await TorrentService.instance
            .addTorrentFromMagnetLink(value)
            .timeout(const Duration(seconds: 30));
        _magnetController.clear();
      } on TimeoutException {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Resolving metadata timed out after 30 seconds. Please retry.',
            ),
          ),
        );
      } finally {
        if (mounted) {
          setState(() {
            _resolvingMagnet = false;
          });
        }
      }
      return;
    }

    _contextService.updateQuery(value);
    await SearchService.instance.broadcastSearch(value);

    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (_results.isEmpty) {
        _triggerAutoEvent(_triggers.onZeroResults(value));
      }
    });
  }

  Future<void> _addMagnet() async {
    final text = _magnetController.text.trim();
    if (text.isEmpty) return;
    await TorrentService.instance.addTorrentFromMagnetLink(text);
    _magnetController.clear();
    await _refreshTorrents();
  }

  Future<void> _startDownload(SearchResult result) async {
    if (result.magnetLink.isEmpty) return;
    await TorrentService.instance.addTorrentFromMagnetLink(result.magnetLink);
    await _refreshTorrents();
    _triggerAutoEvent(
      _triggers.onDownloadStarted(
        name: result.name,
        size: _formatSize(result.size ?? 0),
      ),
    );
  }

  Future<void> _selectResult(SearchResult result) async {
    setState(() {
      _selected = result;
    });
    _contextService.updateSelected(result);
    _triggerAutoEvent(_triggers.onResultSelected(result));
    // Ensure AI is ready before generating info card
    await _syncAiSettings();
    await _generateInfoCard(result);
  }

  Future<void> _generateInfoCard(SearchResult result) async {
    final trust = _computeTrustSignal(result);
    setState(() {
      _infoCardLoading = true;
      _trustSignal = trust;
      _infoCardText = 'Analyzing torrent metadata...';
    });

    final prompt =
        'Give a concise 2-3 sentence description for this torrent candidate: title=${result.name}, size=${result.size ?? 0} bytes, category=$_category, source=${result.responderId}. Include likely file structure and notable quality hints.';

    if (!mounted) return;
    
    if (!_aiReady) {
      setState(() {
        _infoCardLoading = false;
        _trustSignal = 'Neutral';
        _infoCardText = 'AI not connected. Check Settings > AI Settings and verify Ollama is running.';
      });
      return;
    }

    // Validate that the model exists
    final modelExists = await _aiService.modelExists(_activeModel);
    if (!modelExists) {
      if (!mounted) return;
      setState(() {
        _infoCardLoading = false;
        _trustSignal = 'Neutral';
        _infoCardText = 'Model "$_activeModel" not found. Download it in Settings > Local AI Chat.';
      });
      return;
    }

    try {
      final stream = await _aiService.chatChunkStream(
        model: _activeModel,
        messages: [
          {
            'role': 'system',
            'content':
                'You are a torrent analysis copilot. Be concise and practical.',
          },
          {'role': 'user', 'content': prompt},
        ],
      );
      final buffer = StringBuffer();
      await for (final chunk in stream) {
        buffer.write(chunk.content);
        if (chunk.done) break;
      }
      if (!mounted) return;
      setState(() {
        _infoCardLoading = false;
        _infoCardText = buffer.toString().trim().isEmpty
            ? 'No extra details available yet.'
            : buffer.toString().trim();
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('AI analysis failed: $e');
      setState(() {
        _infoCardLoading = false;
        _trustSignal = 'Neutral';
        _infoCardText = 'AI analysis failed: $e';
      });
    }
  }

  String _computeTrustSignal(SearchResult result) {
    final size = result.size;
    final seeders = result.seeders;
    final age = result.ageYears;

    final plausibleMovie = size == null || size >= 500 * 1024 * 1024;

    if ((seeders != null && seeders < 10) ||
        (age != null && age > 5) ||
        (_category == 'Movies' && !plausibleMovie)) {
      return 'Red';
    }
    if ((seeders != null && seeders > 50) &&
        (age != null && age < 2) &&
        (_category != 'Movies' || plausibleMovie)) {
      return 'Green';
    }
    return 'Yellow';
  }

  Future<void> _triggerAutoEvent(AiTriggerEvent event) async {
    if (_triggeredEventKeys.contains(event.key)) return;
    _triggeredEventKeys.add(event.key);
    if (_isSending) {
      _queuedAutoEvents.add(event);
      return;
    }
    await _sendToAi(event.prompt, auto: true, visibleUserMessage: false);
  }

  Future<void> _onUserSend() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _isSending) return;
    _chatController.clear();

    final parsed = _intentParser.parse(text);
    var shouldExecuteCommand = false;

    if (_intentParser.passesKeywordGate(text) &&
        parsed.type != TorrentIntentType.none) {
      try {
        shouldExecuteCommand = await _aiService.verifyTorrentIntent(
          model: _activeModel,
          userMessage: text,
          timeout: const Duration(seconds: 2),
        );
      } catch (_) {
        shouldExecuteCommand = false;
      }
    }

    if (shouldExecuteCommand) {
      await _executeIntent(parsed);
    }

    await _sendToAi(text, auto: false, visibleUserMessage: true);
  }

  Future<void> _executeIntent(TorrentIntent intent) async {
    switch (intent.type) {
      case TorrentIntentType.search:
        if (intent.payload.isNotEmpty) {
          _searchController.text = intent.payload;
          await _performSearch(intent.payload);
        }
        break;
      case TorrentIntentType.downloadTop:
        if (_results.isNotEmpty) {
          await _startDownload(_results.first);
        }
        break;
      case TorrentIntentType.whatsDownloading:
        break;
      case TorrentIntentType.safetyCheck:
        break;
      case TorrentIntentType.betterVersion:
        if (_selected != null) {
          await _performSearch('${_selected!.name} 1080p verified');
        }
        break;
      case TorrentIntentType.diskSpace:
        final usedByLibrary = _contextService.library.fold<int>(
          0,
          (sum, item) => sum + (item.totalSize ?? 0),
        );
        final info =
            'Local library currently uses about ${_formatSize(usedByLibrary)}.';
        setState(() {
          _messages.add(
            AiChatEntry(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              role: 'assistant',
              content: info,
              createdAt: DateTime.now(),
              isAutoTriggered: true,
            ),
          );
        });
        _scrollChatToBottom();
        break;
      case TorrentIntentType.none:
        break;
    }
  }

  Future<void> _sendToAi(
    String prompt, {
    required bool auto,
    required bool visibleUserMessage,
  }) async {
    setState(() {
      _isSending = true;
      if (visibleUserMessage) {
        _messages.add(
          AiChatEntry(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            role: 'user',
            content: prompt,
            createdAt: DateTime.now(),
          ),
        );
      }
      _messages.add(
        AiChatEntry(
          id: 'assist-${DateTime.now().microsecondsSinceEpoch}',
          role: 'assistant',
          content: '',
          createdAt: DateTime.now(),
          isAutoTriggered: auto,
          isStreaming: true,
        ),
      );
    });
    _scrollChatToBottom();

    final contextBlock = _contextService.getContext();
    final history = _messages
        .where((m) => !m.isStreaming && m.content.trim().isNotEmpty)
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    final payload = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content':
            'You are TorrentSpire AI, an in-app torrent copilot. '
            'Always use the provided app context and reference live torrent state.',
      },
      {'role': 'system', 'content': contextBlock},
      ...history,
      {'role': 'user', 'content': prompt},
    ];

    try {
      final stream = await _aiService.chatChunkStream(
        model: _activeModel,
        messages: payload,
      );
      if (mounted && !_aiReady) {
        setState(() {
          _aiReady = true;
        });
      }
      final buffer = StringBuffer();
      var sawDone = false;
      await for (final chunk in stream) {
        buffer.write(chunk.content);
        if (chunk.done) {
          sawDone = true;
        }
        if (!mounted) return;
        setState(() {
          final index = _messages.lastIndexWhere(
            (m) => m.isStreaming && m.role == 'assistant',
          );
          if (index >= 0) {
            _messages[index] = _messages[index].copyWith(
              content: buffer.toString(),
            );
          }
        });
        if (chunk.done) break;
      }

      if (!mounted) return;
      setState(() {
        final index = _messages.lastIndexWhere(
          (m) => m.isStreaming && m.role == 'assistant',
        );
        if (index >= 0) {
          _messages[index] = _messages[index].copyWith(
            content: sawDone
                ? _messages[index].content
                : '${_messages[index].content} [connection lost]',
            isStreaming: false,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _aiReady = false;
        final index = _messages.lastIndexWhere(
          (m) => m.isStreaming && m.role == 'assistant',
        );
        if (index >= 0) {
          _messages[index] = _messages[index].copyWith(
            content:
                'AI copilot offline — check your Ollama connection in Settings. ($e)',
            isStreaming: false,
          );
        }
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isSending = false;
      });
      if (_queuedAutoEvents.isNotEmpty) {
        final next = _queuedAutoEvents.removeAt(0);
        unawaited(
          _sendToAi(next.prompt, auto: true, visibleUserMessage: false),
        );
      }
      _scrollChatToBottom();
    }
  }

  Future<void> _checkAiReadiness() async {
    final ok = await _aiService.checkVersion();
    if (!mounted) return;
    setState(() {
      _aiReady = ok;
    });
  }

  Future<void> _syncAiSettings() async {
    final currentUrl = SettingsService.instance.aiOllamaUrl;
    final currentModel = SettingsService.instance.aiDefaultModel;

    if (_cachedAiUrl != currentUrl || _cachedAiModel != currentModel) {
      if (_cachedAiUrl != currentUrl) {
        _aiService.setBaseUrl(currentUrl);
        _cachedAiUrl = currentUrl;
        _aiReady = false; // Reset ready status when URL changes
        // Verify connection with new URL
        final ok = await _aiService.checkVersion();
        if (mounted) {
          setState(() {
            _aiReady = ok;
          });
        }
      }
      if (_cachedAiModel != currentModel) {
        _activeModel = currentModel;
        _cachedAiModel = currentModel;
      }
    }
  }

  void _scrollChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_chatScroll.hasClients) return;
      _chatScroll.animateTo(
        _chatScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.of(context).size.width < 900;

    final torrentPane = _buildTorrentPane(context);
    final chatPane = _buildChatPane(context);

    Widget content;
    if (_focusMode) {
      content = torrentPane;
    } else if (_chatMode) {
      content = Row(
        children: [
          SizedBox(width: 220, child: torrentPane),
          const VerticalDivider(width: 1),
          Expanded(child: chatPane),
        ],
      );
    } else if (isNarrow) {
      content = Column(
        children: [
          Expanded(flex: 6, child: torrentPane),
          const Divider(height: 1),
          Expanded(flex: 5, child: chatPane),
        ],
      );
    } else {
      content = LayoutBuilder(
        builder: (context, constraints) {
          final left = constraints.maxWidth * _splitRatio;
          return Row(
            children: [
              SizedBox(width: left, child: torrentPane),
              MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      _splitRatio =
                          ((_splitRatio * constraints.maxWidth) +
                              details.delta.dx) /
                          constraints.maxWidth;
                      _splitRatio = _splitRatio.clamp(0.3, 0.75);
                    });
                  },
                  child: Container(width: 8, color: Colors.black12),
                ),
              ),
              Expanded(child: chatPane),
            ],
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('TorrentSpire AI'),
        actions: [
          IconButton(
            tooltip: 'Focus mode',
            onPressed: () => setState(() {
              _focusMode = !_focusMode;
              if (_focusMode) {
                _chatMode = false;
              }
            }),
            icon: Icon(_focusMode ? Icons.view_week : Icons.filter_none),
          ),
          IconButton(
            tooltip: 'Chat mode',
            onPressed: () {
              setState(() {
                _chatMode = !_chatMode;
                if (_chatMode) {
                  _focusMode = false;
                }
              });
              if (_chatMode) {
                _syncAiSettings();
                if (!_aiReady) {
                  _checkAiReadiness();
                }
              }
            },
            icon: Icon(_chatMode ? Icons.chat : Icons.open_in_full),
          ),
        ],
      ),
      body: content,
    );
  }

  Widget _buildTorrentPane(BuildContext context) {
    final activeDownloads = _contextService.activeDownloads;
    final library = _contextService.library;

    return Container(
      color: const Color(0xFF0F1115),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white70),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Search torrents',
                        labelStyle: TextStyle(color: Colors.white70),
                        prefixIcon: Icon(Icons.search),
                      ),
                      onSubmitted: _performSearch,
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _category,
                    dropdownColor: const Color(0xFF1A1F27),
                    items:
                        const [
                              'All',
                              'Movies',
                              'TV',
                              'Music',
                              'Software',
                              'Books',
                            ]
                            .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            )
                            .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _category = value;
                      });
                      _contextService.updateCategory(value);
                      _triggerAutoEvent(_triggers.onCategoryChanged(value));
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (_resolvingMagnet)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Resolving metadata...'),
                    ],
                  ),
                ),
              TextField(
                controller: _magnetController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Paste magnet link',
                  hintStyle: const TextStyle(color: Colors.white54),
                  suffixIcon: IconButton(
                    onPressed: _addMagnet,
                    icon: const Icon(Icons.add_link),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Search results',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final item = _results[index];
                    final selected = _selected?.torrentId == item.torrentId;
                    final safeTitle = item.name.length > 60
                        ? '${item.name.substring(0, 60)}...'
                        : item.name;
                    final sl =
                        'S: ${item.seeders?.toString() ?? '—'} / L: ${item.leechers?.toString() ?? '—'}';
                    final age = item.ageYears == null
                        ? '—'
                        : (item.ageYears == 0
                              ? 'this year'
                              : '${item.ageYears} years ago');
                    final source = item.source.isEmpty ? '—' : item.source;
                    return Card(
                      color: selected
                          ? const Color(0xFF1F2733)
                          : const Color(0xFF141922),
                      child: ListTile(
                        title: Text(
                          safeTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '$sl | Size ${item.size == null ? '—' : _formatSize(item.size!)} | Source $source | Age $age',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        onTap: () => _selectResult(item),
                        trailing: IconButton(
                          onPressed: () => _startDownload(item),
                          icon: const Icon(Icons.download),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Download queue',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(
                height: 120,
                child: ListView.builder(
                  itemCount: activeDownloads.length,
                  itemBuilder: (context, index) {
                    final item = activeDownloads[index];
                    final progress =
                        (item.totalSize == null || item.totalSize == 0)
                        ? 0.0
                        : (item.bytesDown / item.totalSize!).clamp(0.0, 1.0);
                    return ListTile(
                      dense: true,
                      title: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: LinearProgressIndicator(value: progress),
                      trailing: Text('${(progress * 100).toStringAsFixed(1)}%'),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Library',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(
                height: 80,
                child: ListView.builder(
                  itemCount: library.length,
                  itemBuilder: (context, index) {
                    final item = library[index];
                    return ListTile(
                      dense: true,
                      title: Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        item.filePath ?? 'Completed',
                        style: const TextStyle(fontSize: 11),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              _buildInfoCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    Color trustColor;
    switch (_trustSignal) {
      case 'Green':
        trustColor = const Color(0xFF4CAF50);
        break;
      case 'Red':
        trustColor = const Color(0xFFF44336);
        break;
      case 'Neutral':
        trustColor = const Color(0xFF9E9E9E);
        break;
      default:
        trustColor = const Color(0xFFFFC107);
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF121A26),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'AI Info Card',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: trustColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _trustSignal,
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_infoCardLoading)
            const LinearProgressIndicator()
          else
            Text(_infoCardText, maxLines: 4, overflow: TextOverflow.ellipsis),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _selected == null
                  ? null
                  : () {
                      _chatController.text =
                          'Tell me more about ${_selected!.name}';
                    },
              child: const Text('Tell me more'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatPane(BuildContext context) {
    return Container(
      color: const Color(0xFF151920),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: _aiReady ? const Color(0xFF1B5E20) : const Color(0xFFFFA000),
            child: Text(
              _aiReady
                  ? 'AI Ready'
                  : 'AI copilot offline — check your Ollama connection in Settings',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: _chatScroll,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg.role == 'user';
                return Align(
                  alignment: isUser
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(10),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.48,
                    ),
                    decoration: BoxDecoration(
                      color: isUser
                          ? const Color(0xFF2B3442)
                          : const Color(0xFF202836),
                      borderRadius: BorderRadius.circular(12),
                      border: msg.isAuto
                          ? Border.all(
                              color: const Color(0xFFFFC107),
                              width: 1.3,
                            )
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (msg.isAuto)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 6),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.bolt,
                                  size: 14,
                                  color: Color(0xFFFFC107),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Auto',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFFFFC107),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        MarkdownBody(
                          data: msg.content.isEmpty && msg.isStreaming
                              ? '...'
                              : msg.content,
                          styleSheet:
                              MarkdownStyleSheet.fromTheme(
                                Theme.of(context),
                              ).copyWith(
                                p: const TextStyle(color: Colors.white),
                                code: const TextStyle(
                                  fontFamily: 'monospace',
                                  color: Colors.white,
                                ),
                                codeblockDecoration: BoxDecoration(
                                  color: const Color(0xFF101418),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _chatController,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        hintStyle: TextStyle(color: Colors.white60),
                      ),
                      onSubmitted: (_) => _onUserSend(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _isSending ? null : _onUserSend,
                    child: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }
}
