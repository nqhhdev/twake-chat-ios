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
  /// The room's picture, or `nil` when it has none.
  public let avatar: MediaReference?
  /// The user is invited and has not joined yet.
  public let isInvite: Bool
  /// The user marked the room as a favourite; the list shows favourites first.
  public let isFavourite: Bool
  /// A direct chat with one person, rather than a group.
  public let isDirect: Bool
  /// The user muted the room: no notification.
  public let isMuted: Bool
  /// The user left the room: it is in the archive and opens read-only.
  public let isArchived: Bool
  /// A space: it holds rooms instead of messages, and opens as the list of its rooms.
  public let isSpace: Bool
  /// The user put the room in low priority (`m.lowpriority` tag); the list shows it at the bottom.
  public let isLowPriority: Bool
  /// The text the user left in the composer of this room, shown on its row in place of the last message.
  public let draft: String?
  /// Only moderators and administrators post (`events_default` 50 or more): a Broadcast, typed or not (web D109).
  public let isBroadcast: Bool

  public init(
    id: String, name: String, lastMessageText: String?, lastMessageSender: String?,
    lastActivity: Date?, unreadCount: Int = 0, mentionCount: Int = 0, avatar: MediaReference? = nil,
    isInvite: Bool = false, isFavourite: Bool = false, isDirect: Bool = false,
    isMuted: Bool = false, isArchived: Bool = false, isSpace: Bool = false,
    isLowPriority: Bool = false, draft: String? = nil, isBroadcast: Bool = false
  ) {
    self.isBroadcast = isBroadcast
    self.draft = draft
    self.isLowPriority = isLowPriority
    self.isArchived = isArchived
    self.isSpace = isSpace
    self.id = id
    self.name = name
    self.lastMessageText = lastMessageText
    self.lastMessageSender = lastMessageSender
    self.lastActivity = lastActivity
    self.unreadCount = unreadCount
    self.mentionCount = mentionCount
    self.avatar = avatar
    self.isInvite = isInvite
    self.isFavourite = isFavourite
    self.isDirect = isDirect
    self.isMuted = isMuted
  }
}

extension RoomSummary: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    "RoomSummary(id: \(id), lastMessageText: \(lastMessageText == nil ? "nil" : "<redacted>"))"
  }

  public var debugDescription: String { description }
}

extension RoomSummary {
  /// What this room adds to the app icon badge: nothing when it is muted, since a muted room sends no notification
  /// (its push rule is `dont_notify`), even for a mention.
  public var badgeCount: Int { isMuted || isSpace ? 0 : unreadCount }

  /// The app icon badge for these rooms: the unread messages of the rooms that are not muted.
  public static func appBadge(for rooms: [RoomSummary]) -> Int {
    rooms.reduce(0) { $0 + $1.badgeCount }
  }
}
