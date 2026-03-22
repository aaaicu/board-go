import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../server/mdns_registrar.dart';
import '../../server/server_isolate.dart';
import '../../shared/game_pack/game_pack_interface.dart';
import '../../shared/game_pack/game_state.dart';
import '../../shared/game_pack/player_action.dart';
import '../../shared/game_pack/views/board_view.dart';
import '../../shared/game_session/session_phase.dart';
import '../../shared/messages/board_view_message.dart';
import '../../shared/messages/lobby_state_message.dart';
import '../../shared/messages/ws_message.dart';
import '../shared/app_theme.dart';
import 'game_board_play_screen.dart';
import 'lobby_screen.dart';
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

  StreamSubscription<LobbyStateEvent>? _lobbySub;
  StreamSubscription<BoardViewEvent>? _boardViewSub;
  StreamSubscription<ForceEndVoteStartedEvent>? _voteStartedSub;
  StreamSubscription<ForceEndVoteResultEvent>? _voteResultSub;
  StreamSubscription<GameResetEvent>? _gameResetSub;
  final _mdns = MdnsRegistrar();

  /// True while a force-end vote is in progress.
  bool _voteInProgress = false;

  /// True when the ServerStatusWidget overlay is visible during a game.
  /// In lobby it is always shown; in game it defaults to hidden.
  bool _showServerStatus = false;

  /// Latest lobby state received from the server isolate.
  LobbyStateMessage _lobbyState = const LobbyStateMessage(
    players: [],
    canStart: false,
  );

  /// Latest board view received from the server after game start (Sprint 2).
  BoardView? _boardView;

  /// True once [handle.startGame()] has been called.
  bool _gameStarted = false;

  /// Guards against showing the game-over reset dialog more than once.
  bool _gameOverDialogShown = false;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _startServer();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _lobbySub?.cancel();
    _boardViewSub?.cancel();
    _voteStartedSub?.cancel();
    _voteResultSub?.cancel();
    _gameResetSub?.cancel();
    _handle?.stop();
    _mdns.unregister();
    super.dispose();
  }

  Future<void> _startServer() async {
    try {
      // Start the server and resolve the local IP concurrently — neither
      // depends on the other, so running them in parallel saves time.
      final results = await Future.wait([
        widget.serverStarter(),
        _getLocalIp(),
      ]);
      final handle = results[0] as ServerHandle;
      final (ip, isEmulator) = results[1] as (String?, bool);

      // Advertise via mDNS fire-and-forget — don't block the UI on it.
      unawaited(_mdns.register(port: handle.port));

      // Subscribe to lobby state snapshots from the server isolate.
      final lobbySub = handle.lobbyStateEvents.listen((event) {
        if (!mounted) return;
        setState(() {
          _lobbyState = LobbyStateMessage(
            players: event.players
                .map((p) => LobbyStatePlayerInfo.fromJson(p))
                .toList(),
            canStart: event.canStart,
          );
        });
      });

      // Subscribe to board-view updates from the server isolate (Sprint 2).
      final boardViewSub = handle.boardViewEvents.listen((event) {
        if (!mounted) return;
        final bv = BoardView.fromJson(event.boardView);
        final wasInGame = _gameStarted;
        setState(() {
          _boardView = bv;
          _gameStarted = true;
        });
        // Apply board orientation on first game view.
        if (!wasInGame) {
          _applyOrientation(
              bv.data['_boardOrientation'] as String? ?? 'landscape');
        }
        // Show a reset dialog when the game finishes.
        if (bv.phase == SessionPhase.finished && !_gameOverDialogShown) {
          _gameOverDialogShown = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _showGameOverDialog();
          });
        }
      });

      // Subscribe to force-end vote started events.
      final voteStartedSub = handle.forceEndVoteStartedEvents.listen((event) {
        if (!mounted) return;
        setState(() => _voteInProgress = true);
      });

      // Subscribe to force-end vote result events — resets the button regardless of outcome.
      final voteResultSub = handle.forceEndVoteResultEvents.listen((event) {
        if (!mounted) return;
        setState(() => _voteInProgress = false);
      });

      // Subscribe to game reset events (from votes or manual reset).
      final gameResetSub = handle.gameResetEvents.listen((event) {
        if (!mounted) return;
        _applyOrientation('any'); // Restore free orientation in lobby
        setState(() {
          _gameStarted = false;
          _boardView = null;
          _gameOverDialogShown = false;
          _voteInProgress = false;
          _showServerStatus = false;
        });
        if (event.forcedByVote && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('강제 종료 투표 가결 — 로비로 이동합니다'),
                  backgroundColor: AppTheme.secondaryContainer,
                ),
              );
            }
          });
        }
      });

      if (mounted) {
        setState(() {
          _handle = handle;
          _localIp = ip;
          _isEmulatorIp = isEmulator;
          _lobbySub = lobbySub;
          _boardViewSub = boardViewSub;
          _voteStartedSub = voteStartedSub;
          _voteResultSub = voteResultSub;
          _gameResetSub = gameResetSub;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    }
  }

  /// Applies [SystemChrome.setPreferredOrientations] based on the pack's
  /// orientation string ('landscape', 'portrait', or 'any').
  void _applyOrientation(String orientation) {
    switch (orientation) {
      case 'landscape':
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      case 'portrait':
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      default:
        SystemChrome.setPreferredOrientations([]);
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

  /// Shows a dialog when the game ends, asking whether to return to lobby.
  Future<void> _showGameOverDialog() async {
    final handle = _handle;
    if (handle == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('게임 종료'),
        content: const Text('게임이 끝났습니다.\n게임 준비 단계로 돌아가시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: AppTheme.onSurfaceMuted),
            child: const Text('결과 보기'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.primary),
            child: const Text('게임 준비 단계로'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await handle.resetGame();
      setState(() {
        _gameStarted = false;
        _boardView = null;
        _gameOverDialogShown = false;
        _voteInProgress = false;
      });
    }
  }

  /// Handles back navigation. If players are connected, shows a confirmation
  /// dialog before stopping the server and going back.
  Future<bool> _onWillPop() async {
    if (_lobbyState.players.isEmpty) return true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('게임 종료'),
        content: Text(
          '현재 ${_lobbyState.players.length}명이 접속 중입니다.\n'
          '뒤로 가면 모든 플레이어가 자동으로 메인 화면으로 이동합니다.\n\n'
          '계속하시겠습니까?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: AppTheme.onSurfaceMuted),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.error),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  /// Initiates the force-end vote flow: first shows a confirmation dialog on
  /// the GameBoard, then sends the command to the server if confirmed.
  Future<void> _onForceEndVote() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('게임 강제종료'),
        content: const Text(
          '게임을 강제 종료하겠습니까?\n'
          '모든 플레이어에게 투표가 전송됩니다.\n'
          '과반수가 동의하면 로비로 돌아갑니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            style: TextButton.styleFrom(foregroundColor: AppTheme.onSurfaceMuted),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: AppTheme.error,
              backgroundColor: AppTheme.errorContainer,
            ),
            child: const Text('투표 시작'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _handle?.startForceEndVote();
    }
  }

  @override
  Widget build(BuildContext context) {
    final inGame = _gameStarted && _boardView != null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        final canLeave = await _onWillPop();
        if (canLeave && mounted) {
          await _handle?.stop();
          navigator.pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        // Hide the AppBar during gameplay — controls are embedded in the
        // board widget's phase header to avoid wasting a full line.
        appBar: inGame
            ? null
            : AppBar(
                backgroundColor: AppTheme.background,
                title: Image.asset('assets/images/logo.png', height: 36),
              ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Text('Server error: $_error',
            style: const TextStyle(color: AppTheme.error)),
      );
    }

    final handle = _handle;
    if (handle == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final displayIp = _localIp ?? 'localhost';
    final connectionData = '$displayIp:${handle.port}';
    final qrData = 'ws://$displayIp:${handle.port}/ws';

    return Column(
      children: [
        if (_isEmulatorIp)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_outlined,
                    color: AppTheme.secondary, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '에뮬레이터 전용 IP입니다. 외부 기기에서 접속할 수 없어요.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Server status: always visible in lobby; toggled via AppBar button in game.
        if (!_gameStarted)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ServerStatusWidget(
              port: handle.port,
              playerCount: _lobbyState.players.length,
              playerNames: _lobbyState.players.map((p) => p.nickname).toList(),
            ),
          ),
        // In-game: show the board view.
        if (_gameStarted && _boardView != null)
          Expanded(
            child: GameBoardPlayScreen(
              boardView: _boardView!,
              playerNames: {
                for (final p in _lobbyState.players) p.playerId: p.nickname
              },
              voteInProgress: _voteInProgress,
              showServerStatus: _showServerStatus,
              onToggleServerStatus: () =>
                  setState(() => _showServerStatus = !_showServerStatus),
              onForceEndVote: _onForceEndVote,
              serverStatusWidget: _showServerStatus
                  ? ServerStatusWidget(
                      port: handle.port,
                      playerCount: _lobbyState.players.length,
                      playerNames:
                          _lobbyState.players.map((p) => p.nickname).toList(),
                    )
                  : null,
            ),
          )
        // Lobby: show the lobby screen.
        else
          Expanded(
            child: LobbyScreen(
              lobbyState: _lobbyState,
              serverAddress: connectionData,
              qrData: qrData,
              onStartGame: _lobbyState.canStart
                  ? (String packId) async {
                      await handle.startGame(packId: packId);
                    }
                  : null,
            ),
          ),
      ],
    );
  }
}
