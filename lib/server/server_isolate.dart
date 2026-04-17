import 'dart:async';
import 'dart:isolate';

import '../shared/game_pack/game_pack_interface.dart';
import '../shared/game_pack/game_pack_rules.dart';
import '../shared/game_pack/game_state.dart';
import 'game_server.dart';

// ---------------------------------------------------------------------------
// Player event — sent from the server isolate to the UI isolate
// ---------------------------------------------------------------------------

/// A player join or leave event forwarded from the server Isolate to the UI.
class PlayerEvent {
  final bool joined;
  final String playerId;
  final String displayName;

  /// When [joined] is false, indicates whether this is a temporary network
  /// disconnect (true) or a deliberate LEAVE (false).
  ///
  /// The GameBoard UI should preserve the player's entry in its player map for
  /// temporary disconnects and remove it only on a deliberate leave.
  final bool isTemporaryDisconnect;

  const PlayerEvent({
    required this.joined,
    required this.playerId,
    required this.displayName,
    this.isTemporaryDisconnect = false,
  });
}

/// A lobby-state snapshot forwarded from the server Isolate to the UI.
///
/// Sent whenever the lobby state changes (player joins, leaves, or toggles
/// ready). The UI can use this to update the [LobbyScreen] without parsing
/// raw WebSocket JSON.
class LobbyStateEvent {
  /// Serialised [LobbyStatePlayerInfo] entries.
  final List<Map<String, dynamic>> players;
  final bool canStart;

  const LobbyStateEvent({
    required this.players,
    required this.canStart,
  });
}

/// A board-view snapshot forwarded from the server Isolate to the UI isolate
/// after every game action.
///
/// The UI uses this to update the [GameBoardPlayScreen] without subscribing
/// to the WebSocket itself.
class BoardViewEvent {
  /// The serialised [BoardView] JSON map.
  final Map<String, dynamic> boardView;

  const BoardViewEvent({required this.boardView});
}

/// Sent from the server Isolate to the UI isolate when a force-end vote starts.
class ForceEndVoteStartedEvent {
  final int playerCount;
  const ForceEndVoteStartedEvent({required this.playerCount});
}

/// Sent from the server Isolate to the UI isolate when a force-end vote resolves.
class ForceEndVoteResultEvent {
  final bool agreed;
  final int agreeCount;
  final int totalCount;
  const ForceEndVoteResultEvent({
    required this.agreed,
    required this.agreeCount,
    required this.totalCount,
  });
}

/// Sent from the server Isolate to the UI isolate when the game is reset,
/// either by a force-end vote passing or by the host manually resetting.
class GameResetEvent {
  final bool forcedByVote;
  const GameResetEvent({this.forcedByVote = false});
}

// ---------------------------------------------------------------------------
// Command / response types
// ---------------------------------------------------------------------------

sealed class _ServerCommand {}

class _StartServerCommand extends _ServerCommand {
  final String host;
  final int port;
  final GameState initialState;
  final SendPort replyPort;
  final String? webAssetRoot;

  _StartServerCommand({
    required this.host,
    required this.port,
    required this.initialState,
    required this.replyPort,
    this.webAssetRoot,
  });
}

class _StopServerCommand extends _ServerCommand {
  final SendPort replyPort;
  _StopServerCommand({required this.replyPort});
}

/// Signals the server isolate to start the game (transition from lobby).
class _StartGameCommand extends _ServerCommand {
  final SendPort replyPort;

  /// The pack ID to use for the game session.
  final String packId;

  _StartGameCommand({required this.replyPort, required this.packId});
}

/// Signals the server isolate to reset the game back to the lobby phase.
class _ResetGameCommand extends _ServerCommand {
  final SendPort replyPort;
  _ResetGameCommand({required this.replyPort});
}

/// Signals the server isolate to initiate a force-end vote among all connected players.
class _ForceEndVoteCommand extends _ServerCommand {
  final SendPort replyPort;
  _ForceEndVoteCommand({required this.replyPort});
}

class _ServerStarted {
  final int port;
  _ServerStarted(this.port);
}

// ---------------------------------------------------------------------------
// Isolate entry point
// ---------------------------------------------------------------------------

/// Bundles the [GamePackInterface] factory, command port, and event port so
/// the spawned isolate can create its own pack instance and fire player events
/// back to the UI isolate.
class _IsolateConfig {
  final GamePackInterface Function() packFactory;
  final SendPort commandPort;
  final SendPort eventPort;

  /// Pack ID → rules factory, passed from the UI isolate's [GamePackRegistry].
  final Map<String, GamePackRules Function()> rulesFactoryMap;

  _IsolateConfig({
    required this.packFactory,
    required this.commandPort,
    required this.eventPort,
    required this.rulesFactoryMap,
  });
}


void _serverIsolateEntry(_IsolateConfig config) {
  final receivePort = ReceivePort();
  config.commandPort.send(receivePort.sendPort);

  final pack = config.packFactory();
  final server = GameServer(
    gamePack: pack,
    eventPort: config.eventPort,
    rulesFactoryMap: config.rulesFactoryMap,
  );

  receivePort.listen((message) async {
    if (message is _StartServerCommand) {
      await server.start(
        host: message.host,
        port: message.port,
        initialState: message.initialState,
        webAssetRoot: message.webAssetRoot,
      );
      message.replyPort.send(_ServerStarted(server.port!));
    } else if (message is _StartGameCommand) {
      server.startGame(packId: message.packId);
      message.replyPort.send(null);
    } else if (message is _ResetGameCommand) {
      server.resetGame();
      message.replyPort.send(null);
    } else if (message is _ForceEndVoteCommand) {
      server.startForceEndVote();
      message.replyPort.send(null);
    } else if (message is _StopServerCommand) {
      await server.stop();
      message.replyPort.send(null);
      receivePort.close();
    }
  });
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/// Common interface for a running game server handle.
///
/// Using an abstract class allows widget tests to inject a lightweight fake
/// instead of spinning up a real Isolate + network socket.
abstract class ServerHandle {
  int get port;
  bool get isRunning;

  /// Stream of player join/leave events emitted by the server.
  Stream<PlayerEvent> get playerEvents;

  /// Stream of lobby-state snapshots emitted whenever the lobby changes.
  Stream<LobbyStateEvent> get lobbyStateEvents;

  /// Stream of board-view snapshots emitted after each in-game action.
  Stream<BoardViewEvent> get boardViewEvents;

  /// Stream of force-end vote started events emitted when a vote is initiated.
  Stream<ForceEndVoteStartedEvent> get forceEndVoteStartedEvents;

  /// Stream of force-end vote result events emitted when a vote resolves.
  Stream<ForceEndVoteResultEvent> get forceEndVoteResultEvents;

  /// Stream of game reset events emitted when the game is reset, whether
  /// by a passing force-end vote or by the host manually.
  Stream<GameResetEvent> get gameResetEvents;

  /// Signals the server to transition from lobby to the in-game phase.
  ///
  /// [packId] selects which game-pack rules to activate.
  /// Defaults to `'simple_card_battle'`.
  Future<void> startGame({String packId = 'simple_card_battle'});

  /// Resets the game back to the lobby phase.
  Future<void> resetGame();

  /// Initiates a force-end vote among all currently connected players.
  ///
  /// Does nothing if the session is not in the inGame phase, or if a vote
  /// is already in progress.
  Future<void> startForceEndVote();

  Future<void> stop();
}

/// Handle to a [GameServer] running inside an Isolate.
class ServerIsolateHandle implements ServerHandle {
  @override
  final int port;
  final SendPort _commandPort;
  bool _running;
  final StreamController<PlayerEvent> _eventController =
      StreamController<PlayerEvent>.broadcast();
  final StreamController<LobbyStateEvent> _lobbyController =
      StreamController<LobbyStateEvent>.broadcast();
  final StreamController<BoardViewEvent> _boardViewController =
      StreamController<BoardViewEvent>.broadcast();
  final StreamController<ForceEndVoteStartedEvent> _voteStartedController =
      StreamController<ForceEndVoteStartedEvent>.broadcast();
  final StreamController<ForceEndVoteResultEvent> _voteResultController =
      StreamController<ForceEndVoteResultEvent>.broadcast();
  final StreamController<GameResetEvent> _gameResetController =
      StreamController<GameResetEvent>.broadcast();

  ServerIsolateHandle._({
    required this.port,
    required SendPort commandPort,
  })  : _commandPort = commandPort,
        _running = true;

  @override
  bool get isRunning => _running;

  @override
  Stream<PlayerEvent> get playerEvents => _eventController.stream;

  @override
  Stream<LobbyStateEvent> get lobbyStateEvents => _lobbyController.stream;

  @override
  Stream<BoardViewEvent> get boardViewEvents => _boardViewController.stream;

  @override
  Stream<ForceEndVoteStartedEvent> get forceEndVoteStartedEvents =>
      _voteStartedController.stream;

  @override
  Stream<ForceEndVoteResultEvent> get forceEndVoteResultEvents =>
      _voteResultController.stream;

  @override
  Stream<GameResetEvent> get gameResetEvents => _gameResetController.stream;

  @override
  Future<void> startGame({String packId = 'simple_card_battle'}) async {
    final reply = ReceivePort();
    _commandPort.send(_StartGameCommand(replyPort: reply.sendPort, packId: packId));
    await reply.first;
    reply.close();
  }

  @override
  Future<void> resetGame() async {
    final reply = ReceivePort();
    _commandPort.send(_ResetGameCommand(replyPort: reply.sendPort));
    await reply.first;
    reply.close();
  }

  @override
  Future<void> startForceEndVote() async {
    final reply = ReceivePort();
    _commandPort.send(_ForceEndVoteCommand(replyPort: reply.sendPort));
    await reply.first;
    reply.close();
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    final reply = ReceivePort();
    _commandPort.send(_StopServerCommand(replyPort: reply.sendPort));
    await reply.first;
    reply.close();
    _running = false;
    await _eventController.close();
    await _lobbyController.close();
    await _boardViewController.close();
    await _voteStartedController.close();
    await _voteResultController.close();
    await _gameResetController.close();
  }
}

/// Launches a [GameServer] in a dedicated Isolate using [packFactory] to
/// create the game pack inside the isolate's memory space.
class ServerIsolate {
  static Future<ServerIsolateHandle> start({
    required GamePackInterface Function() packFactory,
    required GameState initialState,
    String host = '0.0.0.0',
    int port = 8080,
    Map<String, GamePackRules Function()> rulesFactoryMap = const {},
    String? webAssetRoot,
  }) async {
    // Event port receives PlayerEvent messages from the server isolate.
    final eventReceivePort = ReceivePort();

    final bootstrapPort = ReceivePort();
    await Isolate.spawn(
      _serverIsolateEntry,
      _IsolateConfig(
        packFactory: packFactory,
        commandPort: bootstrapPort.sendPort,
        eventPort: eventReceivePort.sendPort,
        rulesFactoryMap: rulesFactoryMap,
      ),
    );

    final SendPort commandPort = await bootstrapPort.first as SendPort;
    bootstrapPort.close();

    final replyPort = ReceivePort();
    commandPort.send(
      _StartServerCommand(
        host: host,
        port: port,
        initialState: initialState,
        replyPort: replyPort.sendPort,
        webAssetRoot: webAssetRoot,
      ),
    );
    final started = await replyPort.first as _ServerStarted;
    replyPort.close();

    final handle = ServerIsolateHandle._(
      port: started.port,
      commandPort: commandPort,
    );

    // Forward events from the ReceivePort to the handle's StreamControllers.
    eventReceivePort.listen((event) {
      if (event is PlayerEvent && !handle._eventController.isClosed) {
        handle._eventController.add(event);
      } else if (event is LobbyStateEvent && !handle._lobbyController.isClosed) {
        handle._lobbyController.add(event);
      } else if (event is BoardViewEvent &&
          !handle._boardViewController.isClosed) {
        handle._boardViewController.add(event);
      } else if (event is ForceEndVoteStartedEvent &&
          !handle._voteStartedController.isClosed) {
        handle._voteStartedController.add(event);
      } else if (event is ForceEndVoteResultEvent &&
          !handle._voteResultController.isClosed) {
        handle._voteResultController.add(event);
      } else if (event is GameResetEvent &&
          !handle._gameResetController.isClosed) {
        handle._gameResetController.add(event);
      }
    });

    return handle;
  }
}
