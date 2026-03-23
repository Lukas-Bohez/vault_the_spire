import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

class TorrentDragDrop extends StatefulWidget {
  final void Function(String path) onTorrentFile;
  final void Function(String path)? onPath;

  const TorrentDragDrop({super.key, required this.onTorrentFile, this.onPath});

  @override
  State<TorrentDragDrop> createState() => _TorrentDragDropState();
}

class _TorrentDragDropState extends State<TorrentDragDrop> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) async {
        setState(() => _dragging = false);
        for (final file in detail.files) {
          if (file.name.endsWith('.torrent')) {
            widget.onTorrentFile(file.path);
          } else {
            widget.onPath?.call(file.path);
          }
        }
      },
      child: Container(
        height: 120,
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _dragging ? Colors.blue.shade100 : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.blue),
        ),
        child: const Center(child: Text('Drag & drop .torrent files here')),
      ),
    );
  }
}
