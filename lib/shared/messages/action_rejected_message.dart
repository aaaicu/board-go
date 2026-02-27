import 'ws_message.dart';

/// Rejection codes sent when the server refuses a player action.
enum ActionRejectedCode {
  /// The action ID was already processed (idempotency replay).
  duplicateAction,

  /// The game is not in [SessionPhase.inGame].
  phaseMismatch,

  /// The sender is not the active player.
  notYourTurn,

  /// The action type or parameters are not in the allowed list.
  invalidAction;

  String toJson() => switch (this) {
        ActionRejectedCode.duplicateAction => 'DUPLICATE_ACTION',
        ActionRejectedCode.phaseMismatch => 'PHASE_MISMATCH',
        ActionRejectedCode.notYourTurn => 'NOT_YOUR_TURN',
        ActionRejectedCode.invalidAction => 'INVALID_ACTION',
      };

  static ActionRejectedCode fromJson(String value) => switch (value) {
        'DUPLICATE_ACTION' => ActionRejectedCode.duplicateAction,
        'PHASE_MISMATCH' => ActionRejectedCode.phaseMismatch,
        'NOT_YOUR_TURN' => ActionRejectedCode.notYourTurn,
        'INVALID_ACTION' => ActionRejectedCode.invalidAction,
        _ => throw FormatException('Unknown ActionRejectedCode: $value'),
      };
}

/// Sent from the GameBoard server to the specific player whose action was
/// rejected, explaining why.
class ActionRejectedMessage {
  /// Echoes the client-provided idempotency key, if one was supplied.
  final String? clientActionId;

  /// Human-readable explanation.
  final String reason;

  /// Machine-readable rejection code.
  final ActionRejectedCode code;

  const ActionRejectedMessage({
    required this.reason,
    required this.code,
    this.clientActionId,
  });

  WsMessage toEnvelope() => WsMessage(
        type: WsMessageType.actionRejected,
        payload: {
          'reason': reason,
          'code': code.toJson(),
          if (clientActionId != null) 'clientActionId': clientActionId,
        },
      );

  factory ActionRejectedMessage.fromEnvelope(WsMessage msg) {
    assert(msg.type == WsMessageType.actionRejected);
    return ActionRejectedMessage(
      reason: msg.payload['reason'] as String,
      code: ActionRejectedCode.fromJson(msg.payload['code'] as String),
      clientActionId: msg.payload['clientActionId'] as String?,
    );
  }
}
