import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Displays a QR code encoding [connectionData] (a full `ws://ip:port/ws` URL)
/// and shows [displayText] (typically `"ip:port"`) below for manual entry.
class QrCodeWidget extends StatelessWidget {
  final String connectionData;
  final String? displayText;
  final double size;

  const QrCodeWidget({
    super.key,
    required this.connectionData,
    this.displayText,
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
          displayText ?? connectionData,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}
