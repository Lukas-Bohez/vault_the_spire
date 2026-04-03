import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vault_the_spire/models/torrent.dart';
import 'package:vault_the_spire/platform/drag_drop.dart';
import 'package:vault_the_spire/services/settings_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vault_the_spire/services/torrent_engine_service.dart';
import 'package:vault_the_spire/services/torrent_service.dart';

class TorrentsScreen extends StatefulWidget {
  const TorrentsScreen({super.key});

  @override
  State<TorrentsScreen> createState() => _TorrentsScreenState();
}

class _TorrentsScreenState extends State<TorrentsScreen> {
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

  @override
  Widget build(BuildContext context) {
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
                return const Center(child: CircularProgressIndicator());
              }
              final torrents = snapshot.data!;
              if (torrents.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 100),
                    Center(
                      child: Text(
                        'No torrents yet. Drag and drop .torrent files.',
                      ),
                    ),
                  ],
                );
              }

              return ListView.builder(
                itemCount: torrents.length,
                itemBuilder: (context, index) {
                  final torrentState = torrents[index];
                  final torrent = torrentState.model;
                  final compactRows = SettingsService.instance.compactTorrentRows;
                  final narrowActions = MediaQuery.of(context).size.width < 700;
                  final progress = torrentState.progress.clamp(0.0, 1.0);
                  final speedText = torrentState.isSeeding
                      ? '${(torrentState.uploadSpeed / 1024).toStringAsFixed(1)} KB/s up'
                      : '${(torrentState.downloadSpeed / 1024).toStringAsFixed(1)} KB/s down';

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

                  final actionButton = narrowActions
                      ? PopupMenuButton<String>(
                          tooltip: 'More actions',
                          onSelected: (value) {
                            switch (value) {
                              case 'folder':
                                _openTorrentFolder(torrent);
                                break;
                              case 'toggle':
                                _toggleTorrent(torrentState);
                                break;
                              case 'copy':
                                copyMagnetLink();
                                break;
                              case 'delete':
                                _deleteTorrent(torrentState);
                                break;
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem<String>(
                              value: 'folder',
                              child: Text('Open folder'),
                            ),
                            PopupMenuItem<String>(
                              value: 'toggle',
                              child: Text(torrentState.isActive ? 'Pause' : 'Play'),
                            ),
                            const PopupMenuItem<String>(
                              value: 'copy',
                              child: Text('Copy magnet link'),
                            ),
                            const PopupMenuDivider(),
                            const PopupMenuItem<String>(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                          child: const Icon(Icons.more_vert),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.folder_open),
                              tooltip: 'Open folder',
                              onPressed: () => _openTorrentFolder(torrent),
                            ),
                            IconButton(
                              icon: Icon(
                                torrentState.isActive ? Icons.pause : Icons.play_arrow,
                              ),
                              tooltip: torrentState.isActive ? 'Pause' : 'Play',
                              onPressed: () => _toggleTorrent(torrentState),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy),
                              tooltip: 'Copy magnet link',
                              onPressed: copyMagnetLink,
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              tooltip: 'Delete',
                              onPressed: () => _deleteTorrent(torrentState),
                            ),
                          ],
                        );

                  return Card(
                    margin: EdgeInsets.symmetric(
                      horizontal: compactRows ? 8 : 12,
                      vertical: compactRows ? 3 : 6,
                    ),
                    child: ListTile(
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: compactRows ? 10 : 12,
                        vertical: compactRows ? 4 : 8,
                      ),
                      title: Text(torrent.name, overflow: TextOverflow.ellipsis),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          LinearProgressIndicator(value: progress),
                          const SizedBox(height: 4),
                          Text(
                            '${torrentState.statusLabel} • ${(progress * 100).toStringAsFixed(1)}% • ${torrentState.peers} peers • $speedText',
                          ),
                        ],
                      ),
                      onLongPress: copyMagnetLink,
                      trailing: actionButton,
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}