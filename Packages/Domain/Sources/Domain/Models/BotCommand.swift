import Foundation

/// A command a bot in the room answers (MSC4332 « In-room bot commands »), as the web client reads them from the state
/// events `org.matrix.msc4332.commands` (or `m.bot.commands`), one per bot, keyed by its user id.
public struct BotCommand: Sendable, Equatable, Hashable, Identifiable {
  public let botUserId: String
  /// As announced: `gif {search} {words...}`.
  public let syntax: String
  public let description: String
  /// `gif`.
  public let name: String
  public let argumentNames: [String]
  /// The last argument takes the rest of the words (`{words...}`).
  public let isLastArgumentVariadic: Bool

  public var id: String { botUserId + " " + syntax }

  public init(botUserId: String, syntax: String, description: String) {
    self.botUserId = botUserId
    self.syntax = syntax
    self.description = description
    let parsed = Self.parse(syntax)
    name = parsed.name
    argumentNames = parsed.argumentNames
    isLastArgumentVariadic = parsed.isLastArgumentVariadic
  }

  /// `gif {search} {words...}` → `gif`, [`search`, `words`], variadic (web `parseSyntax`).
  static func parse(_ syntax: String) -> (
    name: String, argumentNames: [String], isLastArgumentVariadic: Bool
  ) {
    let words = syntax.split(whereSeparator: \.isWhitespace).map(String.init)
    let name = words.first ?? ""
    let arguments = words.dropFirst().compactMap { word -> String? in
      guard word.hasPrefix("{"), word.hasSuffix("}"), word.count > 2 else { return nil }
      return String(word.dropFirst().dropLast())
    }
    let variadic = arguments.last?.hasSuffix("...") ?? false
    return (
      name,
      arguments.map { $0.hasSuffix("...") ? String($0.dropLast(3)) : $0 },
      variadic
    )
  }

  /// The commands of one state event's content; entries without a syntax are left out.
  public static func commands(botUserId: String, content: [String: Any]) -> [BotCommand] {
    guard let list = content["commands"] as? [[String: Any]] else { return [] }
    return list.compactMap { entry in
      guard let syntax = entry["syntax"] as? String else { return nil }
      let texts = (entry["description"] as? [String: Any])?["m.text"] as? [[String: Any]]
      let command = BotCommand(
        botUserId: botUserId, syntax: syntax,
        description: texts?.first?["body"] as? String ?? "")
      return command.name.isEmpty ? nil : command
    }
  }

  /// The message content that runs the command: the typed text as its body, and the command with its arguments
  /// (web `buildCommandContent`): the words after the name, the last argument taking the rest.
  public func content(for text: String) -> [String: Any] {
    var words = text.split(whereSeparator: \.isWhitespace).map(String.init)
    if let first = words.first, first.hasPrefix("/") || first.hasPrefix("!") { words.removeFirst() }
    var arguments: [String: Any] = [:]
    for (index, argument) in argumentNames.enumerated() {
      let isLast = index == argumentNames.count - 1
      let value = isLast ? Array(words.dropFirst(index)) : Array(words.dropFirst(index).prefix(1))
      guard !value.isEmpty else { continue }
      if isLastArgumentVariadic, isLast {
        arguments[argument + "..."] = value
      } else {
        arguments[argument] = value.joined(separator: " ")
      }
    }
    return [
      "msgtype": "m.text", "body": text,
      "org.matrix.msc4332.command": ["syntax": syntax, "arguments": arguments],
    ]
  }

  /// The commands whose name starts with what follows "/" at the start of `draft`, before any space.
  public static func matching(_ draft: String, in commands: [BotCommand]) -> [BotCommand] {
    guard draft.hasPrefix("/"), !draft.dropFirst().contains(where: \.isWhitespace) else {
      return []
    }
    let typed = draft.dropFirst().lowercased()
    return commands.filter { typed.isEmpty || $0.name.lowercased().hasPrefix(typed) }
  }

  /// The command the draft runs: its first word is `/name` of a known command.
  public static func command(for draft: String, in commands: [BotCommand]) -> BotCommand? {
    guard draft.hasPrefix("/"),
      let first = draft.split(whereSeparator: \.isWhitespace).first
    else { return nil }
    let name = first.dropFirst().lowercased()
    return commands.first { $0.name.lowercased() == name }
  }
}
