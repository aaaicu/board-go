/// Describes a single action the active player is permitted to take.
///
/// The server computes the allowed action list from the current [GameSessionState]
/// and sends it inside each [PlayerView].  The client renders these as buttons.
class AllowedAction {
  /// The action type string sent back to the server (e.g. 'PLAY_CARD').
  final String actionType;

  /// Human-readable label shown on the button in the UI.
  final String label;

  /// Optional parameters (e.g. `{'cardId': 'A♠'}`) pre-filled by the server.
  /// For actions like DRAW_CARD / END_TURN this map is empty.
  final Map<String, dynamic> params;

  const AllowedAction({
    required this.actionType,
    required this.label,
    this.params = const {},
  });

  AllowedAction copyWith({
    String? actionType,
    String? label,
    Map<String, dynamic>? params,
  }) =>
      AllowedAction(
        actionType: actionType ?? this.actionType,
        label: label ?? this.label,
        params: params ?? this.params,
      );

  factory AllowedAction.fromJson(Map<String, dynamic> json) => AllowedAction(
        actionType: json['actionType'] as String,
        label: json['label'] as String,
        params: Map<String, dynamic>.from(
          (json['params'] as Map<String, dynamic>?) ?? {},
        ),
      );

  Map<String, dynamic> toJson() => {
        'actionType': actionType,
        'label': label,
        'params': params,
      };
}
