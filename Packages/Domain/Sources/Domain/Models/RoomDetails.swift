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
    canEnableEncryption: Bool = false, canBan: Bool = false
  ) {
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

  /// The display name, or the Matrix id when the member has none.
  public var name: String { displayName.flatMap { $0.isEmpty ? nil : $0 } ?? id }
}

public enum RoomDetailsError: Error, Sendable, Equatable {
  case notSignedIn
  case roomNotFound
  case requestFailed
}

/// Reads and changes a room's details. Implemented in MatrixData; no SDK type appears here (ADR 0006).
public protocol RoomDetailsRepository: Sendable {
  func details(roomId: String) async throws(RoomDetailsError) -> RoomDetails
  /// The joined and invited members, by name.
  func members(roomId: String) async throws(RoomDetailsError) -> [RoomMember]
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
  /// Invites these Matrix users; the first failure stops and throws.
  func invite(userIds: [String], roomId: String) async throws(RoomDetailsError)
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
}
