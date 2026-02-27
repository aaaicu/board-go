import '../game_pack/views/player_view.dart';
import 'ws_message.dart';

/// Carries a [PlayerView] from the GameBoard server to a specific GameNode.
///
/// This message is sent individually to each player — never broadcast —
/// to preserve the privacy of each player's hand.
class PlayerViewMessage {
  final PlayerView playerView;

  const PlayerViewMessage({required this.playerView});

  WsMessage toEnvelope() => WsMessage(
        type: WsMessageType.playerView,
        payload: {'playerView': playerView.toJson()},
      );

  factory PlayerViewMessage.fromEnvelope(WsMessage msg) {
    assert(msg.type == WsMessageType.playerView);
    return PlayerViewMessage(
      playerView: PlayerView.fromJson(
        msg.payload['playerView'] as Map<String, dynamic>,
      ),
    );
  }
}
