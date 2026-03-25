import 'package:flutter/material.dart';

class ConnectionStatusTile extends StatelessWidget {
  final int dhtNodes;
  final int peers;
  final double downloadSpeed; // In KB/s
  final String statusMessage;
  final bool hasError;

  const ConnectionStatusTile({
    super.key,
    required this.dhtNodes,
    required this.peers,
    required this.downloadSpeed,
    required this.statusMessage,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      color: hasError ? Colors.red.shade50 : null,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildStat(Icons.lan, 'DHT: $dhtNodes', Colors.blue),
                const SizedBox(width: 16),
                _buildStat(Icons.group, 'Peers: $peers', Colors.green),
                const SizedBox(width: 16),
                _buildStat(Icons.download, '${downloadSpeed.toStringAsFixed(1)} KB/s', Colors.orange),
              ],
            ),
            const Divider(),
            Row(
              children: [
                Icon(
                  hasError ? Icons.error_outline : Icons.info_outline,
                  size: 16,
                  color: hasError ? Colors.red : Colors.grey,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    statusMessage,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: hasError ? Colors.red : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
