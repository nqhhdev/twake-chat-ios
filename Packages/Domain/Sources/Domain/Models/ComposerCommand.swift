import Foundation

/// What a typed text becomes when it starts with « / », as the web client reads it (`prepareCommandText`): `/me` sends
/// an emote, `/shrug` adds the shrug, « // » sends a text that starts with « / », and any other « /word » is a mistake
/// that is not sent. A bot's command is read before this (`BotCommand.command(for:in:)`).
public enum ComposerCommand: Sendable, Equatable {
  /// A plain message with this text.
  case message(String)
  /// An emote (`m.emote`): « Alice waves ».
  case emote(String)
  /// « /word » that no client or bot command answers; `word` is its name.
  case unknown(String)

  /// « ¯\_(ツ)_/¯ » written as Markdown, which the message is sent as: the backslash and the underscores are escaped
  /// so the formatted message keeps the arm and shows no italics.
  public static let shrug = #"¯\\\_(ツ)\_/¯"#

  public static func prepare(_ text: String) -> ComposerCommand {
    if text.hasPrefix("//") { return .message(String(text.dropFirst())) }
    guard let match = text.firstMatch(of: /^\/([^\s\/]+)(?:\s+|$)/) else { return .message(text) }
    let name = match.output.1.lowercased()
    let rest = String(text[match.range.upperBound...])
    switch name {
    case "me" where !rest.isEmpty: return .emote(rest)
    case "shrug": return .message(rest.isEmpty ? shrug : rest + " " + shrug)
    default: return .unknown(name)
    }
  }
}
