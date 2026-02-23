import 'package:flutter/material.dart';

import '../shared/mdns_discovery.dart';
import 'qr_scan_screen.dart';

/// Lets the player find the GameBoard server via mDNS scan, QR code,
/// or manual IP:port entry.
class DiscoveryScreen extends StatefulWidget {
  /// Called when the user selects a server (manual URL, mDNS, or QR scan).
  final void Function(String wsUrl)? onServerSelected;

  /// Exposed for testing — fires when the "Search" button is tapped before
  /// the actual mDNS scan starts.
  final VoidCallback? onSearch;

  const DiscoveryScreen({super.key, this.onServerSelected, this.onSearch});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  List<DiscoveredServer> _discovered = [];
  bool _scanning = false;
  String? _error;

  final _ipController = TextEditingController(text: '192.168.0.');
  final _portController = TextEditingController(text: '8080');

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    widget.onSearch?.call();
    setState(() {
      _scanning = true;
      _error = null;
      _discovered = [];
    });

    try {
      final results = await MdnsDiscovery.discover(
        timeout: const Duration(seconds: 5),
      );
      setState(() {
        _discovered = results;
        _scanning = false;
        if (results.isEmpty) {
          _error = '주변 서버를 찾지 못했어요. IP를 직접 입력해보세요.';
        }
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _scanning = false;
      });
    }
  }

  void _connectManual() {
    final ip = _ipController.text.trim();
    final port = _portController.text.trim();
    if (ip.isEmpty || port.isEmpty) return;
    final url = 'ws://$ip:$port/ws';
    widget.onServerSelected?.call(url);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 직접 입력 ──────────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'IP 직접 입력',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '게임 보드 화면에 표시된 IP와 포트를 입력하세요',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _ipController,
                          decoration: const InputDecoration(
                            labelText: 'IP',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.url,
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text(':', style: TextStyle(fontSize: 20)),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _portController,
                          decoration: const InputDecoration(
                            labelText: 'Port',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.login),
                    label: const Text('접속'),
                    onPressed: _connectManual,
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('또는', style: TextStyle(color: Colors.grey)),
              ),
              Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 16),

          // ── QR 스캔 ────────────────────────────────────
          ElevatedButton.icon(
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Scan QR Code'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => QrScanScreen(
                    onScanned: (url) {
                      Navigator.pop(context);
                      widget.onServerSelected?.call(url);
                    },
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),

          // ── mDNS 자동 탐색 ─────────────────────────────
          ElevatedButton.icon(
            icon: _scanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_find),
            label: const Text('Search for Servers'),
            onPressed: _scanning ? null : _scan,
          ),

          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.orange)),
          ],

          if (_discovered.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Found servers:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            ..._discovered.map(
              (server) => ListTile(
                leading: const Icon(Icons.tablet),
                title: Text(server.toString()),
                onTap: () =>
                    widget.onServerSelected?.call(server.wsUri.toString()),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
