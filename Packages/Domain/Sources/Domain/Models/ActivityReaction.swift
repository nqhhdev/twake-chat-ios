import Foundation

/// A reaction of someone else on a message of the user, for the Activity (web D58, `domain/activity.ts`): the emoji,
/// who, when, the room and an excerpt of the message reacted to.
public struct ActivityReaction: Sendable, Equatable, Identifiable {
  public let roomId: String
  public let roomName: String
  /// The message reacted to.
  public let eventId: String
  public let key: String
  public let senderId: String
  public let senderName: String
  public let reactedAt: Date
  /// The text of the message reacted to; `nil` when it has none to show (a deleted or unreadable message).
  public let messageText: String?

  public var id: String { [roomId, eventId, key, senderId].joined(separator: "|") }

  public init(
    roomId: String, roomName: String, eventId: String, key: String, senderId: String,
    senderName: String, reactedAt: Date, messageText: String?
  ) {
    self.roomId = roomId
    self.roomName = roomName
    self.eventId = eventId
    self.key = key
    self.senderId = senderId
    self.senderName = senderName
    self.reactedAt = reactedAt
    self.messageText = messageText
  }
}

/// The web's `buildActivity` for reactions: newest first, 50 at most.
public enum ActivityReactions {
  /// How many the Activity shows (web `ACTIVITY_LIMIT`).
  public static let limit = 50

  /// The reactions of other people on the user's messages, newest first, at most `limit`. A reaction the user sent is
  /// left out: it is not something that happened to them.
  public static func newest(_ reactions: [ActivityReaction], ownUserId: String?)
    -> [ActivityReaction]
  {
    Array(
      reactions.filter { $0.senderId != ownUserId }
        .sorted { $0.reactedAt > $1.reactedAt }
        .prefix(limit))
  }
}
