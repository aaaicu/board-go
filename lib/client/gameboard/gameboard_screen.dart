import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../server/mdns_registrar.dart';
import '../../server/server_isolate.dart';
import '../../shared/game_pack/game_state.dart';
import '../../shared/game_pack/game_pack_interface.dart';
import '../../shared/game_pack/player_action.dart';
import 'qr_code_widget.dart';
import 'server_status_widget.dart';

/// Placeholder game pack used until a real pack is selected.
class _NoOpGamePack implements GamePackInterface {
  @override
  Future<void> initialize(GameState initialState) async {}

  @override
  bool validateAction(PlayerAction action, GameState currentState) => true;

  @override
  GameState processAction(PlayerAction action, GameState currentState) =>
      currentState;

  @override
  Future<void> dispose() async {}
}

/// Signature for the function that starts the server and returns a handle.
///
/// Exposing this as a parameter lets widget tests inject a lightweight fake
/// instead of spinning up a real Isolate + network socket.
typedef ServerStarter = Future<ServerHandle> Function();

Future<ServerHandle> _defaultServerStarter() => ServerIsolate.start(
      packFactory: _NoOpGamePack.new,
      initialState: GameState(
        gameId: 'game-${DateTime.now().millisecondsSinceEpoch}',
        turn: 0,
        activePlayerId: '',
        data: {},
      ),
      port: 8080,
    );

/// IP override injected via `--dart-define=HOST_IP=192.168.x.x` at build time.
/// Useful when running the server inside an Android emulator whose virtual
/// network IP is unreachable from external devices.
const _kHostIpOverride = String.fromEnvironment('HOST_IP', defaultValue: '');

/// The main iPad screen.  Starts the embedded WebSocket server in an Isolate
/// and displays connection info (status widget + QR code) once ready.
class GameboardScreen extends StatefulWidget {
  /// Override in tests to avoid spawning a real server.
  final ServerStarter serverStarter;

  const GameboardScreen({
    super.key,
    ServerStarter? serverStarter,
  }) : serverStarter = serverStarter ?? _defaultServerStarter;

  @override
  State<GameboardScreen> createState() => _GameboardScreenState();
}

class _GameboardScreenState extends State<GameboardScreen> {
  ServerHandle? _handle;
  String? _localIp;
  bool _isEmulatorIp = false;
  String? _error;

  final List<String> _playerNames = [];
  StreamSubscription<PlayerEvent>? _eventSub;
  final _mdns = MdnsRegistrar();

  @override
  void initState() {
    super.initState();
    _startServer();
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    _handle?.stop();
    _mdns.unregister();
    super.dispose();
  }

  Future<void> _startServer() async {
    try {
      final handle = await widget.serverStarter();

      final (ip, isEmulator) = await _getLocalIp();

      // Advertise the server via mDNS/Bonjour so GameNode can auto-discover.
      await _mdns.register(port: handle.port);

      // Subscribe to player join/leave events from the server isolate.
      final sub = handle.playerEvents.listen((event) {
        if (!mounted) return;
        setState(() {
          if (event.joined) {
            if (!_playerNames.contains(event.displayName)) {
              _playerNames.add(event.displayName);
            }
          } else {
            _playerNames.remove(event.displayName);
          }
        });
      });

      if (mounted) {
        setState(() {
          _handle = handle;
          _localIp = ip;
          _isEmulatorIp = isEmulator;
          _eventSub = sub;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    }
  }

  /// Returns (bestIp, isEmulatorOnly).
  ///
  /// Priority:
  ///   1. `--dart-define=HOST_IP=...` override (emulator + port-forward setup)
  ///   2. Real LAN addresses (192.168.x.x / 172.16-31.x.x)
  ///   3. Other non-loopback addresses (excludes 10.0.2.x emulator range)
  ///   4. Fallback: emulator IP with warning
  Future<(String?, bool)> _getLocalIp() async {
    // Highest priority: explicit override from --dart-define=HOST_IP=...
    if (_kHostIpOverride.isNotEmpty) return (_kHostIpOverride, false);

    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    final all = interfaces
        .expand((i) => i.addresses)
        .where((a) => !a.isLoopback)
        .map((a) => a.address)
        .toList();

    // Prefer real LAN addresses (192.168.x.x or 172.16-31.x.x).
    final lan = all.where(_isLanAddress).toList();
    if (lan.isNotEmpty) return (lan.first, false);

    // Exclude Android emulator virtual IPs (10.0.2.x).
    final nonEmulator = all.where((ip) => !ip.startsWith('10.0.2.')).toList();
    if (nonEmulator.isNotEmpty) return (nonEmulator.first, false);

    // Only emulator IPs available — external connections won't work.
    return (all.firstOrNull, all.isNotEmpty);
  }

  bool _isLanAddress(String ip) {
    if (ip.startsWith('192.168.')) return true;
    // 172.16.0.0 – 172.31.255.255
    final parts = ip.split('.');
    if (parts.length == 4 && parts[0] == '172') {
      final second = int.tryParse(parts[1]) ?? 0;
      if (second >= 16 && second <= 31) return true;
    }
    return false;
  }

  /// Handles back navigation. If players are connected, shows a confirmation
  /// dialog before stopping the server and going back.
  Future<bool> _onWillPop() async {
    if (_playerNames.isEmpty) return true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('게임 종료'),
        content: Text(
          '현재 ${_playerNames.length}명이 접속 중입니다.\n'
          '뒤로 가면 모든 플레이어가 자동으로 메인 화면으로 이동합니다.\n\n'
          '계속하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('나가기', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final canLeave = await _onWillPop();
        if (canLeave && context.mounted) {
          await _handle?.stop();
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('board-go')),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Text('Server error: $_error',
            style: const TextStyle(color: Colors.red)),
      );
    }

    final handle = _handle;
    if (handle == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final displayIp = _localIp ?? 'localhost';
    final connectionData = '$displayIp:${handle.port}';
    final qrData = 'ws://$displayIp:${handle.port}/ws';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          if (_isEmulatorIp)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.orange),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '에뮬레이터 전용 IP입니다.\n외부 기기에서 접속할 수 없어요. 실제 기기를 사용해주세요.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ServerStatusWidget(
            port: handle.port,
            playerCount: _playerNames.length,
            playerNames: _playerNames,
          ),
          const SizedBox(height: 24),
          Text(
            'Scan to join',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          QrCodeWidget(connectionData: qrData, displayText: connectionData),
        ],
      ),
    );
  }
}
