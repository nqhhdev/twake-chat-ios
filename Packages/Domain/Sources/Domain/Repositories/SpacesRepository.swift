import Foundation

/// A room or a sub-space listed in a space (Flutter `space_home`'s channels).
public struct SpaceChild: Sendable, Equatable, Identifiable {
  public let id: String
  public let name: String
  public let topic: String?
  public let avatar: MediaReference?
  public let memberCount: Int
  /// The user is in it: it opens. Otherwise Join first.
  public let isJoined: Bool
  /// A space inside the space: it opens as a space.
  public let isSpace: Bool
  /// Servers that can find it, for joining.
  public let via: [String]
  /// A Broadcast (`app.twake.chat.page`): it may have a page style.
  public let isBroadcast: Bool

  public init(
    id: String, name: String, topic: String?, avatar: MediaReference?, memberCount: Int,
    isJoined: Bool, isSpace: Bool, via: [String], isBroadcast: Bool = false
  ) {
    self.id = id
    self.name = name
    self.topic = topic
    self.avatar = avatar
    self.memberCount = memberCount
    self.isJoined = isJoined
    self.isSpace = isSpace
    self.via = via
    self.isBroadcast = isBroadcast
  }
}

public enum SpacesError: Error, Sendable, Equatable {
  case notSignedIn
  case requestFailed
}

/// What a space holds, and joining it. Implemented in MatrixData (ADR 0006).
public protocol SpacesRepository: Sendable {
  /// The rooms and sub-spaces of a space, as far as the server lists them.
  func children(of spaceId: String) async throws(SpacesError) -> [SpaceChild]
  /// Joins a room of the space and returns its id.
  func join(_ child: SpaceChild) async throws(SpacesError) -> String
  /// The user may add rooms to the space `spaceId` (their power level lets them edit it).
  func canAddChannel(to spaceId: String) async -> Bool
  /// Creates an encrypted private room named `name` and adds it to the space; returns its id.
  func createChannel(named name: String, in spaceId: String) async throws(SpacesError) -> String
  /// The page style of a space or room (`app.twake.chat.page_style`), or `nil` when it has none or it cannot be read.
  func pageStyle(of roomId: String) async -> PageStyle?
  func createSpace(_ space: NewSpace, picture: PictureUpload?) async throws(SpacesError) -> String
}

extension SpacesRepository {
  public func canAddChannel(to spaceId: String) async -> Bool { false }
  public func createChannel(named name: String, in spaceId: String) async throws(SpacesError)
    -> String
  {
    throw .requestFailed
  }
  public func pageStyle(of roomId: String) async -> PageStyle? { nil }
  public func createSpace(_ space: NewSpace, picture: PictureUpload?) async throws(SpacesError)
    -> String
  {
    throw .requestFailed
  }
}
