import 'package:multicast_dns/multicast_dns.dart';

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

/// Scans the local network for GameBoard servers advertised via mDNS.
///
/// Returns a list of [DiscoveredServer] entries found within [timeout].
class MdnsDiscovery {
  static const String _serviceType = '_boardgo._tcp';

  static Future<List<DiscoveredServer>> discover({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final client = MDnsClient();
    final results = <DiscoveredServer>[];

    try {
      await client.start();

      await for (final PtrResourceRecord ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer(_serviceType),
        timeout: timeout,
      )) {
        // For each PTR record, look up the SRV record to get host/port.
        await for (final SrvResourceRecord srv
            in client.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(ptr.domainName),
          timeout: const Duration(seconds: 2),
        )) {
          results.add(
            DiscoveredServer(host: srv.target, port: srv.port, name: ptr.domainName),
          );
          break; // take the first SRV per PTR
        }
      }
    } finally {
      client.stop();
    }

    return results;
  }
}
