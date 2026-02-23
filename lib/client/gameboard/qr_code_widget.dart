import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Displays a QR code encoding [connectionData] (typically `"ip:port"`) and
/// shows the raw string below for manual entry.
class QrCodeWidget extends StatelessWidget {
  final String connectionData;
  final double size;

  const QrCodeWidget({
    super.key,
    required this.connectionData,
    this.size = 250,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        QrImageView(
          data: connectionData,
          size: size,
          backgroundColor: Colors.white,
        ),
        const SizedBox(height: 8),
        Text(
          connectionData,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}
