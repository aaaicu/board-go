import 'ws_message.dart';

/// A heartbeat ping message sent from client to server.
///
/// The server responds with a [PongMessage] carrying the same [timestamp].
/// This allows the client to measure round-trip latency and detect stale
/// connections within a predictable time window.
class PingMessage {
  /// Milliseconds since epoch at the moment the ping was created.
  final int timestamp;

  const PingMessage({required this.timestamp});

  factory PingMessage.now() =>
      PingMessage(timestamp: DateTime.now().millisecondsSinceEpoch);

  factory PingMessage.fromEnvelope(WsMessage msg) =>
      PingMessage(timestamp: msg.payload['timestamp'] as int);

  WsMessage toEnvelope() => WsMessage(
        type: WsMessageType.ping,
        payload: {'timestamp': timestamp},
      );

  Map<String, dynamic> toJson() => {'timestamp': timestamp};
}

/// A heartbeat pong response sent from server to client.
///
/// The [timestamp] echoes back the value from the originating [PingMessage].
class PongMessage {
  final int timestamp;

  const PongMessage({required this.timestamp});

  factory PongMessage.fromEnvelope(WsMessage msg) =>
      PongMessage(timestamp: msg.payload['timestamp'] as int);

  WsMessage toEnvelope() => WsMessage(
        type: WsMessageType.pong,
        payload: {'timestamp': timestamp},
      );
}
