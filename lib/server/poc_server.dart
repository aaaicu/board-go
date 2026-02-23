import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Minimal shelf WebSocket server for Phase 0 PoC.
///
/// Handles WebSocket connections at `/ws` and echoes every received message
/// back to the sender prefixed with `"echo: "`.
class PocServer {
  HttpServer? _httpServer;

  int? get port => _httpServer?.port;

  bool get isRunning => _httpServer != null;

  Future<void> start({String host = '0.0.0.0', int port = 8080}) async {
    final router = Router();

    router.get(
      '/ws',
      webSocketHandler((WebSocketChannel channel) {
        channel.stream.listen(
          (message) {
            channel.sink.add('echo: $message');
          },
          onError: (_) {
            channel.sink.close();
          },
          cancelOnError: true,
        );
      }),
    );

    _httpServer = await shelf_io.serve(
      const Pipeline().addMiddleware(logRequests()).addHandler(router.call),
      host,
      port,
    );
  }

  Future<void> stop() async {
    await _httpServer?.close(force: true);
    _httpServer = null;
  }
}

// ---------------------------------------------------------------------------
// Isolate support
// ---------------------------------------------------------------------------

/// Message sent from the main isolate to the server isolate.
sealed class _IsolateCommand {}

class _StartCommand extends _IsolateCommand {
  final String host;
  final int port;
  final SendPort replyPort;
  _StartCommand({
    required this.host,
    required this.port,
    required this.replyPort,
  });
}

class _StopCommand extends _IsolateCommand {
  final SendPort replyPort;
  _StopCommand({required this.replyPort});
}

/// Payload sent back from the server isolate after the server starts.
class _ServerStartedPayload {
  final int port;
  _ServerStartedPayload(this.port);
}

/// Isolate entry point.  Must be a top-level function.
void serverIsolateEntryPoint(SendPort commandPort) {
  // The server isolate owns the ReceivePort for incoming commands.
  final receivePort = ReceivePort();
  commandPort.send(receivePort.sendPort);

  PocServer? server;

  receivePort.listen((message) async {
    if (message is _StartCommand) {
      server = PocServer();
      await server!.start(host: message.host, port: message.port);
      message.replyPort.send(_ServerStartedPayload(server!.port!));
    } else if (message is _StopCommand) {
      await server?.stop();
      server = null;
      message.replyPort.send(null);
      receivePort.close();
    }
  });
}

/// Handle returned by [IsolateRunner.start]; use it to communicate with the
/// server isolate and eventually stop it.
class IsolateRunnerHandle {
  final int port;
  final SendPort _commandPort;
  bool _running;

  IsolateRunnerHandle._({
    required this.port,
    required SendPort commandPort,
  })  : _commandPort = commandPort,
        _running = true;

  bool get isRunning => _running;

  Future<void> stop() async {
    if (!_running) return;
    final reply = ReceivePort();
    _commandPort.send(_StopCommand(replyPort: reply.sendPort));
    await reply.first;
    reply.close();
    _running = false;
  }
}

/// Spawns a [serverIsolateEntryPoint] isolate, starts the WebSocket server
/// inside it, and returns a [IsolateRunnerHandle] once the server is ready.
class IsolateRunner {
  static Future<IsolateRunnerHandle> start({
    String host = '0.0.0.0',
    int port = 8080,
  }) async {
    // Step 1: Spawn the isolate; it will send back its ReceivePort's SendPort.
    final bootstrapPort = ReceivePort();
    await Isolate.spawn(serverIsolateEntryPoint, bootstrapPort.sendPort);
    final SendPort commandPort = await bootstrapPort.first as SendPort;
    bootstrapPort.close();

    // Step 2: Send the start command.
    final replyPort = ReceivePort();
    commandPort.send(
      _StartCommand(host: host, port: port, replyPort: replyPort.sendPort),
    );
    final payload = await replyPort.first as _ServerStartedPayload;
    replyPort.close();

    return IsolateRunnerHandle._(port: payload.port, commandPort: commandPort);
  }
}
