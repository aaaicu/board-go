import 'package:flutter/widgets.dart';

import '../../../client/gameboard/secret_hitler_board_widget.dart';
import '../../../client/gamenode/secret_hitler_node_widget.dart';
import '../game_pack_registry.dart';
import 'simple_card_game_emotes.dart';
import 'secret_hitler_rules.dart';

/// Registration for the Secret Hitler game pack.
GamePackRegistration secretHitlerRegistration() => GamePackRegistration(
      packId: 'secret_hitler',
      rulesFactory: ({cards = const []}) => SecretHitlerRules(),
      boardWidgetBuilder: ({
        required boardView,
        playerNames = const {},
        serverStatusWidget,
        voteInProgress = false,
        showServerStatus = false,
        onToggleServerStatus,
        onForceEndVote,
      }) =>
          SecretHitlerBoardWidget(
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
          SecretHitlerNodeWidget(
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
