/// All possible WebSocket message types exchanged between GameBoard and GameNode.
enum WsMessageType {
  action,
  stateUpdate,
  join,
  leave,
  error,
  // Lobby protocol additions (Sprint 1)
  joinRoomAck,
  lobbyState,
  setReady,
  ping,
  pong,
  // Game loop additions (Sprint 2)
  playerView,
  boardView,
  actionRejected,
  startGame;

  String toJson() => switch (this) {
        WsMessageType.action => 'ACTION',
        WsMessageType.stateUpdate => 'STATE_UPDATE',
        WsMessageType.join => 'JOIN',
        WsMessageType.leave => 'LEAVE',
        WsMessageType.error => 'ERROR',
        WsMessageType.joinRoomAck => 'JOIN_ROOM_ACK',
        WsMessageType.lobbyState => 'LOBBY_STATE',
        WsMessageType.setReady => 'SET_READY',
        WsMessageType.ping => 'PING',
        WsMessageType.pong => 'PONG',
        WsMessageType.playerView => 'PLAYER_VIEW',
        WsMessageType.boardView => 'BOARD_VIEW',
        WsMessageType.actionRejected => 'ACTION_REJECTED',
        WsMessageType.startGame => 'START_GAME',
      };

  static WsMessageType fromJson(String value) => switch (value) {
        'ACTION' => WsMessageType.action,
        'STATE_UPDATE' => WsMessageType.stateUpdate,
        'JOIN' => WsMessageType.join,
        'LEAVE' => WsMessageType.leave,
        'ERROR' => WsMessageType.error,
        'JOIN_ROOM_ACK' => WsMessageType.joinRoomAck,
        'LOBBY_STATE' => WsMessageType.lobbyState,
        'SET_READY' => WsMessageType.setReady,
        'PING' => WsMessageType.ping,
        'PONG' => WsMessageType.pong,
        'PLAYER_VIEW' => WsMessageType.playerView,
        'BOARD_VIEW' => WsMessageType.boardView,
        'ACTION_REJECTED' => WsMessageType.actionRejected,
        'START_GAME' => WsMessageType.startGame,
        _ => throw FormatException('Unknown WsMessageType: $value'),
      };
}

/// The envelope that wraps every WebSocket message.
///
/// ```json
/// {
///   "type": "ACTION",
///   "payload": { ... },
///   "timestamp": 1708612345678
/// }
/// ```
class WsMessage {
  final WsMessageType type;
  final Map<String, dynamic> payload;
  final int timestamp;

  WsMessage({
    required this.type,
    required this.payload,
    int? timestamp,
  }) : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch;

  factory WsMessage.fromJson(Map<String, dynamic> json) {
    return WsMessage(
      type: WsMessageType.fromJson(json['type'] as String),
      payload: (json['payload'] as Map<String, dynamic>?) ?? {},
      timestamp: json['timestamp'] as int? ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.toJson(),
        'payload': payload,
        'timestamp': timestamp,
      };
}
