import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:vault_the_spire/models/torrent.dart';
import 'package:vault_the_spire/platform/desktop_window.dart';
import 'package:vault_the_spire/platform/drag_drop.dart';
import 'package:vault_the_spire/screens/torrent_detail_screen.dart';
import 'package:vault_the_spire/services/torrent_engine_service.dart';
import 'package:vault_the_spire/services/torrent_service.dart';

class TorrentsScreen extends StatefulWidget {
  const TorrentsScreen({super.key});

  @override
  State<TorrentsScreen> createState() => _TorrentsScreenState();
}

enum TorrentSortOption { progress, size, downloaded, uploaded, name }

class _TorrentsScreenState extends State<TorrentsScreen> {
  late Future<List<TorrentModel>> _futureTorrents;
  String _statusFilter = 'All';
  TorrentSortOption _sortOption = TorrentSortOption.progress;
  String _searchQuery = '';
  final _magnetController = TextEditingController();
  final Map<String, TorrentEngineStatus> _engineStatuses = {};
  StreamSubscription<TorrentEngineStatus>? _engineSubscription;

  final List<String> _statusCategories = const [
    'All',
    'Downloading',
    'Paused',
    'Seeding',
    'Completed',
    'Error',
  ];

  @override
  void initState() {
    super.initState();
    _futureTorrents = TorrentService.instance.allTorrents();
    _engineSubscription = TorrentEngineService.instance.statusStream.listen((
      status,
    ) {
      if (!mounted) return;
      setState(() {
        _engineStatuses[status.torrentId] = status;
      });
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _futureTorrents = TorrentService.instance.allTorrents();
    });
  }

  Future<void> _startAll() async {
    final torrents = await TorrentService.instance.allTorrents();
    for (final torrent in torrents) {
      if (torrent.status != 'completed') {
        await TorrentEngineService.instance.startTorrent(torrent.id);
      }
    }
    await _refresh();
  }

  Future<void> _pauseAll() async {
    final torrents = await TorrentService.instance.allTorrents();
    for (final torrent in torrents) {
      if (torrent.status == 'downloading') {
        TorrentEngineService.instance.stopTorrent(torrent.id);
      }
    }
    await _refresh();
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

  Future<void> _showCreateTorrentSourceDialog() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Create torrent from'),
          content: const Text('Choose a file or directory to create torrent.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('file'),
              child: const Text('File'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop('directory'),
              child: const Text('Folder'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
    if (choice == 'file') {
      await _pickFileAndCreateTorrent();
    } else if (choice == 'directory') {
      await _pickDirectoryAndCreateTorrent();
    }
  }

  Future<void> _pickFileAndCreateTorrent() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

    try {
      await TorrentService.instance.addTorrentFromPath(path);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Torrent created from file and added.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to create torrent: $e')));
    }
  }

  Future<void> _pickDirectoryAndCreateTorrent() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null || path.isEmpty) return;

    try {
      await TorrentService.instance.addTorrentFromPath(path);
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Torrent created from folder and added.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to create torrent: $e')));
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

  Future<void> _addMagnetLinkFromInput() async {
    final link = _magnetController.text.trim();
    if (link.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a magnet link')),
      );
      return;
    }

    try {
      await TorrentService.instance.addTorrentFromMagnetLink(link);
      _magnetController.clear();
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
  void dispose() {
    _magnetController.dispose();
    _engineSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Torrents'),
        actions: [
          IconButton(
            icon: const Icon(Icons.play_arrow),
            tooltip: 'Start all',
            onPressed: _startAll,
          ),
          IconButton(
            icon: const Icon(Icons.pause),
            tooltip: 'Pause all',
            onPressed: _pauseAll,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create torrent from file/folder',
            onPressed: _showCreateTorrentSourceDialog,
          ),
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Text('Category: '),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: _statusFilter,
                  items: _statusCategories
                      .map(
                        (status) => DropdownMenuItem(
                          value: status,
                          child: Text(status),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _statusFilter = value;
                      });
                    }
                  },
                ),
                const SizedBox(width: 16),
                const Text('Sort:'),
                const SizedBox(width: 8),
                DropdownButton<TorrentSortOption>(
                  value: _sortOption,
                  items: TorrentSortOption.values
                      .map(
                        (option) => DropdownMenuItem(
                          value: option,
                          child: Text(option.toString().split('.').last),
                        ),
                      )
                      .toList(),
                  onChanged: (option) {
                    if (option != null) {
                      setState(() {
                        _sortOption = option;
                      });
                    }
                  },
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh',
                  onPressed: _refresh,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Search torrents',
                hintText: 'Type name or part of name',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.trim();
                });
              },
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _magnetController,
                    decoration: const InputDecoration(
                      labelText: 'Paste magnet link',
                      hintText: 'magnet:?xt=urn:btih:...',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.url,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.add_link),
                  label: const Text('Add'),
                  onPressed: _addMagnetLinkFromInput,
                ),
              ],
            ),
          ),
          Expanded(
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
                final byStatus = _statusFilter == 'All'
                    ? torrents
                    : torrents.where((t) {
                        final status = (t.status ?? '').toLowerCase();
                        switch (_statusFilter) {
                          case 'Downloading':
                            return status.contains('download');
                          case 'Paused':
                            return status.contains('pause');
                          case 'Seeding':
                            return status.contains('seed');
                          case 'Completed':
                            return status.contains('complete');
                          case 'Error':
                            return status.contains('error');
                          default:
                            return true;
                        }
                      }).toList();

                final filteredTorrents = _searchQuery.isEmpty
                    ? byStatus
                    : byStatus
                          .where(
                            (t) => t.name.toLowerCase().contains(
                              _searchQuery.toLowerCase(),
                            ),
                          )
                          .toList();

                filteredTorrents.sort((a, b) {
                  switch (_sortOption) {
                    case TorrentSortOption.progress:
                      return b.progress.compareTo(a.progress);
                    case TorrentSortOption.size:
                      return (b.totalSize ?? 0).compareTo(a.totalSize ?? 0);
                    case TorrentSortOption.downloaded:
                      return b.bytesDown.compareTo(a.bytesDown);
                    case TorrentSortOption.uploaded:
                      return b.bytesUp.compareTo(a.bytesUp);
                    case TorrentSortOption.name:
                      return a.name.toLowerCase().compareTo(
                        b.name.toLowerCase(),
                      );
                  }
                });

                if (filteredTorrents.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TorrentDragDrop(
                          onTorrentFile: (path) {
                            _importTorrent(path);
                          },
                          onPath: (path) async {
                            final messenger = ScaffoldMessenger.of(context);
                            try {
                              await TorrentService.instance.addTorrentFromPath(
                                path,
                              );
                              await _refresh();
                              if (!mounted) return;
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Path added as torrent container.',
                                  ),
                                ),
                              );
                            } catch (e) {
                              if (!mounted) return;
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Failed to create torrent from path: $e',
                                  ),
                                ),
                              );
                            }
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
                    itemCount: filteredTorrents.length,
                    itemBuilder: (context, index) {
                      final torrent = filteredTorrents[index];
                      final progress = torrent.progress;
                      return Card(
                        child: ListTile(
                          title: Text(torrent.name),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Status: ${torrent.status ?? 'unknown'} • ${(progress * 100).toStringAsFixed(1)}%',
                              ),
                              if (_engineStatuses.containsKey(torrent.id))
                                Builder(
                                  builder: (context) {
                                    final status = _engineStatuses[torrent.id]!;
                                    final speedDown = status.downloadSpeed;
                                    final speedUp = status.uploadSpeed;
                                    final eta =
                                        torrent.totalSize != null &&
                                            torrent.totalSize! > 0
                                        ? Duration(
                                            seconds:
                                                ((torrent.totalSize! *
                                                            (1 -
                                                                torrent
                                                                    .progress)) /
                                                        (speedDown > 0
                                                            ? speedDown
                                                            : 1))
                                                    .ceil(),
                                          )
                                        : null;
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Seeders: ${torrent.seeders}, Leechers: ${torrent.leechers}, Connected peers: ${status.peers}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        Text(
                                          'DL: ${speedDown.toStringAsFixed(1)} B/s • UL: ${speedUp.toStringAsFixed(1)} B/s • peers: ${status.peers}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        if (eta != null)
                                          Text(
                                            'ETA: ${eta.inMinutes}m ${eta.inSeconds % 60}s',
                                            style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        Text(
                                          'Downloaded: ${status.downloaded} B / ${status.uploaded} B',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              if (torrent.maxSeedRatio != null)
                                Text(
                                  'Seed ratio limit: ${torrent.maxSeedRatio!.toStringAsFixed(2)}${torrent.deleteAfterRatioReached ? ' (delete after reached)' : ''}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                ),
                            ],
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) async {
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                if (value == 'pause') {
                                  await TorrentService.instance
                                      .updateTorrentStatus(
                                        torrent.id,
                                        'paused',
                                      );
                                } else if (value == 'resume') {
                                  await TorrentService.instance
                                      .updateTorrentStatus(
                                        torrent.id,
                                        'downloading',
                                      );
                                } else if (value == 'set_ratio') {
                                  final ratioController = TextEditingController(
                                    text:
                                        torrent.maxSeedRatio?.toStringAsFixed(
                                          2,
                                        ) ??
                                        '2.00',
                                  );
                                  final submit = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Set seed ratio limit'),
                                      content: TextField(
                                        controller: ratioController,
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        decoration: const InputDecoration(
                                          labelText: 'Seed ratio',
                                          hintText: '2.0',
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(false),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(true),
                                          child: const Text('Set'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (submit == true) {
                                    final parsed = double.tryParse(
                                      ratioController.text,
                                    );
                                    if (parsed != null && parsed > 0) {
                                      await TorrentService.instance
                                          .setSeedRatioLimit(
                                            torrent.id,
                                            parsed,
                                          );
                                      await _refresh();
                                    }
                                  }
                                } else if (value == 'start') {
                                  await TorrentEngineService.instance
                                      .startTorrent(torrent.id);
                                  await _refresh();
                                } else if (value == 'stop') {
                                  TorrentEngineService.instance.stopTorrent(
                                    torrent.id,
                                  );
                                  await TorrentService.instance
                                      .updateTorrentStatus(
                                        torrent.id,
                                        'paused',
                                      );
                                  await _refresh();
                                } else if (value == 'toggle_delete') {
                                  await TorrentService.instance
                                      .setDeleteAfterRatioReached(
                                        torrent.id,
                                        !torrent.deleteAfterRatioReached,
                                      );
                                  await _refresh();
                                } else if (value == 'remove') {
                                  TorrentEngineService.instance.stopTorrent(
                                    torrent.id,
                                  );
                                  await TorrentService.instance.removeTorrent(
                                    torrent.id,
                                  );
                                  await _refresh();
                                } else if (value == 'copy_magnet') {
                                  if (torrent.magnetLink != null &&
                                      torrent.magnetLink!.isNotEmpty) {
                                    await Clipboard.setData(
                                      ClipboardData(text: torrent.magnetLink!),
                                    );
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Magnet link copied to clipboard',
                                        ),
                                      ),
                                    );
                                  } else {
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'No magnet link available',
                                        ),
                                      ),
                                    );
                                  }
                                } else if (value == 'copy_id') {
                                  await Clipboard.setData(
                                    ClipboardData(text: torrent.id),
                                  );
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Torrent ID copied to clipboard',
                                      ),
                                    ),
                                  );
                                } else if (value == 'open') {
                                  final path = torrent.filePath;
                                  if (path != null &&
                                      path.isNotEmpty &&
                                      File(path).existsSync()) {
                                    await Process.start(
                                      Platform.isWindows
                                          ? 'explorer'
                                          : (Platform.isMacOS
                                                ? 'open'
                                                : 'xdg-open'),
                                      [
                                        Platform.isWindows
                                            ? p.dirname(path)
                                            : path,
                                      ],
                                    );
                                  } else {
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'File path not available.',
                                        ),
                                      ),
                                    );
                                  }
                                }
                                await _refresh();
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('Action executed: $value'),
                                  ),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                messenger.showSnackBar(
                                  SnackBar(
                                    content: Text('Failed action $value: $e'),
                                  ),
                                );
                              }
                            },
                            itemBuilder: (_) => [
                              PopupMenuItem(
                                value: 'start',
                                child: Text('Start download'),
                              ),
                              PopupMenuItem(
                                value: 'stop',
                                child: Text('Stop download'),
                              ),
                              PopupMenuItem(
                                value: 'pause',
                                child: Text('Pause'),
                              ),
                              PopupMenuItem(
                                value: 'resume',
                                child: Text('Resume'),
                              ),
                              PopupMenuItem(
                                value: 'set_ratio',
                                child: Text('Set seed ratio limit'),
                              ),
                              PopupMenuItem(
                                value: 'toggle_delete',
                                child: Text(
                                  torrent.deleteAfterRatioReached
                                      ? 'Disable delete after ratio'
                                      : 'Enable delete after ratio',
                                ),
                              ),
                              PopupMenuItem(
                                value: 'copy_magnet',
                                child: Text('Copy magnet link'),
                              ),
                              PopupMenuItem(
                                value: 'copy_id',
                                child: Text('Copy torrent ID'),
                              ),
                              PopupMenuItem(
                                value: 'open',
                                child: Text('Open folder'),
                              ),
                              const PopupMenuDivider(),
                              PopupMenuItem(
                                value: 'remove',
                                child: Text('Remove'),
                              ),
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
          ),
        ],
      ),
    );
  }
}
