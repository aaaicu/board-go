import 'package:flutter/material.dart';

import '../shared/app_theme.dart';
import '../shared/mdns_discovery.dart';
import '../shared/widgets/board_card.dart';
import '../shared/widgets/primary_button.dart';
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
    // Strip brackets that may appear when pasting IPv6-style notation like [192.168.0.1]
    final ip = _ipController.text.trim().replaceAll('[', '').replaceAll(']', '');
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
          BoardCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'IP 직접 입력',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '게임 보드 화면에 표시된 IP와 포트를 입력하세요',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.onSurfaceMuted,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _ipController,
                        decoration: const InputDecoration(
                          labelText: 'IP 주소',
                        ),
                        keyboardType: TextInputType.url,
                        style: const TextStyle(
                          color: AppTheme.onSurface,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: SizedBox(
                        height: 52,
                        child: Center(
                          child: Text(
                            ':',
                            style: TextStyle(
                              fontSize: 20,
                              color: AppTheme.onSurfaceMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextField(
                        controller: _portController,
                        decoration: const InputDecoration(
                          labelText: '포트',
                        ),
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          color: AppTheme.onSurface,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                PrimaryButton(
                  label: '접속',
                  icon: Icons.login_rounded,
                  onPressed: _connectManual,
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Divider — spacing-based, no solid line per design rules
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 1,
                  color: AppTheme.outlineVariant.withValues(alpha: 0.2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '또는',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.onSurfaceMuted,
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  height: 1,
                  color: AppTheme.outlineVariant.withValues(alpha: 0.2),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // ── QR 스캔 ────────────────────────────────────
          _SecondaryButton(
            icon: Icons.qr_code_scanner_rounded,
            label: 'QR 코드 스캔',
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
          _SecondaryButton(
            icon: Icons.wifi_find_rounded,
            label: _scanning ? '탐색 중...' : '주변 서버 자동 탐색',
            isLoading: _scanning,
            onPressed: _scanning ? null : _scan,
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.secondaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _error!,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.onSecondaryContainer,
                ),
              ),
            ),
          ],

          if (_discovered.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text(
              '발견된 서버',
              style: TextStyle(
                fontFamily: 'Manrope',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            ..._discovered.map(
              (server) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: BoardCard(
                  onTap: () =>
                      widget.onServerSelected?.call(server.wsUri.toString()),
                  backgroundColor: AppTheme.surfaceContainerLow,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  borderRadius: 16,
                  child: Row(
                    children: [
                      const Icon(
                        Icons.tablet_mac_outlined,
                        color: AppTheme.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          server.toString(),
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.onSurface,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: AppTheme.onSurfaceMuted,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Secondary-style button: surfaceContainerHighest bg + primary text.
class _SecondaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool isLoading;

  const _SecondaryButton({
    required this.label,
    required this.icon,
    this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null && !isLoading;
    return SizedBox(
      height: 56,
      child: Material(
        color: AppTheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(9999),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(9999),
          splashColor: AppTheme.primary.withValues(alpha: 0.08),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.primary,
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        icon,
                        size: 20,
                        color: disabled
                            ? AppTheme.onSurfaceMuted
                            : AppTheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        label,
                        style: TextStyle(
                          fontFamily: 'Manrope',
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: disabled
                              ? AppTheme.onSurfaceMuted
                              : AppTheme.primary,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
