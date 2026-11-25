import Foundation

public struct EmojiShortcode: Sendable, Equatable, Identifiable {
  public let shortcode: String
  public let emoji: String

  public var id: String { shortcode }

  public init(shortcode: String, emoji: String) {
    self.shortcode = shortcode
    self.emoji = emoji
  }

  public static let limit = 8

  public static func query(in text: String) -> String? {
    guard !isInCodeBlock(text) else { return nil }
    guard let match = text.firstMatch(of: /(?:\A|\s):([A-Za-z][A-Za-z0-9_+\-]*)\z/) else {
      return nil
    }
    return String(match.output.1)
  }

  public static func matching(_ query: String) -> [EmojiShortcode] {
    let wanted = query.lowercased()
    guard !wanted.isEmpty else { return [] }
    let found = all.filter { $0.shortcode.contains(wanted) }
    let exact = found.filter { $0.shortcode == wanted }
    let starting = found.filter { $0.shortcode != wanted && $0.shortcode.hasPrefix(wanted) }
    let holding = found.filter { !$0.shortcode.hasPrefix(wanted) }
    return Array((exact + starting + holding).prefix(limit))
  }

  public static func suggestions(for text: String) -> [EmojiShortcode] {
    query(in: text).map(matching) ?? []
  }

  public static func replacingQuery(in text: String, with emoji: String) -> String {
    guard let query = query(in: text) else { return text }
    return String(text.dropLast(query.count + 1)) + emoji
  }

  static func isInCodeBlock(_ text: String) -> Bool {
    let fences = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
      .filter { $0.hasPrefix("```") }
    return !fences.count.isMultiple(of: 2)
  }

  static let all: [EmojiShortcode] = table.map { EmojiShortcode(shortcode: $0.0, emoji: $0.1) }

  private static let table: [(String, String)] = [
    ("grinning", "😀"), ("smiley", "😃"), ("smile", "😄"), ("grin", "😁"),
    ("laughing", "😆"), ("sweat_smile", "😅"), ("joy", "😂"), ("rofl", "🤣"),
    ("slightly_smiling_face", "🙂"), ("upside_down_face", "🙃"), ("wink", "😉"),
    ("blush", "😊"), ("innocent", "😇"), ("heart_eyes", "😍"), ("kissing_heart", "😘"),
    ("yum", "😋"), ("stuck_out_tongue_winking_eye", "😜"), ("sunglasses", "😎"),
    ("nerd_face", "🤓"), ("thinking", "🤔"), ("neutral_face", "😐"), ("expressionless", "😑"),
    ("roll_eyes", "🙄"), ("smirk", "😏"), ("open_mouth", "😮"), ("astonished", "😲"),
    ("flushed", "😳"), ("pleading_face", "🥺"), ("cry", "😢"), ("sob", "😭"),
    ("scream", "😱"), ("rage", "😡"), ("angry", "😠"), ("partying_face", "🥳"),
    ("sleeping", "😴"), ("exploding_head", "🤯"), ("grimacing", "😬"), ("hugs", "🤗"),
    ("hand_over_mouth", "🤭"), ("shushing_face", "🤫"), ("zipper_mouth_face", "🤐"),
    ("saluting_face", "🫡"), ("skull", "💀"), ("clown_face", "🤡"), ("ghost", "👻"),
    ("robot", "🤖"), ("see_no_evil", "🙈"),
    ("thumbsup", "👍"), ("thumbsdown", "👎"), ("clap", "👏"), ("raised_hands", "🙌"),
    ("pray", "🙏"), ("muscle", "💪"), ("wave", "👋"), ("handshake", "🤝"), ("v", "✌️"),
    ("crossed_fingers", "🤞"), ("ok_hand", "👌"), ("point_up", "☝️"), ("point_right", "👉"),
    ("eyes", "👀"), ("heart_hands", "🫶"), ("facepalm", "🤦"), ("shrug", "🤷"),
    ("raising_hand", "🙋"),
    ("heart", "❤️"), ("orange_heart", "🧡"), ("yellow_heart", "💛"), ("green_heart", "💚"),
    ("blue_heart", "💙"), ("purple_heart", "💜"), ("black_heart", "🖤"),
    ("broken_heart", "💔"), ("sparkling_heart", "💖"),
    ("fire", "🔥"), ("sparkles", "✨"), ("star", "⭐"), ("zap", "⚡"), ("boom", "💥"),
    ("tada", "🎉"), ("confetti_ball", "🎊"), ("white_check_mark", "✅"),
    ("heavy_check_mark", "✔️"), ("x", "❌"), ("warning", "⚠️"), ("question", "❓"),
    ("exclamation", "❗"),
    ("rocket", "🚀"), ("bulb", "💡"), ("pushpin", "📌"), ("paperclip", "📎"), ("memo", "📝"),
    ("date", "📅"), ("calendar", "📆"), ("hourglass", "⌛"), ("alarm_clock", "⏰"),
    ("lock", "🔒"), ("key", "🔑"), ("bug", "🐛"), ("trophy", "🏆"), ("gift", "🎁"),
    ("birthday", "🎂"), ("cake", "🍰"), ("pizza", "🍕"), ("coffee", "☕"), ("beer", "🍺"),
    ("sunny", "☀️"), ("rainbow", "🌈"), ("umbrella", "☔"), ("snowflake", "❄️"),
    ("rose", "🌹"), ("four_leaf_clover", "🍀"), ("dog", "🐶"), ("cat", "🐱"),
    ("unicorn", "🦄"),
  ]
}
