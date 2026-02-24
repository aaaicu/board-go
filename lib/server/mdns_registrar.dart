import 'dart:io';

import 'package:bonsoir/bonsoir.dart';

/// Registers the GameBoard WebSocket server via mDNS/Bonjour so that GameNode
/// apps can discover it automatically on the same Wi-Fi network.
///
/// Uses [bonsoir] which delegates to native Bonjour on iOS/macOS and Android
/// NSD on Android — no raw socket binding required, so no EADDRINUSE.
///
/// The service is advertised under the `_boardgo._tcp` service type.
class MdnsRegistrar {
  static const String _serviceType = '_boardgo._tcp';
  static const String _serviceName = 'Board Go';

  BonsoirBroadcast? _broadcast;
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
    final service = BonsoirService(
      name: instanceName,
      type: _serviceType,
      port: port,
    );

    _broadcast = BonsoirBroadcast(service: service);
    // initialize() must be awaited before start() in bonsoir 6.x
    await _broadcast!.initialize();
    await _broadcast!.start();
    _registered = true;
  }

  /// Stops advertising and releases resources.
  Future<void> unregister() async {
    await _broadcast?.stop();
    _broadcast = null;
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
