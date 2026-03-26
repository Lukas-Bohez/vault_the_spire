import 'package:flutter/material.dart';
import 'package:vault_the_spire/services/torrent_engine_service.dart';

class NetworkHealthIndicator extends StatelessWidget {
  const NetworkHealthIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: TorrentEngineService.instance.statusStream
          .map((event) => event.dhtNodes)
          .distinct(),
      builder: (context, snapshot) {
        final dhtNodes = snapshot.data ??
            TorrentEngineService.instance.currentDhtNodeCount;
        final status = dhtNodes == 0
            ? 'Offline'
            : dhtNodes < 5
                ? 'Restricted'
                : 'Healthy';
        final color = dhtNodes == 0
            ? Colors.red
            : dhtNodes < 5
                ? Colors.amber
                : Colors.green;

        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white70, width: 0.8),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'DHT: $status ($dhtNodes)',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.white70,
                    ),
              ),
            ],
          ),
        );
      },
    );
  }
}
