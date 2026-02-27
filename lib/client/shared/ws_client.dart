import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../shared/messages/ping_message.dart';
import '../../shared/messages/ws_message.dart';

/// Describes the current WebSocket connection state observed by [WsClient].
enum WsConnectionState {
  /// Successfully connected and the server is reachable.
  connected,

  /// The connection has been lost.  The client may attempt to reconnect.
  disconnected,

  /// Actively trying to re-establish a previously active connection.
  reconnecting,
}

/// A reconnectable WebSocket client with client-driven heartbeat.
///
/// ## Heartbeat
/// Once connected, the client sends a [PingMessage] every [pingInterval].
/// If a [PongMessage] is not received within [pongTimeout] the connection
/// is considered dead and [_attemptReconnect] is called.
///
/// ## Auto-reconnect
/// On any unplanned disconnect (socket error, pong timeout) the client
/// performs exponential-backoff reconnect attempts up to [maxReconnectAttempts].
/// Callers observe progress via the [connectionState] stream.
///
/// ## Reconnect Token
/// Set [reconnectToken] to a non-null value before calling [connect] (or
/// receive it from the server's JOIN_ROOM_ACK) so the server can restore the
/// player's seat on reconnect.
///
/// ## Timer Injection
/// [pingInterval], [pongTimeout] and the backoff base are constructor
/// parameters so tests can inject shorter durations without needing to
/// override the [Timer] class.
class WsClient {
  final Uri uri;
  final void Function(bool)? onConnectionStateChange;

  // ---------------------------------------------------------------------------
  // Configuration / injection points
  // ---------------------------------------------------------------------------

  /// How often to send a ping to the server.
  final Duration pingInterval;

  /// Maximum time to wait for a pong before declaring the connection dead.
  final Duration pongTimeout;

  /// Base delay for the first reconnect attempt (doubles each retry).
  final Duration reconnectBaseDelay;

  /// Maximum number of auto-reconnect attempts before giving up.
  final int maxReconnectAttempts;

  // ---------------------------------------------------------------------------
  // Internal state
  // ---------------------------------------------------------------------------

  WebSocketChannel? _channel;
  bool _connected = false;

  /// True after the first successful connect; used to gate auto-reconnect.
  bool _hasConnectedOnce = false;

  /// True when the disconnect was intentional (called [disconnect]).
  bool _intentionalDisconnect = false;

  int _reconnectAttempts = 0;

  Timer? _pingTimer;
  Timer? _pongTimer;

  /// Reconnect token received from the server after a successful JOIN.
  String? reconnectToken;

  // ---------------------------------------------------------------------------
  // Streams
  // ---------------------------------------------------------------------------

  /// Raw incoming message stream (strings from the server).
  final StreamController<dynamic> _messageController =
      StreamController<dynamic>.broadcast();

  /// Connection-state change stream.
  final StreamController<WsConnectionState> _stateController =
      StreamController<WsConnectionState>.broadcast();

  WsClient({
    required this.uri,
    this.onConnectionStateChange,
    this.reconnectToken,
    this.pingInterval = const Duration(seconds: 30),
    this.pongTimeout = const Duration(seconds: 10),
    this.reconnectBaseDelay = const Duration(seconds: 2),
    this.maxReconnectAttempts = 5,
  });

  bool get isConnected => _connected;

  /// Incoming raw message stream (strings from the server).
  Stream<dynamic> get messages => _messageController.stream;

  /// Stream of [WsConnectionState] events.
  Stream<WsConnectionState> get connectionState => _stateController.stream;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Establishes the WebSocket connection.
  Future<void> connect() async {
    _intentionalDisconnect = false;
    _channel = WebSocketChannel.connect(uri);
    await _channel!.ready;

    _connected = true;
    _hasConnectedOnce = true;
    _reconnectAttempts = 0;

    _emit(WsConnectionState.connected);
    onConnectionStateChange?.call(true);

    _channel!.stream.listen(
      _onRawMessage,
      onError: (Object _) => _onSocketClosed(),
      onDone: _onSocketClosed,
      cancelOnError: false,
    );

    _startHeartbeat();
  }

  /// Closes the WebSocket connection intentionally (no auto-reconnect).
  Future<void> disconnect() async {
    _intentionalDisconnect = true;
    _stopHeartbeat();
    await _channel?.sink.close();
    _channel = null;
    _setDisconnected();
  }

  /// Sends a raw string to the server.
  void sendRaw(String data) {
    assert(_connected, 'WsClient: not connected');
    _channel?.sink.add(data);
  }

  /// Serialises [msg] to JSON and sends it.
  void sendMessage(WsMessage msg) {
    sendRaw(jsonEncode(msg.toJson()));
  }

  Future<void> dispose() async {
    await disconnect();
    await _messageController.close();
    if (!_stateController.isClosed) {
      await _stateController.close();
    }
  }

  // ---------------------------------------------------------------------------
  // Heartbeat
  // ---------------------------------------------------------------------------

  void _startHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(pingInterval, (_) => _sendPing());
  }

  void _stopHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _pongTimer?.cancel();
    _pongTimer = null;
  }

  void _sendPing() {
    if (!_connected) return;
    final ping = PingMessage.now();
    sendMessage(ping.toEnvelope());

    // Expect a pong within [pongTimeout].
    _pongTimer?.cancel();
    _pongTimer = Timer(pongTimeout, () {
      // No pong arrived — connection is stale.
      _onSocketClosed();
    });
  }

  void _onPongReceived() {
    _pongTimer?.cancel();
    _pongTimer = null;
  }

  // ---------------------------------------------------------------------------
  // Incoming messages
  // ---------------------------------------------------------------------------

  void _onRawMessage(dynamic raw) {
    // Intercept pong messages for heartbeat bookkeeping; forward everything else.
    try {
      final msg = WsMessage.fromJson(
          jsonDecode(raw as String) as Map<String, dynamic>);
      if (msg.type == WsMessageType.pong) {
        _onPongReceived();
        return; // Do not forward internal heartbeat messages.
      }
    } catch (_) {
      // Fall through — forward the raw message as-is.
    }
    _messageController.add(raw);
  }

  // ---------------------------------------------------------------------------
  // Disconnect / reconnect
  // ---------------------------------------------------------------------------

  void _onSocketClosed() {
    if (!_connected) return; // already handled

    _stopHeartbeat();
    _setDisconnected();

    if (!_intentionalDisconnect && _hasConnectedOnce) {
      _scheduleReconnect();
    }
  }

  void _setDisconnected() {
    if (_connected) {
      _connected = false;
      onConnectionStateChange?.call(false);
      _emit(WsConnectionState.disconnected);
    }
  }

  Future<void> _scheduleReconnect() async {
    if (_reconnectAttempts >= maxReconnectAttempts) {
      // Gave up — remain in disconnected state.
      return;
    }

    _emit(WsConnectionState.reconnecting);

    final exponent = math.min(_reconnectAttempts, 6); // cap at 2^6 = 64
    final delay = reconnectBaseDelay * math.pow(2, exponent).toInt();
    _reconnectAttempts++;

    await Future<void>.delayed(delay);

    if (_intentionalDisconnect) return;

    try {
      await connect();
      // Emit reconnect token hint on the message stream so the caller can
      // re-send a JOIN message with the token.
      if (reconnectToken != null && !_messageController.isClosed) {
        _messageController.add(_kReconnectHint);
      }
    } catch (_) {
      // connect() failed — try again recursively.
      _scheduleReconnect();
    }
  }

  void _emit(WsConnectionState state) {
    if (!_stateController.isClosed) {
      _stateController.add(state);
    }
  }
}

/// A sentinel string placed on the message stream to tell the caller that a
/// reconnect succeeded and a JOIN message with [WsClient.reconnectToken] should
/// be sent.
const String _kReconnectHint = '__ws_client_reconnect__';

/// The sentinel value emitted on [WsClient.messages] after a successful auto-reconnect.
const String wsClientReconnectHint = _kReconnectHint;
