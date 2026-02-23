import 'package:flutter/material.dart';

/// Shows the current server port and the list of connected players.
class ServerStatusWidget extends StatelessWidget {
  final int port;
  final int playerCount;
  final List<String> playerNames;

  const ServerStatusWidget({
    super.key,
    required this.port,
    required this.playerCount,
    required this.playerNames,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.wifi, color: Colors.green),
                const SizedBox(width: 8),
                Text(
                  'Server: port $port',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const Divider(),
            Text(
              'Players connected: $playerCount',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            ...playerNames.map(
              (name) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    const Icon(Icons.person, size: 16),
                    const SizedBox(width: 4),
                    Text(name),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
