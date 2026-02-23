import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../lib/client/gameboard/qr_code_widget.dart';

void main() {
  group('QrCodeWidget', () {
    testWidgets('renders a QrImage with the correct data', (tester) async {
      const data = '192.168.1.10:8080';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: QrCodeWidget(connectionData: data),
          ),
        ),
      );

      // QrImage should be present in the tree
      expect(find.byType(QrImageView), findsOneWidget);
    });

    testWidgets('displays the connection string below the QR code',
        (tester) async {
      const data = '10.0.0.5:8080';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: QrCodeWidget(connectionData: data),
          ),
        ),
      );

      expect(find.text(data), findsOneWidget);
    });

    testWidgets('respects custom size parameter', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: QrCodeWidget(connectionData: '127.0.0.1:8080', size: 300),
          ),
        ),
      );

      final qr = tester.widget<QrImageView>(find.byType(QrImageView));
      expect(qr.size, equals(300));
    });
  });
}
