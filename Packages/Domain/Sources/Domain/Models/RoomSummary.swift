import Foundation

/// One joined room as the room list shows it: its name and its last message. The last message is message content, so
/// `description` and `debugDescription` leave its text out and printing a summary never logs it (ADR 0009).
public struct RoomSummary: Sendable, Equatable, Identifiable {
  /// The Matrix room id.
  public let id: String
  /// The room's display name.
  public let name: String
  /// The text of the last message: the body of a text, the caption of a picture or video, the name of a file, the
  /// question of a poll; `nil` when it has none.
  public let lastMessageText: String?
  /// What the last message is, so the row names a picture, a poll or a deleted message (Flutter, web
  /// `roomRowText.ts`); `nil` when the last event is not a message.
  public let lastMessageKind: MessageKind?
  /// The signed-in user sent the last message: the row writes "You:" and shows its send state.
  public let isLastMessageOwn: Bool
  /// The send state of the user's own last message; `nil` when the last message is someone else's.
  public let lastMessageSendState: SendState?
  /// The display name of the last message's sender, or its Matrix id when the name is not known.
  public let lastMessageSender: String?
  /// When the last event was sent, or `nil` when the room has none.
  public let lastActivity: Date?
  /// Messages the user has not read yet.
  public let unreadCount: Int
  /// The user marked the room as unread (`m.marked_unread`); the row shows a dot when no message is unread.
  public let isMarkedUnread: Bool
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
  /// The room is end-to-end encrypted; the row shows a lock, as the Flutter chat list does.
  public let isEncrypted: Bool
  /// Who is typing in the room, other than the user; the row shows it in place of the last message.
  public var typingNames: [String]
  public let directUserId: String?
  public let isPublic: Bool

  /// What a room's last message is.
  public enum MessageKind: Sendable, Equatable {
    case text, emote, notice, picture, video, audio, voice, file, location, sticker, poll, deleted,
      encrypted
  }

  /// Where the user's own last message is.
  public enum SendState: Sendable, Equatable {
    case sending, sent, failed
  }

  public init(
    id: String, name: String, lastMessageText: String?, lastMessageSender: String?,
    lastActivity: Date?, lastMessageKind: MessageKind? = nil, isLastMessageOwn: Bool = false,
    lastMessageSendState: SendState? = nil, unreadCount: Int = 0, isMarkedUnread: Bool = false,
    mentionCount: Int = 0, avatar: MediaReference? = nil, isInvite: Bool = false,
    isFavourite: Bool = false, isDirect: Bool = false, isMuted: Bool = false,
    isArchived: Bool = false, isSpace: Bool = false, isLowPriority: Bool = false,
    draft: String? = nil, isBroadcast: Bool = false, isEncrypted: Bool = false,
    typingNames: [String] = [], directUserId: String? = nil, isPublic: Bool = false
  ) {
    self.typingNames = typingNames
    self.directUserId = directUserId
    self.isPublic = isPublic
    self.lastMessageKind = lastMessageKind
    self.isLastMessageOwn = isLastMessageOwn
    self.lastMessageSendState = lastMessageSendState
    self.isMarkedUnread = isMarkedUnread
    self.isEncrypted = isEncrypted
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
  public var badgeCount: Int { isMuted || isSpace ? 0 : max(unreadCount, isMarkedUnread ? 1 : 0) }

  /// The room has unread messages or the user marked it as unread: it shows under the Unread filter, in bold.
  public var isUnread: Bool { unreadCount > 0 || isMarkedUnread }

  /// The app icon badge for these rooms: the unread messages of the rooms that are not muted.
  public static func appBadge(for rooms: [RoomSummary]) -> Int {
    rooms.reduce(0) { $0 + $1.badgeCount }
  }
}
