import 'package:flutter/widgets.dart';

import '../../../client/gameboard/stockpile_board_widget.dart';
import '../../../client/gamenode/stockpile_player_widget.dart';
import '../game_pack_registry.dart';
import 'simple_card_game_emotes.dart';
import 'stockpile_rules.dart';

/// Registration for the Stockpile game pack.
GamePackRegistration stockpileRegistration() => GamePackRegistration(
      packId: 'stockpile',
      rulesFactory: ({cards = const []}) => StockpileRules(),
      boardWidgetBuilder: ({
        required boardView,
        playerNames = const {},
        serverStatusWidget,
        voteInProgress = false,
        showServerStatus = false,
        onToggleServerStatus,
        onForceEndVote,
      }) =>
          StockpileBoardWidget(
        boardView: boardView,
        playerNames: playerNames,
        serverStatusWidget: serverStatusWidget,
        voteInProgress: voteInProgress,
        showServerStatus: showServerStatus,
        onToggleServerStatus: onToggleServerStatus,
        onForceEndVote: onForceEndVote,
      ),
      nodeWidgetBuilder: ({
        required playerView,
        required onAction,
      }) =>
          StockpilePlayerWidget(
        playerView: playerView,
        onAction: onAction,
      ),
      emoteConfig: const PackEmoteConfig(
        emoteType: SimpleCardGameEmote.emote,
        chatType: SimpleCardGameEmote.chat,
        chatMaxLength: SimpleCardGameEmote.chatMaxLength,
        emojis: SimpleCardGameEmote.all,
      ),
    );
