import 'dart:async';
import 'dart:isolate';

import '../shared/game_pack/game_pack_interface.dart';
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

  const PlayerEvent({
    required this.joined,
    required this.playerId,
    required this.displayName,
  });
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

  _StartServerCommand({
    required this.host,
    required this.port,
    required this.initialState,
    required this.replyPort,
  });
}

class _StopServerCommand extends _ServerCommand {
  final SendPort replyPort;
  _StopServerCommand({required this.replyPort});
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

  _IsolateConfig({
    required this.packFactory,
    required this.commandPort,
    required this.eventPort,
  });
}

void _serverIsolateEntry(_IsolateConfig config) {
  final receivePort = ReceivePort();
  config.commandPort.send(receivePort.sendPort);

  final pack = config.packFactory();
  final server = GameServer(gamePack: pack, eventPort: config.eventPort);

  receivePort.listen((message) async {
    if (message is _StartServerCommand) {
      await server.start(
        host: message.host,
        port: message.port,
        initialState: message.initialState,
      );
      message.replyPort.send(_ServerStarted(server.port!));
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
  Future<void> stop() async {
    if (!_running) return;
    final reply = ReceivePort();
    _commandPort.send(_StopServerCommand(replyPort: reply.sendPort));
    await reply.first;
    reply.close();
    _running = false;
    await _eventController.close();
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
      ),
    );
    final started = await replyPort.first as _ServerStarted;
    replyPort.close();

    final handle = ServerIsolateHandle._(
      port: started.port,
      commandPort: commandPort,
    );

    // Forward PlayerEvents from the ReceivePort to the handle's StreamController.
    eventReceivePort.listen((event) {
      if (event is PlayerEvent && !handle._eventController.isClosed) {
        handle._eventController.add(event);
      }
    });

    return handle;
  }
}
