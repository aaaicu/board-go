import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

/// A discovered GameBoard server on the local network.
class DiscoveredServer {
  final String host;
  final int port;
  final String? name;

  const DiscoveredServer({required this.host, required this.port, this.name});

  Uri get wsUri => Uri.parse('ws://$host:$port/ws');

  @override
  String toString() => '${name ?? host}:$port';
}

/// Scans the local network for GameBoard servers advertised via mDNS/Bonjour.
///
/// Uses [bonsoir] which delegates to the native Bonjour API on iOS (no raw
/// socket binding to port 5353 → no EADDRINUSE) and Android NSD on Android.
///
/// Returns a list of [DiscoveredServer] entries found within [timeout].
class MdnsDiscovery {
  static const String _serviceType = '_boardgo._tcp';

  static Future<List<DiscoveredServer>> discover({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final results = <DiscoveredServer>[];
    final discovery = BonsoirDiscovery(type: _serviceType);

    // initialize() replaces the old .ready future in bonsoir 6.x
    await discovery.initialize();

    StreamSubscription? subscription;
    subscription = discovery.eventStream?.listen((event) {
      if (event is BonsoirDiscoveryServiceFoundEvent) {
        // Trigger resolution to get the host address
        discovery.serviceResolver.resolveService(event.service);
      } else if (event is BonsoirDiscoveryServiceResolvedEvent) {
        final service = event.service;
        final host = service.host;
        if (host != null && host.isNotEmpty) {
          results.add(DiscoveredServer(
            host: host,
            port: service.port,
            name: service.name,
          ));
        }
      }
    });

    try {
      await discovery.start();
      await Future.delayed(timeout);
    } finally {
      await subscription?.cancel();
      await discovery.stop();
    }

    return results;
  }
}
