import '../game_pack_registry.dart';
import 'simple_card_game_emotes.dart';
import 'simple_card_game_rules.dart';

/// Registration for the Simple Card Battle game pack.
///
/// Board and node widgets are null — the platform renders its built-in
/// generic card game UI as the fallback.
GamePackRegistration simpleCardGameRegistration() => GamePackRegistration(
      packId: 'simple_card_battle',
      rulesFactory: ({cards = const []}) =>
          SimpleCardGameRules(cardDefinitions: cards),
      emoteConfig: const PackEmoteConfig(
        emoteType: SimpleCardGameEmote.emote,
        chatType: SimpleCardGameEmote.chat,
        chatMaxLength: SimpleCardGameEmote.chatMaxLength,
        emojis: SimpleCardGameEmote.all,
      ),
    );
