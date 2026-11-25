import Foundation

/// What the chat details screen shows about a room, as the Flutter app's `chat_details` page: its name, description,
/// address, whether it is a direct chat, encrypted or public, and how many people joined.
public struct RoomDetails: Sendable, Equatable {
  public let id: String
  public let name: String
  public let topic: String?
  public let alias: String?
  public let isDirect: Bool
  public let isEncrypted: Bool
  public let isPublic: Bool
  public let joinedMemberCount: Int
  /// The user may change the room's name and topic.
  public let canEdit: Bool
  /// The user may invite people.
  public let canInvite: Bool
  /// The room's picture (for a direct chat without one, the other person's), or `nil`.
  public let avatar: MediaReference?
  /// Who can join (Flutter `room_access`); `nil` for a rule the app does not offer, such as "restricted".
  public let joinRule: JoinRule?
  /// The user may change who can join.
  public let canChangeAccess: Bool
  /// The user may turn encryption on.
  public let canEnableEncryption: Bool
  /// The user may ban members and unban them.
  public let canBan: Bool
  /// The user may delete other people's messages, as a moderator (`redact` power level, Flutter `canRedact`).
  public let canRedactOthers: Bool
  /// The room that replaced this one after an upgrade (`m.room.tombstone`); `nil` while the room is current.
  public let successorRoomId: String?
  /// The other person of a direct chat with one person; `nil` for a group.
  public let directUserId: String?
  /// The user's power level lets them post messages (not so in a Broadcast, where only moderators post, web D90).
  public let canSendMessages: Bool
  /// The user's power level lets them notify everyone in the room (`@room`).
  public let canNotifyRoom: Bool
  /// Only moderators and administrators post (`events_default` 50 or more): a Broadcast, as `RoomSummary.isBroadcast`.
  public let isBroadcast: Bool

  /// Who can join a room.
  public enum JoinRule: Sendable, Equatable, CaseIterable {
    /// Only people invited.
    case invite
    /// Anyone may ask; a member lets them in.
    case knock
    /// Anyone joins.
    case `public`
  }

  public init(
    id: String, name: String, topic: String?, alias: String?, isDirect: Bool, isEncrypted: Bool,
    isPublic: Bool,
    joinedMemberCount: Int, canEdit: Bool = false, canInvite: Bool = false,
    avatar: MediaReference? = nil, joinRule: JoinRule? = nil, canChangeAccess: Bool = false,
    canEnableEncryption: Bool = false, canBan: Bool = false, canRedactOthers: Bool = false,
    successorRoomId: String? = nil, directUserId: String? = nil, canSendMessages: Bool = true,
    canNotifyRoom: Bool = false, isBroadcast: Bool = false
  ) {
    self.canNotifyRoom = canNotifyRoom
    self.isBroadcast = isBroadcast
    self.canSendMessages = canSendMessages
    self.successorRoomId = successorRoomId
    self.directUserId = directUserId
    self.canRedactOthers = canRedactOthers
    self.joinRule = joinRule
    self.canChangeAccess = canChangeAccess
    self.canEnableEncryption = canEnableEncryption
    self.canBan = canBan
    self.id = id
    self.name = name
    self.topic = topic
    self.alias = alias
    self.isDirect = isDirect
    self.isEncrypted = isEncrypted
    self.isPublic = isPublic
    self.joinedMemberCount = joinedMemberCount
    self.canEdit = canEdit
    self.canInvite = canInvite
    self.avatar = avatar
  }
}

/// One member of a room as the members list shows them.
public struct RoomMember: Sendable, Equatable, Identifiable {
  public enum Membership: Sendable, Equatable {
    case joined
    case invited
    case banned
  }

  /// The Matrix user id.
  public let id: String
  public let displayName: String?
  public let membership: Membership
  /// The member's picture, or `nil`.
  public let avatar: MediaReference?
  /// What the member's power level makes them, as the Flutter member list labels it.
  public let role: Role
  /// The member is the signed-in user.
  public let isOwn: Bool
  /// The user may remove this member: they can kick, and the member's power level is lower than theirs.
  public let canBeRemoved: Bool
  /// The user may ban this member: they can ban, and the member's power level is lower than theirs.
  public let canBeBanned: Bool
  /// The roles the user may give this member (none when the member outranks them or is them).
  public let assignableRoles: [Role]

  public enum Role: Sendable, Equatable, Hashable {
    case creator
    case administrator
    case moderator
    case user
  }

  public init(
    id: String, displayName: String?, membership: Membership, avatar: MediaReference? = nil,
    role: Role = .user, isOwn: Bool = false, canBeRemoved: Bool = false,
    canBeBanned: Bool = false, assignableRoles: [Role] = []
  ) {
    self.canBeBanned = canBeBanned
    self.assignableRoles = assignableRoles
    self.id = id
    self.displayName = displayName
    self.membership = membership
    self.avatar = avatar
    self.role = role
    self.isOwn = isOwn
    self.canBeRemoved = canBeRemoved
  }

  /// The entry of the mention list that notifies everyone in the room (`@room`), as the web's `EVERYONE_MENTION`.
  public static let everyone = RoomMember(id: "@room", displayName: "room", membership: .joined)

  /// A mention query offers `everyone` first when it starts « room », « all » or « everyone », the names other apps
  /// give it; a bare « @ » offers it last, so a quick pick never notifies everyone by mistake (web `offersEveryone`).
  public static func offersEveryoneFirst(for query: String) -> Bool {
    let wanted = query.lowercased()
    return !wanted.isEmpty && ["room", "all", "everyone"].contains { $0.hasPrefix(wanted) }
  }

  /// The display name, or the Matrix id when the member has none.
  public var name: String { displayName.flatMap { $0.isEmpty ? nil : $0 } ?? id }
}

public enum RoomDetailsError: Error, Sendable, Equatable {
  case notSignedIn
  case roomNotFound
  case requestFailed
}

extension RoomDetailsRepository {
  /// No changes reported: a repository without live updates.
  public func changes(roomId: String) async -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

/// Reads and changes a room's details. Implemented in MatrixData; no SDK type appears here (ADR 0006).
public protocol RoomDetailsRepository: Sendable {
  func details(roomId: String) async throws(RoomDetailsError) -> RoomDetails
  /// The joined and invited members, by name.
  func members(roomId: String) async throws(RoomDetailsError) -> [RoomMember]
  /// Yields each time the room changes (a member joins, leaves or is removed, the name or the picture changes), so
  /// an open details screen shows it without being reopened. Ends when the caller stops reading it.
  func changes(roomId: String) async -> AsyncStream<Void>
  /// Leaves the room; it disappears from the chat list.
  func leave(roomId: String) async throws(RoomDetailsError)

  /// How the room notifies the user now, and whether that is the account's default.
  func notificationMode(roomId: String) async throws(RoomDetailsError) -> (
    mode: NotificationMode, isDefault: Bool
  )

  /// Sets the room's own mode, or goes back to the account's default with `nil`.
  func setNotificationMode(_ mode: NotificationMode?, roomId: String) async throws(RoomDetailsError)

  /// Renames the room.
  func rename(_ name: String, roomId: String) async throws(RoomDetailsError)
  /// Sets the room's topic; an empty text removes it.
  func setTopic(_ topic: String, roomId: String) async throws(RoomDetailsError)
  /// Invites these Matrix users, each on its own: one that cannot be invited (a server that does not answer, a
  /// banned person) does not stop the others. Returns the ids that were not invited; empty when all were.
  @discardableResult
  func invite(userIds: [String], roomId: String) async throws(RoomDetailsError) -> [String]
  /// Removes (kicks) a member from the room.
  func remove(userId: String, roomId: String) async throws(RoomDetailsError)
  /// Bans a member: removed, and kept out until unbanned.
  func ban(userId: String, roomId: String) async throws(RoomDetailsError)
  /// The people banned from the room.
  func banned(roomId: String) async throws(RoomDetailsError) -> [RoomMember]
  /// Lets a banned person back (they can then be invited or join again).
  func unban(userId: String, roomId: String) async throws(RoomDetailsError)
  /// Gives a member a role.
  func setRole(_ role: RoomMember.Role, userId: String, roomId: String)
    async throws(RoomDetailsError)
  /// Changes who can join.
  func setJoinRule(_ rule: RoomDetails.JoinRule, roomId: String) async throws(RoomDetailsError)
  /// Turns end-to-end encryption on; it cannot be turned off.
  func enableEncryption(roomId: String) async throws(RoomDetailsError)
  /// Uploads a picture and makes it the room's avatar.
  func setAvatar(_ picture: PictureUpload, roomId: String) async throws(RoomDetailsError)
  /// Removes the room's avatar.
  func removeAvatar(roomId: String) async throws(RoomDetailsError)
  /// The group chats the user and `userId` are both in, by name (direct chats left out).
  func roomsInCommon(with userId: String) async -> [RoomInCommon]
  /// The status message `userId` set (Matrix presence `status_msg`), or `nil`.
  func statusMessage(of userId: String) async -> String?
  /// Whether `userId` is online, when they were last active, and their status (`GET /presence/{userId}/status`); `nil`
  /// when the server keeps no presence.
  func presence(of userId: String) async -> Presence?
}

extension RoomDetailsRepository {
  public func roomsInCommon(with userId: String) async -> [RoomInCommon] { [] }
  public func statusMessage(of userId: String) async -> String? { nil }
  public func presence(of userId: String) async -> Presence? { nil }
}

/// What a direct chat's header says about the other person (Matrix presence).
public struct Presence: Sendable, Equatable {
  public let isOnline: Bool
  /// How long ago they were last active, when the server says.
  public let lastActive: TimeInterval?
  public let statusMessage: String?
  public let isAway: Bool

  public init(
    isOnline: Bool, lastActive: TimeInterval? = nil, statusMessage: String? = nil,
    isAway: Bool = false
  ) {
    self.isOnline = isOnline
    self.lastActive = lastActive
    self.statusMessage = statusMessage
    self.isAway = isAway
  }

  public enum Dot: Sendable, Equatable {
    case online, away
  }

  public var dot: Dot? {
    if isOnline { return .online }
    return isAway ? .away : nil
  }

  /// From the presence JSON: `presence`, `currently_active`, `last_active_ago` (ms), `status_msg`.
  public static func from(_ object: [String: Any]) -> Presence {
    let state = object["presence"] as? String
    let active = object["currently_active"] as? Bool ?? false
    let ago = (object["last_active_ago"] as? NSNumber).map { $0.doubleValue / 1000 }
    let status = (object["status_msg"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    let isOnline = state == "online" && (active || (ago ?? .infinity) < 300)
    return Presence(
      isOnline: isOnline, lastActive: ago, statusMessage: status,
      isAway: !isOnline && (state == "unavailable" || state == "online"))
  }

  /// One line under the name: the status when set, else « Online » or « Active 5 min ago »; `nil` when nothing is
  /// known.
  public var line: String? {
    if let statusMessage { return statusMessage }
    if isOnline { return "Online" }
    guard let lastActive else { return nil }
    let minutes = Int(lastActive / 60)
    switch minutes {
    case ..<1: return "Active just now"
    case ..<60: return "Active \(minutes) min ago"
    case ..<(24 * 60): return "Active \(minutes / 60) h ago"
    default:
      let days = minutes / (24 * 60)
      return days == 1 ? "Active yesterday" : "Active \(days) days ago"
    }
  }
}

/// A group chat shared with someone, on their profile.
public struct RoomInCommon: Sendable, Equatable, Identifiable {
  public let id: String
  public let name: String
  public let avatar: MediaReference?

  public init(id: String, name: String, avatar: MediaReference? = nil) {
    self.id = id
    self.name = name
    self.avatar = avatar
  }
}
