import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vault_the_spire/models/torrent.dart';
import 'package:vault_the_spire/platform/drag_drop.dart';
import 'package:vault_the_spire/screens/torrent_detail_screen.dart';
import 'package:vault_the_spire/services/settings_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vault_the_spire/services/torrent_engine_service.dart';
import 'package:vault_the_spire/services/torrent_service.dart';

class TorrentsScreen extends StatefulWidget {
  const TorrentsScreen({super.key});

  @override
  State<TorrentsScreen> createState() => _TorrentsScreenState();
}

class _TorrentsScreenState extends State<TorrentsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Color _statusColor(BuildContext context, String state) {
    final cs = Theme.of(context).colorScheme;
    final normalized = state.toLowerCase();
    if (normalized.contains('seed')) return cs.tertiary;
    if (normalized.contains('download')) return cs.primary;
    if (normalized.contains('error')) return cs.error;
    if (normalized.contains('paused')) return cs.outline;
    return cs.outlineVariant;
  }

  IconData _statusIcon(String state) {
    final normalized = state.toLowerCase();
    if (normalized.contains('seed')) return Icons.upload_rounded;
    if (normalized.contains('download')) return Icons.download_rounded;
    if (normalized.contains('paused')) return Icons.pause_circle_outline;
    if (normalized.contains('error')) return Icons.error_outline;
    if (normalized.contains('pending')) return Icons.hourglass_empty;
    return Icons.circle_outlined;
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var unitIndex = 0;
    while (value >= 1024 && unitIndex < units.length - 1) {
      value /= 1024;
      unitIndex++;
    }
    return '${value.toStringAsFixed(unitIndex == 0 ? 0 : 1)} ${units[unitIndex]}';
  }

  @override
  void initState() {
    super.initState();
    unawaited(TorrentService.instance.refreshTorrentStates());
  }

  Future<void> _refresh() async {
    await TorrentService.instance.refreshTorrentStates();
  }

  Future<void> _toggleTorrent(TorrentViewState torrentState) async {
    final torrent = torrentState.model;
    try {
      if (torrentState.isActive) {
        TorrentEngineService.instance.stopTorrent(torrent.id);
        await TorrentService.instance.updateTorrentStatus(torrent.id, 'paused');
      } else {
        await TorrentEngineService.instance.startTorrent(torrent.id);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to toggle torrent: $e')));
    }
    await TorrentService.instance.refreshTorrentStates();
  }

  Future<void> _deleteTorrent(TorrentViewState torrentState) async {
    final torrent = torrentState.model;
    try {
      TorrentEngineService.instance.stopTorrent(torrent.id);
      await TorrentService.instance.removeTorrent(torrent.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Torrent removed.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to delete torrent: $e')));
    }
    await TorrentService.instance.refreshTorrentStates();
  }

  Future<void> _redownloadTorrent(TorrentViewState torrentState) async {
    final torrent = torrentState.model;
    try {
      TorrentEngineService.instance.stopTorrent(torrent.id);
      await TorrentService.instance.removeTorrent(torrent.id);
      if (torrent.type == 'magnet_link' &&
          torrent.magnetLink != null &&
          torrent.magnetLink!.isNotEmpty) {
        await TorrentService.instance.addTorrentFromMagnetLink(
          torrent.magnetLink!,
        );
      } else if (torrent.filePath != null && torrent.filePath!.isNotEmpty) {
        await TorrentService.instance.addTorrentFromTorrentFile(
          torrent.filePath!,
        );
      } else {
        throw StateError('No source available to redownload this torrent');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Torrent re-added.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to redownload torrent: $e')));
    }
    await TorrentService.instance.refreshTorrentStates();
  }

  Future<void> _recheckTorrent(TorrentViewState torrentState) async {
    try {
      final result = await TorrentEngineService.instance.recheckTorrent(
        torrentState.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['isValid'] == true
                ? 'Recheck complete: all pieces valid.'
                : 'Recheck complete: ${result['invalidPieces']} piece(s) need re-download.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Recheck failed: $e')),
      );
    }
  }

  Future<void> _openTorrentFolder(TorrentModel torrent) async {
    final String pathToOpen;
    if (torrent.filePath != null && torrent.filePath!.isNotEmpty) {
      final lowerPath = torrent.filePath!.toLowerCase();
      if (lowerPath.endsWith('.torrent')) {
        pathToOpen = SettingsService.instance.downloadDestination;
      } else {
        pathToOpen = torrent.filePath!;
      }
    } else {
      pathToOpen = SettingsService.instance.downloadDestination;
    }

    if (pathToOpen.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No path available to open.')),
      );
      return;
    }

    String directoryPath;

    if (Directory(pathToOpen).existsSync()) {
      directoryPath = pathToOpen;
    } else if (File(pathToOpen).existsSync()) {
      directoryPath = File(pathToOpen).parent.path;
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Specified path does not exist.')),
      );
      return;
    }

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

    final uri = Uri.file(directoryPath);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Failed to open folder.')));
    }
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
        const SnackBar(content: Text('Torrent path added via drag & drop.')),
      );
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to import dropped path: $e')),
      );
    }
  }

  Future<void> _showAddMagnetDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add torrent'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Paste magnet link here',
            prefixIcon: Icon(Icons.link),
          ),
          minLines: 1,
          maxLines: 4,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == null || result.isEmpty || !mounted) return;

    try {
      await TorrentService.instance.addTorrentFromMagnetLink(result);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Torrent added!')));
      await _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Torrents'),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open),
            tooltip: 'Go to download folder',
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
      ),
      body: TorrentDragDrop(
        onTorrentFile: _handleDropPath,
        onPath: _handleDropPath,
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: StreamBuilder<List<TorrentViewState>>(
            stream: TorrentService.instance.torrentStatesStream,
            builder: (context, snapshot) {
              if (!snapshot.hasData) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 120),
                    Center(child: CircularProgressIndicator()),
                    SizedBox(height: 12),
                    Center(child: Text('Loading torrents...')),
                  ],
                );
              }

              final torrents = snapshot.data!;
              if (torrents.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    const SizedBox(height: 100),
                    Center(
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
                              'Tap + to add a magnet link\nor browse and pick a torrent',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: _showAddMagnetDialog,
                              icon: const Icon(Icons.add),
                              label: const Text('Add magnet link'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }

              return ListView.builder(
                itemCount: torrents.length,
                cacheExtent: 200,
                itemBuilder: (context, index) {
                  final torrentState = torrents[index];
                  final torrent = torrentState.model;
                  final progress = torrentState.progress.clamp(0.0, 1.0);
                  final stateColor = _statusColor(context, torrentState.state);

                  void copyMagnetLink() {
                    final magnet = torrent.magnetLink;
                    if (magnet != null && magnet.isNotEmpty) {
                      Clipboard.setData(ClipboardData(text: magnet));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Magnet link copied to clipboard'),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No magnet link available for this torrent'),
                        ),
                      );
                    }
                  }

                  return RepaintBoundary(
                    child: Card(
                      key: ValueKey(torrentState.id),
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => TorrentDetailScreen(torrent: torrent),
                          ),
                        ),
                        onLongPress: copyMagnetLink,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    _statusIcon(torrentState.state),
                                    color: stateColor,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      torrent.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(Icons.more_vert, size: 20),
                                    onSelected: (v) {
                                      switch (v) {
                                        case 'toggle':
                                          _toggleTorrent(torrentState);
                                          break;
                                        case 'folder':
                                          _openTorrentFolder(torrent);
                                          break;
                                        case 'copy':
                                          copyMagnetLink();
                                          break;
                                        case 'recheck':
                                          _recheckTorrent(torrentState);
                                          break;
                                        case 'redownload':
                                          _redownloadTorrent(torrentState);
                                          break;
                                        case 'delete':
                                          _deleteTorrent(torrentState);
                                          break;
                                      }
                                    },
                                    itemBuilder: (_) => [
                                      PopupMenuItem(
                                        value: 'toggle',
                                        child: ListTile(
                                          dense: true,
                                          leading: Icon(
                                            torrentState.isActive
                                                ? Icons.pause
                                                : Icons.play_arrow,
                                          ),
                                          title: Text(
                                            torrentState.isActive ? 'Pause' : 'Resume',
                                          ),
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'folder',
                                        child: ListTile(
                                          dense: true,
                                          leading: Icon(Icons.folder_open),
                                          title: Text('Show location'),
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'copy',
                                        child: ListTile(
                                          dense: true,
                                          leading: Icon(Icons.link),
                                          title: Text('Copy magnet'),
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'recheck',
                                        child: ListTile(
                                          dense: true,
                                          leading: Icon(Icons.fact_check_outlined),
                                          title: Text('Recheck files'),
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'redownload',
                                        child: ListTile(
                                          dense: true,
                                          leading: Icon(Icons.replay),
                                          title: Text('Redownload'),
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
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: progress,
                                        minHeight: 6,
                                        backgroundColor: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest,
                                        valueColor: AlwaysStoppedAnimation(stateColor),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 44,
                                    child: Text(
                                      '${(progress * 100).toStringAsFixed(1)}%',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      textAlign: TextAlign.right,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: stateColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      torrentState.statusLabel,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: stateColor,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.people_outline,
                                    size: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    '${torrentState.peers}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (torrentState.isSeeding &&
                                      torrentState.uploadSpeed > 0) ...[
                                    Icon(
                                      Icons.arrow_upward,
                                      size: 11,
                                      color: Theme.of(context).colorScheme.tertiary,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      '${_formatBytes(torrentState.uploadSpeed.round())}/s',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context).colorScheme.tertiary,
                                      ),
                                    ),
                                  ] else if (torrentState.downloadSpeed > 0) ...[
                                    Icon(
                                      Icons.arrow_downward,
                                      size: 11,
                                      color: Theme.of(context).colorScheme.primary,
                                    ),
                                    const SizedBox(width: 2),
                                    Text(
                                      '${_formatBytes(torrentState.downloadSpeed.round())}/s',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context).colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                  if (torrent.totalSize != null && torrent.totalSize! > 0) ...[
                                    const SizedBox(width: 8),
                                    Text(
                                      '${_formatBytes((progress * torrent.totalSize!).round())} / ${_formatBytes(torrent.totalSize!)}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
      floatingActionButton: Platform.isAndroid
          ? FloatingActionButton.extended(
              onPressed: _showAddMagnetDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add torrent'),
            )
          : null,
    );
  }
}