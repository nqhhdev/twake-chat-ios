import Foundation

/// One joined room as the room list shows it: its name and its last message. The last message is message content, so
/// `description` and `debugDescription` leave its text out and printing a summary never logs it (ADR 0009).
public struct RoomSummary: Sendable, Equatable, Identifiable {
  /// The Matrix room id.
  public let id: String
  /// The room's display name.
  public let name: String
  /// The text of the last message, or `nil` when the last event is not a text-like message.
  public let lastMessageText: String?
  /// The display name of the last message's sender, or its Matrix id when the name is not known.
  public let lastMessageSender: String?
  /// When the last event was sent, or `nil` when the room has none.
  public let lastActivity: Date?
  /// Messages the user has not read yet.
  public let unreadCount: Int
  /// Unread messages that mention the user.
  public let mentionCount: Int

  public init(
    id: String, name: String, lastMessageText: String?, lastMessageSender: String?,
    lastActivity: Date?, unreadCount: Int = 0, mentionCount: Int = 0
  ) {
    self.id = id
    self.name = name
    self.lastMessageText = lastMessageText
    self.lastMessageSender = lastMessageSender
    self.lastActivity = lastActivity
    self.unreadCount = unreadCount
    self.mentionCount = mentionCount
  }
}

extension RoomSummary: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    "RoomSummary(id: \(id), lastMessageText: \(lastMessageText == nil ? "nil" : "<redacted>"))"
  }

  public var debugDescription: String { description }
}
