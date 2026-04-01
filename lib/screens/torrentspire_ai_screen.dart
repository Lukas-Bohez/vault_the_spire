import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:vault_the_spire/models/ai_chat_entry.dart';
import 'package:vault_the_spire/models/torrent.dart';
import 'package:vault_the_spire/services/ai_copilot_service.dart';
import 'package:vault_the_spire/services/ai_triggers.dart';
import 'package:vault_the_spire/services/intent_parser.dart';
import 'package:vault_the_spire/services/search_service.dart';
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

  SearchResult? _selected;
  String _category = 'All';
  String _activeModel = 'llama3';
  String _infoCardText = 'Select a torrent to generate AI analysis.';
  String _trustSignal = 'Yellow';
  bool _focusMode = false;
  bool _chatMode = false;
  bool _isSending = false;
  double _splitRatio = 0.58;

  @override
  void initState() {
    super.initState();
    _contextService.addListener(_noop);
    _searchSubscription = SearchService.instance.resultsStream.listen((items) {
      setState(() {
        _results = items;
      });
      if (items.isEmpty && _searchController.text.trim().isNotEmpty) {
        _autoPrompt(_triggers.onZeroResults(_searchController.text.trim()).prompt);
      }
    });
    _refreshTorrents();
    _torrentPoll = Timer.periodic(const Duration(seconds: 2), (_) => _refreshTorrents());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _magnetController.dispose();
    _chatController.dispose();
    _chatScroll.dispose();
    _searchSubscription?.cancel();
    _torrentPoll?.cancel();
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
      final nowComplete = (torrent.status ?? '').toLowerCase().contains('complete');
      if (nowComplete && !previousComplete.contains(torrent.id)) {
        _autoPrompt(_triggers.onDownloadCompleted(torrent.name).prompt);
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
    _contextService.updateQuery(value);
    await SearchService.instance.broadcastSearch(value);

    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (_results.isEmpty) {
        _autoPrompt(_triggers.onZeroResults(value).prompt);
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
    _autoPrompt(_triggers.onDownloadStarted(name: result.name, size: _formatSize(result.size ?? 0)).prompt);
  }

  Future<void> _selectResult(SearchResult result) async {
    setState(() {
      _selected = result;
    });
    _contextService.updateSelected(result);
    _autoPrompt(_triggers.onResultSelected(result).prompt);
    _generateInfoCard(result);
  }

  Future<void> _generateInfoCard(SearchResult result) async {
    final trust = _computeTrustSignal(result);
    setState(() {
      _trustSignal = trust;
      _infoCardText = 'Analyzing torrent metadata...';
    });

    final prompt =
        'Give a concise 2-3 sentence description for this torrent candidate: title=${result.name}, size=${result.size ?? 0} bytes, category=$_category, source=${result.responderId}. Include likely file structure and notable quality hints.';

    try {
      final stream = await _aiService.chatStream(
        model: _activeModel,
        messages: [
          {
            'role': 'system',
            'content': 'You are a torrent analysis copilot. Be concise and practical.',
          },
          {'role': 'user', 'content': prompt},
        ],
      );
      final buffer = StringBuffer();
      await for (final chunk in stream) {
        buffer.write(chunk);
      }
      if (!mounted) return;
      setState(() {
        _infoCardText = buffer.toString().trim().isEmpty
            ? 'No extra details available yet.'
            : buffer.toString().trim();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _infoCardText =
            'AI summary unavailable. Check local model endpoint and try again.';
      });
    }
  }

  String _computeTrustSignal(SearchResult result) {
    final size = result.size ?? 0;
    if (size <= 0) return 'Red';
    if (size < 50 * 1024 * 1024 && _category == 'Movies') return 'Red';
    if (result.responderId.toLowerCase().contains('local')) return 'Green';
    if (size < 200 * 1024 * 1024) return 'Yellow';
    return 'Green';
  }

  Future<void> _autoPrompt(String prompt) async {
    await _sendToAi(prompt, auto: true, visibleUserMessage: false);
  }

  Future<void> _onUserSend() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _isSending) return;
    _chatController.clear();

    final parsed = _intentParser.parse(text);
    var shouldExecuteCommand = parsed.type != TorrentIntentType.none;

    if (shouldExecuteCommand) {
      try {
        shouldExecuteCommand = await _aiService.verifyTorrentIntent(
          model: _activeModel,
          userMessage: text,
        );
      } catch (_) {
        shouldExecuteCommand = true;
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
          _messages.add(AiChatEntry(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            role: 'assistant',
            content: info,
            createdAt: DateTime.now(),
            isAuto: true,
          ));
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
        _messages.add(AiChatEntry(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          role: 'user',
          content: prompt,
          createdAt: DateTime.now(),
        ));
      }
      _messages.add(AiChatEntry(
        id: 'assist-${DateTime.now().microsecondsSinceEpoch}',
        role: 'assistant',
        content: '',
        createdAt: DateTime.now(),
        isAuto: auto,
        isStreaming: true,
      ));
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
        'content': 'You are TorrentSpire AI, an in-app torrent copilot. '
            'Always use the provided app context and reference live torrent state.',
      },
      {
        'role': 'system',
        'content': contextBlock,
      },
      ...history,
      {'role': 'user', 'content': prompt},
    ];

    try {
      final stream = await _aiService.chatStream(model: _activeModel, messages: payload);
      final buffer = StringBuffer();
      await for (final chunk in stream) {
        buffer.write(chunk);
        if (!mounted) return;
        setState(() {
          final index = _messages.lastIndexWhere((m) => m.isStreaming && m.role == 'assistant');
          if (index >= 0) {
            _messages[index] = _messages[index].copyWith(content: buffer.toString());
          }
        });
      }

      if (!mounted) return;
      setState(() {
        final index = _messages.lastIndexWhere((m) => m.isStreaming && m.role == 'assistant');
        if (index >= 0) {
          _messages[index] = _messages[index].copyWith(isStreaming: false);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        final index = _messages.lastIndexWhere((m) => m.isStreaming && m.role == 'assistant');
        if (index >= 0) {
          _messages[index] = _messages[index].copyWith(
            content: 'AI error: $e',
            isStreaming: false,
          );
        }
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isSending = false;
      });
      _scrollChatToBottom();
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
                      _splitRatio = ((_splitRatio * constraints.maxWidth) + details.delta.dx) /
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
            onPressed: () => setState(() {
              _chatMode = !_chatMode;
              if (_chatMode) {
                _focusMode = false;
              }
            }),
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
                    items: const [
                      'All',
                      'Movies',
                      'TV',
                      'Music',
                      'Software',
                      'Books',
                    ]
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _category = value;
                      });
                      _contextService.updateCategory(value);
                      _autoPrompt(_triggers.onCategoryChanged(value).prompt);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
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
              const Text('Search results', style: TextStyle(fontWeight: FontWeight.bold)),
              Expanded(
                child: ListView.builder(
                  itemCount: _results.length,
                  itemBuilder: (context, index) {
                    final item = _results[index];
                    final selected = _selected?.torrentId == item.torrentId;
                    return Card(
                      color: selected ? const Color(0xFF1F2733) : const Color(0xFF141922),
                      child: ListTile(
                        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          'Size ${_formatSize(item.size ?? 0)} | Source ${item.responderId}',
                          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
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
              const Text('Download queue', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(
                height: 120,
                child: ListView.builder(
                  itemCount: activeDownloads.length,
                  itemBuilder: (context, index) {
                    final item = activeDownloads[index];
                    final progress = (item.totalSize == null || item.totalSize == 0)
                        ? 0.0
                        : (item.bytesDown / item.totalSize!).clamp(0.0, 1.0);
                    return ListTile(
                      dense: true,
                      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: LinearProgressIndicator(value: progress),
                      trailing: Text('${(progress * 100).toStringAsFixed(1)}%'),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              const Text('Library', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(
                height: 80,
                child: ListView.builder(
                  itemCount: library.length,
                  itemBuilder: (context, index) {
                    final item = library[index];
                    return ListTile(
                      dense: true,
                      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(item.filePath ?? 'Completed', style: const TextStyle(fontSize: 11)),
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
              const Text('AI Info Card', style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: trustColor, borderRadius: BorderRadius.circular(20)),
                child: Text(
                  _trustSignal,
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(_infoCardText, maxLines: 4, overflow: TextOverflow.ellipsis),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _selected == null
                  ? null
                  : () {
                      _chatController.text = 'Tell me more about ${_selected!.name}';
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
          Expanded(
            child: ListView.builder(
              controller: _chatScroll,
              padding: const EdgeInsets.all(12),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isUser = msg.role == 'user';
                return Align(
                  alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    padding: const EdgeInsets.all(10),
                    constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.48),
                    decoration: BoxDecoration(
                      color: isUser ? const Color(0xFF2B3442) : const Color(0xFF202836),
                      borderRadius: BorderRadius.circular(12),
                      border: msg.isAuto ? Border.all(color: const Color(0xFFFFC107), width: 1.3) : null,
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
                                Icon(Icons.bolt, size: 14, color: Color(0xFFFFC107)),
                                SizedBox(width: 4),
                                Text('Auto', style: TextStyle(fontSize: 11, color: Color(0xFFFFC107))),
                              ],
                            ),
                          ),
                        MarkdownBody(
                          data: msg.content.isEmpty && msg.isStreaming ? '...' : msg.content,
                          styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                            p: const TextStyle(color: Colors.white),
                            code: const TextStyle(fontFamily: 'monospace', color: Colors.white),
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
