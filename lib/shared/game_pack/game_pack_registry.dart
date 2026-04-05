import 'package:flutter/widgets.dart';

import 'card_definition.dart';
import 'game_pack_rules.dart';
import 'views/board_view.dart';
import 'views/player_view.dart';

/// Signature for building the board widget (iPad) for a specific game pack.
typedef BoardWidgetBuilder = Widget Function({
  required BoardView boardView,
  Map<String, String> playerNames,
  Widget? serverStatusWidget,
  bool voteInProgress,
  bool showServerStatus,
  VoidCallback? onToggleServerStatus,
  VoidCallback? onForceEndVote,
});

/// Signature for building the node widget (player phone) for a specific game pack.
typedef NodeWidgetBuilder = Widget Function({
  required PlayerView playerView,
  required void Function(String type, Map<String, dynamic> params) onAction,
});

/// Emote/chat configuration provided by a game pack.
///
/// When non-null, the platform renders an emote bar during gameplay using
/// these values instead of hardcoding any pack-specific constants.
class PackEmoteConfig {
  /// The [NodeMessage.type] value for emoji emote messages.
  final String emoteType;

  /// The [NodeMessage.type] value for chat messages.  Null disables chat.
  final String? chatType;

  /// Maximum character length for chat messages.
  final int chatMaxLength;

  /// Ordered list of emoji strings shown in the emote bar.
  final List<String> emojis;

  const PackEmoteConfig({
    required this.emoteType,
    this.chatType,
    this.chatMaxLength = 20,
    required this.emojis,
  });
}

/// Everything a game pack provides when registering with the platform.
class GamePackRegistration {
  /// Unique pack identifier (e.g. `'stockpile'`, `'secret_hitler'`).
  final String packId;

  /// Factory that creates [GamePackRules] for this pack.
  ///
  /// [cards] is injected by [GamePackLoader] for packs that use external card
  /// data from `cards.json`.  Packs that generate their own data can ignore it.
  final GamePackRules Function({List<CardDefinition> cards}) rulesFactory;

  /// Builds the board widget for the GameBoard (iPad).
  /// Null means the platform renders its built-in generic fallback.
  final BoardWidgetBuilder? boardWidgetBuilder;

  /// Builds the node widget for the GameNode (player phone).
  /// Null means the platform renders its built-in generic fallback.
  final NodeWidgetBuilder? nodeWidgetBuilder;

  /// Emote/chat configuration.  Null means no emote bar for this pack.
  final PackEmoteConfig? emoteConfig;

  const GamePackRegistration({
    required this.packId,
    required this.rulesFactory,
    this.boardWidgetBuilder,
    this.nodeWidgetBuilder,
    this.emoteConfig,
  });
}

/// Central registry that decouples platform code from game pack implementations.
///
/// Populated once at app startup (in `main.dart`) and queried by the platform
/// whenever it needs pack-specific rules, widgets, or configuration.
class GamePackRegistry {
  static final GamePackRegistry instance = GamePackRegistry._();
  GamePackRegistry._();

  final Map<String, GamePackRegistration> _packs = {};

  /// Registers a game pack.  Call once per pack in `main.dart`.
  void register(GamePackRegistration registration) {
    _packs[registration.packId] = registration;
  }

  /// Returns the registration for [packId], or `null` if not registered.
  GamePackRegistration? get(String packId) => _packs[packId];

  /// All registered pack IDs in registration order.
  List<String> get registeredPackIds => _packs.keys.toList();

  /// Creates [GamePackRules] for [packId] with optional [cards].
  ///
  /// Throws [UnsupportedError] if [packId] is not registered.
  GamePackRules createRules(String packId,
      {List<CardDefinition> cards = const []}) {
    final reg = _packs[packId];
    if (reg == null) {
      throw UnsupportedError(
        'Pack "$packId" not registered. '
        'Call GamePackRegistry.instance.register() in main.dart.',
      );
    }
    return reg.rulesFactory(cards: cards);
  }

  /// Returns a map of packId -> rules factory suitable for passing into
  /// a server [Isolate].
  ///
  /// The returned closures capture no Flutter-specific state and are safe
  /// to send across isolate boundaries.
  Map<String, GamePackRules Function()> get rulesFactoryMap {
    return {
      for (final e in _packs.entries)
        e.key: () => e.value.rulesFactory(cards: const []),
    };
  }
}
