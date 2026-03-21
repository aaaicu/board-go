/// NodeMessage type constants for the simple_card_battle game pack.
///
/// Used by both server-side [SimpleCardGameRules.onNodeMessage] (to validate
/// incoming emote messages) and the GameNode UI (to send emotes).
abstract final class SimpleCardGameEmote {
  /// The [NodeMessage.type] value for all emote messages.
  static const String emote = 'EMOTE';

  /// The [NodeMessage.type] value for short text chat messages.
  ///
  /// Payload key: `'text'` — UTF-16 length must be 1–20 characters.
  static const String chat = 'CHAT';

  /// Maximum character length for a [chat] message.
  static const int chatMaxLength = 20;

  // ---------------------------------------------------------------------------
  // Supported emoji values (payload key: 'emoji')
  // ---------------------------------------------------------------------------

  static const String thumbsUp = '\u{1F44D}'; // 👍
  static const String laugh = '\u{1F602}'; // 😂
  static const String surprised = '\u{1F631}'; // 😱
  static const String celebrate = '\u{1F389}'; // 🎉

  /// The complete allowlist of valid emoji values for [emote] messages.
  static const List<String> all = [thumbsUp, laugh, surprised, celebrate];
}
