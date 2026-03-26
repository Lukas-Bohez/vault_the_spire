import 'dart:io';

import 'package:flutter/material.dart';
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
  late Future<List<TorrentModel>> _futureTorrents;

  @override
  void initState() {
    super.initState();
    _loadTorrents();
  }

  void _loadTorrents() {
    _futureTorrents = TorrentService.instance.allTorrents();
    setState(() {});
  }

  Future<void> _refresh() async {
    _loadTorrents();
    await _futureTorrents;
  }

  Future<void> _toggleTorrent(TorrentModel torrent) async {
    try {
      final status = torrent.status?.toLowerCase() ?? 'paused';
      if (status.contains('download') || status.contains('seed')) {
        TorrentEngineService.instance.stopTorrent(torrent.id);
        await TorrentService.instance.updateTorrentStatus(torrent.id, 'paused');
      } else {
        await TorrentEngineService.instance.startTorrent(torrent.id);
        await TorrentService.instance.updateTorrentStatus(torrent.id, 'downloading');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to toggle torrent: $e')),
      );
    }
    await _refresh();
  }

  Future<void> _deleteTorrent(TorrentModel torrent) async {
    try {
      TorrentEngineService.instance.stopTorrent(torrent.id);
      await TorrentService.instance.removeTorrent(torrent.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Torrent removed.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to delete torrent: $e')),
      );
    }
    await _refresh();
  }

  Future<void> _openTorrentFolder(TorrentModel torrent) async {
    final String pathToOpen;
    if (torrent.filePath != null && torrent.filePath!.isNotEmpty) {
      pathToOpen = torrent.filePath!;
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open folder.')),
      );
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

  String _statusLabel(TorrentModel torrent) {
    final status = torrent.status?.toLowerCase() ?? 'unknown';
    if (status.contains('download')) return 'Downloading';
    if (status.contains('seed')) return 'Seeding';
    if (status.contains('pause')) return 'Paused';
    if (status.contains('complete')) return 'Completed';
    return torrent.status ?? 'Unknown';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Torrents'),
        actions: [
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
          child: FutureBuilder<List<TorrentModel>>(
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
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 100),
                    Center(child: Text('No torrents yet. Drag and drop .torrent files.')),
                  ],
                );
              }

              return ListView.builder(
                itemCount: torrents.length,
                itemBuilder: (context, index) {
                  final torrent = torrents[index];
                  final progress = torrent.progress.clamp(0.0, 1.0);
                  final isActive = (torrent.status ?? '').toLowerCase().contains('download') ||
                      (torrent.status ?? '').toLowerCase().contains('seed');

                  final isComplete = progress >= 1.0 ||
                      (torrent.status ?? '').toLowerCase() == 'complete';

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      title: Text(torrent.name, overflow: TextOverflow.ellipsis),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 6),
                          LinearProgressIndicator(value: progress),
                          const SizedBox(height: 4),
                          Text('${_statusLabel(torrent)} • ${(progress * 100).toStringAsFixed(1)}%'),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isComplete)
                            IconButton(
                              icon: const Icon(Icons.folder_open),
                              tooltip: 'Open folder',
                              onPressed: () => _openTorrentFolder(torrent),
                            )
                          else
                            IconButton(
                              icon: Icon(isActive ? Icons.pause : Icons.play_arrow),
                              tooltip: isActive ? 'Pause' : 'Play',
                              onPressed: () => _toggleTorrent(torrent),
                            ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            tooltip: 'Delete',
                            onPressed: () => _deleteTorrent(torrent),
                          ),
                        ],
                      ),
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
