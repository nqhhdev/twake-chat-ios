import Foundation

/// A room of the homeserver's public directory (Flutter `public_rooms`).
public struct PublicRoom: Sendable, Equatable, Identifiable {
  /// How the user gets in.
  public enum Access: Sendable, Equatable {
    /// Anyone joins at once.
    case open
    /// The user asks; a member lets them in (Matrix "knock").
    case request
    /// Only an invitation lets the user in.
    case inviteOnly
  }

  public let id: String
  public let name: String
  public let topic: String?
  public let alias: String?
  public let avatar: MediaReference?
  public let memberCount: Int
  public let access: Access

  public init(
    id: String, name: String, topic: String?, alias: String?, avatar: MediaReference?,
    memberCount: Int, access: Access
  ) {
    self.id = id
    self.name = name
    self.topic = topic
    self.alias = alias
    self.avatar = avatar
    self.memberCount = memberCount
    self.access = access
  }
}

public enum PublicRoomsError: Error, Sendable, Equatable {
  case notSignedIn
  case requestFailed
}

/// The homeserver's room directory: browse and search it, a page at a time, then join a room or ask to join it.
/// Rooms the user is already in or invited to are left out, as the Flutter app does. Implemented in MatrixData
/// (ADR 0006).
public protocol PublicRoomsRepository: Sendable {
  /// Starts browsing, or searching for `term`; the stream gives the rooms found so far and ends with the next search.
  func search(_ term: String?) async throws(PublicRoomsError) -> AsyncStream<[PublicRoom]>
  /// Loads the next page of the current search; returns `true` once the last page is loaded.
  func loadMore() async throws(PublicRoomsError) -> Bool
  /// Joins an open room and returns its id.
  func join(roomId: String) async throws(PublicRoomsError) -> String
  /// Asks to join a room that takes requests.
  func requestToJoin(roomId: String) async throws(PublicRoomsError)
}
