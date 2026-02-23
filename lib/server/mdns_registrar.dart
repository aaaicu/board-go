import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

/// Registers the GameBoard WebSocket server via mDNS/zeroconf so that GameNode
/// apps can discover it automatically on the same Wi-Fi network.
///
/// The service is advertised under the `_boardgo._tcp` service type.
class MdnsRegistrar {
  static const String _serviceType = '_boardgo._tcp';
  static const String _serviceName = 'board-go';

  MDnsClient? _client;
  bool _registered = false;

  bool get isRegistered => _registered;

  /// Starts advertising the service on [port].
  ///
  /// [instanceName] can be customised to distinguish multiple boards on the
  /// same network (e.g. using the device name).
  Future<void> register({
    int port = 8080,
    String instanceName = _serviceName,
  }) async {
    _client = MDnsClient();
    await _client!.start();

    // multicast_dns does not expose a high-level "register" API on all
    // platforms — full SRV/TXT registration requires platform-specific code
    // (Bonjour on iOS/macOS, NSD on Android).  The shelf server will be
    // discoverable once we integrate native mDNS registration.
    //
    // For now we mark registration as "started" so the rest of the app can
    // proceed; Phase 5 will add the native bridge.
    _registered = true;
  }

  /// Stops advertising and releases resources.
  Future<void> unregister() async {
    _client?.stop();
    _client = null;
    _registered = false;
  }

  /// Returns the primary non-loopback IPv4 address of this device, or `null`
  /// if none is found.  Useful for building the QR code payload.
  static Future<String?> localIpAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    return interfaces
        .expand((i) => i.addresses)
        .where((a) => !a.isLoopback)
        .map((a) => a.address)
        .firstOrNull;
  }
}
