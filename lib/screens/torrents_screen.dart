import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:vault_the_spire/models/torrent.dart';
import 'package:vault_the_spire/platform/drag_drop.dart';
import 'package:vault_the_spire/screens/create_torrent_screen.dart';
import 'package:vault_the_spire/screens/torrent_detail_screen.dart';
import 'package:vault_the_spire/services/settings_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vault_the_spire/services/torrent_engine_service.dart';
import 'package:vault_the_spire/services/torrent_service.dart';

// ── Sort modes ────────────────────────────────────────────────────────────────

enum _SortMode {
  dateAdded,
  nameAZ,
  nameZA,
  sizeAsc,
  sizeDesc,
  progress,
  status,
}

extension _SortLabel on _SortMode {
  String get label {
    switch (this) {
      case _SortMode.dateAdded:
        return 'Date added';
      case _SortMode.nameAZ:
        return 'Name A → Z';
      case _SortMode.nameZA:
        return 'Name Z → A';
      case _SortMode.sizeAsc:
        return 'Size smallest';
      case _SortMode.sizeDesc:
        return 'Size largest';
      case _SortMode.progress:
        return 'Progress';
      case _SortMode.status:
        return 'Status';
    }
  }

  IconData get icon {
    switch (this) {
      case _SortMode.dateAdded:
        return Icons.calendar_today_outlined;
      case _SortMode.nameAZ:
        return Icons.sort_by_alpha;
      case _SortMode.nameZA:
        return Icons.sort_by_alpha;
      case _SortMode.sizeAsc:
        return Icons.data_usage_outlined;
      case _SortMode.sizeDesc:
        return Icons.data_usage;
      case _SortMode.progress:
        return Icons.download_outlined;
      case _SortMode.status:
        return Icons.circle_outlined;
    }
  }
}

// ── Screen ────────────────────────────────────────────────────────────────────

class TorrentsScreen extends StatefulWidget {
  const TorrentsScreen({super.key});

  @override
  State<TorrentsScreen> createState() => _TorrentsScreenState();
}

class _TorrentsScreenState extends State<TorrentsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _showSearch = false;
  _SortMode _sortMode = _SortMode.dateAdded;
  bool _fabExpanded = false;

  _SortMode _sortModeFromSettings(int value) {
    if (value < 0 || value >= _SortMode.values.length) {
      return _SortMode.dateAdded;
    }
    return _SortMode.values[value];
  }

  Future<void> _loadSortMode() async {
    await SettingsService.instance.load();
    if (!mounted) return;
    setState(() {
      _sortMode = _sortModeFromSettings(
        SettingsService.instance.torrentSortMode,
      );
    });
  }

  Future<void> _setSortMode(_SortMode mode) async {
    setState(() => _sortMode = mode);
    await SettingsService.instance.setTorrentSortMode(mode.index);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadSortMode());
    unawaited(TorrentService.instance.refreshTorrentStates());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _fmtSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _fmtSpeed(double bps) {
    if (bps < 1024) return '${bps.round()} B/s';
    if (bps < 1024 * 1024) return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  Color _stateColor(BuildContext ctx, String state) {
    final cs = Theme.of(ctx).colorScheme;
    if (state.contains('seed')) return cs.tertiary;
    if (state.contains('download')) return cs.primary;
    if (state.contains('error') || state.contains('stall')) return cs.error;
    if (state.contains('pause')) return cs.outline;
    return cs.outlineVariant;
  }

  List<TorrentViewState> _sorted(List<TorrentViewState> all) {
    var list = all.toList();

    // Search filter
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((t) => t.name.toLowerCase().contains(q)).toList();
    }

    // Sort
    list.sort((a, b) {
      switch (_sortMode) {
        case _SortMode.dateAdded:
          return (b.model.addedAt ?? 0).compareTo(a.model.addedAt ?? 0);
        case _SortMode.nameAZ:
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case _SortMode.nameZA:
          return b.name.toLowerCase().compareTo(a.name.toLowerCase());
        case _SortMode.sizeAsc:
          return (a.model.totalSize ?? 0).compareTo(b.model.totalSize ?? 0);
        case _SortMode.sizeDesc:
          return (b.model.totalSize ?? 0).compareTo(a.model.totalSize ?? 0);
        case _SortMode.progress:
          return b.progress.compareTo(a.progress);
        case _SortMode.status:
          return a.statusLabel.compareTo(b.statusLabel);
      }
    });

    return list;
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _refresh() async {
    await TorrentService.instance.refreshTorrentStates();
  }

  Future<void> _toggleTorrent(TorrentViewState ts) async {
    try {
      if (ts.isActive) {
        await TorrentEngineService.instance.stopTorrent(ts.model.id);
        await TorrentService.instance.updateTorrentStatus(
          ts.model.id,
          'paused',
        );
      } else {
        await TorrentEngineService.instance.startTorrent(ts.model.id);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to toggle: $e')));
    }
    await TorrentService.instance.refreshTorrentStates();
  }

  Future<void> _redownloadTorrent(TorrentViewState ts) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Redownload from scratch?'),
        content: Text(
          '"${ts.model.name}" will be deleted and re-downloaded from 0%. '
          'The .torrent source file is preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Redownload'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await TorrentEngineService.instance.forceRedownload(ts.model.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${ts.name}" restarted from scratch.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Redownload failed: $e')));
    }
    await TorrentService.instance.refreshTorrentStates();
  }

  Future<void> _deleteTorrent(TorrentViewState ts) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove torrent?'),
        content: Text(
          '"${ts.name}" will be removed from the list. '
          'Downloaded files are NOT deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await TorrentEngineService.instance.stopTorrent(ts.model.id);
      await TorrentService.instance.removeTorrent(ts.model.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Torrent removed.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Remove failed: $e')));
    }
  }

  Future<void> _openTorrentFolder(TorrentModel torrent) async {
    final String pathToOpen;
    if (torrent.filePath != null && torrent.filePath!.isNotEmpty) {
      final lp = torrent.filePath!.toLowerCase();
      pathToOpen = lp.endsWith('.torrent')
          ? SettingsService.instance.downloadDestination
          : torrent.filePath!;
    } else {
      pathToOpen = SettingsService.instance.downloadDestination;
    }

    if (pathToOpen.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No download folder configured.')),
      );
      return;
    }

    final String directoryPath;
    if (Directory(pathToOpen).existsSync()) {
      directoryPath = pathToOpen;
    } else if (File(pathToOpen).existsSync()) {
      directoryPath = File(pathToOpen).parent.path;
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Folder does not exist.')));
      return;
    }

    // Android: file:// URIs throw FileUriExposedException — show path instead
    if (Platform.isAndroid) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Files saved to:\n$directoryPath'),
          duration: const Duration(seconds: 6),
          action: SnackBarAction(label: 'OK', onPressed: () {}),
        ),
      );
      return;
    }

    try {
      final uri = Uri.file(directoryPath);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to open folder.')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not open folder: $e')));
    }
  }

  Future<void> _pickTorrentFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowMultiple: false,
        allowedExtensions: const <String>[],
      );
      final path = result?.files.single.path;
      if (path == null || path.isEmpty) {
        return;
      }
      await TorrentService.instance.addTorrentFromTorrentFile(path);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Torrent added from file.')));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add torrent file: $e')));
    }
  }

  Future<void> _openCreateTorrent() async {
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CreateTorrentScreen()));
  }

  Future<void> _handleDropPath(String path) async {
    try {
      if (path.toLowerCase().endsWith('.torrent')) {
        await TorrentService.instance.addTorrentFromTorrentFile(path);
      } else {
        await TorrentService.instance.addTorrentFromPath(path);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Torrent added via drag & drop.')),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
    }
  }

  Future<void> _showAddMagnetDialog() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add torrent'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Paste magnet link (magnet:?xt=...)',
            prefixIcon: Icon(Icons.link),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || result.isEmpty || !mounted) return;
    try {
      await TorrentService.instance.addTorrentFromMagnetLink(result);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Torrent added!')));
    } on TorrentAlreadyExistsException {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This torrent is already in your list.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add: $e')));
    }
  }

  Widget _buildFab() {
    if (!Platform.isAndroid) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (_fabExpanded) ...[
          FloatingActionButton.small(
            heroTag: 'create_torrent_fab',
            onPressed: _openCreateTorrent,
            tooltip: 'Create torrent',
            child: const Icon(Icons.create_new_folder_outlined),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.small(
            heroTag: 'pick_torrent_fab',
            onPressed: _pickTorrentFile,
            tooltip: 'Pick .torrent file',
            child: const Icon(Icons.file_open_outlined),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'paste_magnet_fab',
            onPressed: _showAddMagnetDialog,
            icon: const Icon(Icons.add_link),
            label: const Text('Paste magnet'),
          ),
          const SizedBox(height: 8),
        ],
        FloatingActionButton(
          heroTag: 'torrent_fab_toggle',
          onPressed: () => setState(() => _fabExpanded = !_fabExpanded),
          tooltip: _fabExpanded ? 'Close actions' : 'Add torrent',
          child: Icon(_fabExpanded ? Icons.close : Icons.add),
        ),
      ],
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: _buildAppBar(),
      floatingActionButton: _buildFab(),
      body: TorrentDragDrop(
        onTorrentFile: _handleDropPath,
        onPath: _handleDropPath,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: StreamBuilder<List<TorrentViewState>>(
            stream: TorrentService.instance.torrentStatesStream,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final all = snapshot.data!;
              final torrents = _sorted(all);

              // Empty: no torrents at all
              if (all.isEmpty) {
                return _buildEmptyState();
              }

              // Empty: search returned nothing
              if (torrents.isEmpty) {
                return _buildNoSearchResults();
              }

              return ListView.builder(
                cacheExtent: 200,
                padding: EdgeInsets.only(bottom: Platform.isAndroid ? 96 : 12),
                itemCount: torrents.length,
                itemBuilder: (context, index) =>
                    _buildTorrentCard(context, torrents[index]),
              );
            },
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: _showSearch
          ? TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search torrents…',
                border: InputBorder.none,
                hintStyle: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              style: Theme.of(context).textTheme.titleMedium,
              onChanged: (v) => setState(() => _searchQuery = v.trim()),
            )
          : const Text('Torrents'),
      actions: [
        // Search toggle
        IconButton(
          icon: Icon(_showSearch ? Icons.close : Icons.search),
          tooltip: _showSearch ? 'Cancel search' : 'Search torrents',
          onPressed: () => setState(() {
            _showSearch = !_showSearch;
            if (!_showSearch) {
              _searchQuery = '';
              _searchController.clear();
            }
          }),
        ),
        // Sort popup
        PopupMenuButton<_SortMode>(
          icon: const Icon(Icons.sort),
          tooltip: 'Sort by',
          onSelected: _setSortMode,
          itemBuilder: (ctx) => _SortMode.values
              .map(
                (m) => PopupMenuItem<_SortMode>(
                  value: m,
                  child: Row(
                    children: [
                      Icon(
                        m.icon,
                        size: 16,
                        color: _sortMode == m
                            ? Theme.of(ctx).colorScheme.primary
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        m.label,
                        style: TextStyle(
                          fontWeight: _sortMode == m
                              ? FontWeight.w700
                              : FontWeight.normal,
                          color: _sortMode == m
                              ? Theme.of(ctx).colorScheme.primary
                              : null,
                        ),
                      ),
                      if (_sortMode == m) ...[
                        const Spacer(),
                        Icon(
                          Icons.check,
                          size: 14,
                          color: Theme.of(ctx).colorScheme.primary,
                        ),
                      ],
                    ],
                  ),
                ),
              )
              .toList(),
        ),
        // Open download folder (desktop only)
        if (!Platform.isAndroid)
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Open download folder',
            onPressed: () async {
              final pseudo = TorrentModel(
                id: '',
                name: '',
                type: 'magnet_link',
                filePath: SettingsService.instance.downloadDestination,
              );
              await _openTorrentFolder(pseudo);
            },
          ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
          onPressed: _refresh,
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.download_for_offline_outlined,
              size: 72,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No torrents yet',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              Platform.isAndroid
                  ? 'Tap + to paste a magnet link'
                  : 'Drag and drop a .torrent file\nor paste a magnet link',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            if (Platform.isAndroid) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _showAddMagnetDialog,
                icon: const Icon(Icons.add_link),
                label: const Text('Add magnet link'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildNoSearchResults() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off,
            size: 56,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
          const SizedBox(height: 12),
          Text(
            'No results for "$_searchQuery"',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => setState(() {
              _searchQuery = '';
              _searchController.clear();
              _showSearch = false;
            }),
            child: const Text('Clear search'),
          ),
        ],
      ),
    );
  }

  Widget _buildTorrentCard(BuildContext context, TorrentViewState ts) {
    final torrent = ts.model;
    final progress = ts.progress.clamp(0.0, 1.0);
    final stateColor = _stateColor(context, ts.state);
    final cs = Theme.of(context).colorScheme;

    void copyMagnetLink() {
      final magnet = torrent.magnetLink;
      if (magnet != null && magnet.isNotEmpty) {
        Clipboard.setData(ClipboardData(text: magnet));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Magnet link copied')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No magnet link available')),
        );
      }
    }

    return Card(
      key: ValueKey(ts.id),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => TorrentDetailScreen(torrent: torrent),
          ),
        ),
        onLongPress: copyMagnetLink,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
          child: Row(
            children: [
              // Main content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Name
                    Text(
                      torrent.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 7),
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 5,
                        backgroundColor: cs.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation(stateColor),
                      ),
                    ),
                    const SizedBox(height: 5),
                    // Status row
                    Row(
                      children: [
                        // Status badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: stateColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            ts.statusLabel,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: stateColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Progress %
                        Text(
                          '${(progress * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        // Size
                        if (torrent.totalSize != null &&
                            torrent.totalSize! > 0) ...[
                          Text(
                            ' / ${_fmtSize(torrent.totalSize!)}',
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                        const Spacer(),
                        // Download speed
                        if (ts.downloadSpeed > 512) ...[
                          Icon(
                            Icons.arrow_downward,
                            size: 10,
                            color: cs.primary,
                          ),
                          Text(
                            _fmtSpeed(ts.downloadSpeed),
                            style: TextStyle(fontSize: 10, color: cs.primary),
                          ),
                        ],
                        // Upload speed
                        if (ts.uploadSpeed > 512) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_upward,
                            size: 10,
                            color: cs.tertiary,
                          ),
                          Text(
                            _fmtSpeed(ts.uploadSpeed),
                            style: TextStyle(fontSize: 10, color: cs.tertiary),
                          ),
                        ],
                        // Peers
                        if (ts.peers > 0) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.people_outline,
                            size: 10,
                            color: cs.onSurfaceVariant,
                          ),
                          Text(
                            '${ts.peers}',
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // Action menu
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 20),
                tooltip: 'More',
                onSelected: (v) {
                  switch (v) {
                    case 'toggle':
                      _toggleTorrent(ts);
                      break;
                    case 'folder':
                      _openTorrentFolder(torrent);
                      break;
                    case 'copy':
                      copyMagnetLink();
                      break;
                    case 'redownload':
                      _redownloadTorrent(ts);
                      break;
                    case 'delete':
                      _deleteTorrent(ts);
                      break;
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'toggle',
                    child: ListTile(
                      dense: true,
                      leading: Icon(
                        ts.isActive
                            ? Icons.pause_circle_outline
                            : Icons.play_circle_outline,
                      ),
                      title: Text(ts.isActive ? 'Pause' : 'Resume'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'folder',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.folder_open),
                      title: Text('Open folder'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'copy',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.link),
                      title: Text('Copy magnet link'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'redownload',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.replay),
                      title: Text('Redownload from scratch'),
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: ListTile(
                      dense: true,
                      leading: Icon(Icons.delete_outline),
                      title: Text('Remove'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
