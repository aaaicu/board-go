import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../shared/messages/ws_message.dart';

/// A reconnectable WebSocket client.
///
/// Call [connect] before sending messages.  Listen to [messages] for incoming
/// raw strings from the server.  Use [sendMessage] / [sendRaw] to send data.
class WsClient {
  final Uri uri;
  final void Function(bool)? onConnectionStateChange;

  WebSocketChannel? _channel;
  bool _connected = false;

  // Re-use the same broadcast StreamController across reconnections.
  final StreamController<dynamic> _controller =
      StreamController<dynamic>.broadcast();

  WsClient({required this.uri, this.onConnectionStateChange});

  bool get isConnected => _connected;

  /// Incoming raw message stream (strings from the server).
  Stream<dynamic> get messages => _controller.stream;

  /// Establishes the WebSocket connection.
  Future<void> connect() async {
    _channel = WebSocketChannel.connect(uri);
    await _channel!.ready;

    _connected = true;
    onConnectionStateChange?.call(true);

    _channel!.stream.listen(
      _controller.add,
      onError: (Object e) {
        _handleDisconnect();
      },
      onDone: _handleDisconnect,
      cancelOnError: false,
    );
  }

  /// Closes the WebSocket connection.
  Future<void> disconnect() async {
    await _channel?.sink.close();
    _channel = null;
    _handleDisconnect();
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

  void _handleDisconnect() {
    if (_connected) {
      _connected = false;
      onConnectionStateChange?.call(false);
    }
  }

  Future<void> dispose() async {
    await disconnect();
    await _controller.close();
  }
}
