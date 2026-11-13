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

  public init(
    id: String, name: String, topic: String?, alias: String?, isDirect: Bool, isEncrypted: Bool,
    isPublic: Bool,
    joinedMemberCount: Int
  ) {
    self.id = id
    self.name = name
    self.topic = topic
    self.alias = alias
    self.isDirect = isDirect
    self.isEncrypted = isEncrypted
    self.isPublic = isPublic
    self.joinedMemberCount = joinedMemberCount
  }
}

/// One member of a room as the members list shows them.
public struct RoomMember: Sendable, Equatable, Identifiable {
  public enum Membership: Sendable, Equatable {
    case joined
    case invited
  }

  /// The Matrix user id.
  public let id: String
  public let displayName: String?
  public let membership: Membership

  public init(id: String, displayName: String?, membership: Membership) {
    self.id = id
    self.displayName = displayName
    self.membership = membership
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
}
