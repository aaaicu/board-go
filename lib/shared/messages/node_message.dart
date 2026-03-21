import 'ws_message.dart';

/// Envelope for GameNode-to-GameNode messaging routed through the GameBoard.
///
/// All node messages pass through the server so the [GamePackRules.onNodeMessage]
/// hook can intercept, transform, or block them before delivery.
///
/// [toPlayerId] routing semantics:
///   - `null`  → broadcast to all connected players (including the sender).
///   - non-null → unicast to the specified player only.
class NodeMessage {
  final String fromPlayerId;
  final String? toPlayerId; // null = broadcast
  final String type;
  final Map<String, dynamic> payload;

  const NodeMessage({
    required this.fromPlayerId,
    this.toPlayerId,
    required this.type,
    this.payload = const {},
  });

  factory NodeMessage.fromJson(Map<String, dynamic> json) => NodeMessage(
        fromPlayerId: json['fromPlayerId'] as String,
        toPlayerId: json['toPlayerId'] as String?,
        type: json['type'] as String,
        payload: (json['payload'] as Map<String, dynamic>?) ?? {},
      );

  Map<String, dynamic> toJson() => {
        'fromPlayerId': fromPlayerId,
        if (toPlayerId != null) 'toPlayerId': toPlayerId,
        'type': type,
        'payload': payload,
      };

  /// Wraps this message in a [WsMessage] envelope for wire transmission.
  WsMessage toEnvelope() => WsMessage(
        type: WsMessageType.nodeMessage,
        payload: toJson(),
      );

  /// Unwraps a [WsMessage] envelope into a [NodeMessage].
  static NodeMessage fromEnvelope(WsMessage msg) =>
      NodeMessage.fromJson(msg.payload);
}
