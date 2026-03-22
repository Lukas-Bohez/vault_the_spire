import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path/path.dart' as p;
import 'package:vault_the_spire/models/torrent.dart';
import 'package:vault_the_spire/platform/desktop_window.dart';
import 'package:vault_the_spire/platform/drag_drop.dart';
import 'package:vault_the_spire/screens/torrent_detail_screen.dart';
import 'package:vault_the_spire/services/torrent_service.dart';

class TorrentsScreen extends StatefulWidget {
  const TorrentsScreen({super.key});

  @override
  State<TorrentsScreen> createState() => _TorrentsScreenState();
}

class _TorrentsScreenState extends State<TorrentsScreen> {
  late Future<List<TorrentModel>> _futureTorrents;

  @override
  void initState() {
    super.initState();
    _futureTorrents = TorrentService.instance.allTorrents();
  }

  Future<void> _refresh() async {
    setState(() {
      _futureTorrents = TorrentService.instance.allTorrents();
    });
  }

  Future<void> _importTorrent(String path) async {
    try {
      await TorrentService.instance.addTorrentFromTorrentFile(path);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Torrent imported successfully.')),
      );
    } on FileSystemException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File system error: ${e.message}')),
      );
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Torrent parsing error: ${e.message}')),
      );
    } on StateError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to import torrent: $e')));
    }
  }

  Future<void> _showMagnetInputDialog() async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Add Magnet Link'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'magnet:?xt=...'),
            keyboardType: TextInputType.url,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      final link = controller.text.trim();
      if (link.isNotEmpty) {
        try {
          await TorrentService.instance.addTorrentFromMagnetLink(link);
          await _refresh();
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Magnet link added.')));
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to add magnet: $e')));
        }
      }
    }
  }

  Future<void> _toggleFullScreen() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final messenger = ScaffoldMessenger.of(context);
      await toggleDesktopFullScreen();
      if (!mounted) return;
      final currentlyFullScreen = await windowManager.isFullScreen();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            currentlyFullScreen ? 'Entered full screen' : 'Exited full screen',
          ),
        ),
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
            icon: const Icon(Icons.add_link),
            tooltip: 'Add magnet link',
            onPressed: _showMagnetInputDialog,
          ),
          IconButton(
            icon: const Icon(Icons.fullscreen),
            tooltip: 'Toggle fullscreen (desktop)',
            onPressed: _toggleFullScreen,
          ),
          IconButton(
            icon: const Icon(Icons.file_upload),
            tooltip: 'Import .torrent file',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Drag and drop a .torrent file into the panel'),
                ),
              );
            },
          ),
        ],
      ),
      body: FutureBuilder<List<TorrentModel>>(
        future: _futureTorrents,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final torrents = snapshot.data ?? [];
          if (torrents.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TorrentDragDrop(
                    onTorrentFile: (path) {
                      _importTorrent(path);
                    },
                  ),
                  const SizedBox(height: 12),
                  const Text('No torrents yet'),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        onPressed: _refresh,
                        child: const Text('Refresh'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _showMagnetInputDialog,
                        child: const Text('Add Magnet'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              itemCount: torrents.length,
              itemBuilder: (context, index) {
                final torrent = torrents[index];
                final progress =
                    torrent.totalPieces != null && torrent.totalPieces! > 0
                    ? (torrent.piecesHave
                                  ?.split(',')
                                  .where((x) => x == '1')
                                  .length ??
                              0) /
                          torrent.totalPieces!
                    : 0.0;
                return Card(
                  child: ListTile(
                    title: Text(torrent.name),
                    subtitle: Text(
                      'Status: ${torrent.status ?? 'unknown'} • ${(progress * 100).toStringAsFixed(1)}%',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) async {
                        try {
                          if (value == 'pause') {
                            await TorrentService.instance.updateTorrentStatus(
                              torrent.id,
                              'paused',
                            );
                          } else if (value == 'resume') {
                            await TorrentService.instance.updateTorrentStatus(
                              torrent.id,
                              'downloading',
                            );
                          } else if (value == 'remove') {
                            await TorrentService.instance.removeTorrent(
                              torrent.id,
                            );
                          } else if (value == 'open') {
                            final path = torrent.filePath;
                            if (path != null &&
                                path.isNotEmpty &&
                                File(path).existsSync()) {
                              await Process.start(
                                Platform.isWindows
                                    ? 'explorer'
                                    : (Platform.isMacOS ? 'open' : 'xdg-open'),
                                [Platform.isWindows ? p.dirname(path) : path],
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('File path not available.'),
                                ),
                              );
                            }
                          }
                          await _refresh();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Action executed: $value')),
                          );
                        } catch (e) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed action $value: $e')),
                          );
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'pause', child: Text('Pause')),
                        PopupMenuItem(value: 'resume', child: Text('Resume')),
                        PopupMenuItem(
                          value: 'open',
                          child: Text('Open folder'),
                        ),
                        const PopupMenuDivider(),
                        PopupMenuItem(value: 'remove', child: Text('Remove')),
                      ],
                      icon: const Icon(Icons.more_vert),
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) =>
                              TorrentDetailScreen(torrent: torrent),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
