import '../game_pack/views/board_view.dart';
import 'ws_message.dart';

/// Carries a [BoardView] broadcast from the GameBoard server to all clients.
///
/// Contains only public game information — no player hand data.
class BoardViewMessage {
  final BoardView boardView;

  const BoardViewMessage({required this.boardView});

  WsMessage toEnvelope() => WsMessage(
        type: WsMessageType.boardView,
        payload: {'boardView': boardView.toJson()},
      );

  factory BoardViewMessage.fromEnvelope(WsMessage msg) {
    assert(msg.type == WsMessageType.boardView);
    return BoardViewMessage(
      boardView: BoardView.fromJson(
        msg.payload['boardView'] as Map<String, dynamic>,
      ),
    );
  }
}
