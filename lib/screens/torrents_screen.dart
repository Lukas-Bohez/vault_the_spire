import 'dart:io';

import 'package:flutter/material.dart';
import 'package:vault_the_spire/models/torrent.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Torrents'),
        actions: [
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
                  ElevatedButton(
                    onPressed: _refresh,
                    child: const Text('Refresh'),
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
                    trailing: const Icon(Icons.chevron_right),
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
