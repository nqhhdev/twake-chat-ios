import Domain
import Foundation
import MatrixRustSDK

/// `SpacesRepository` on the SDK's space service (ADR 0006): a space's room list, paginated to its end (at most
/// `maxPages` pages), and joining a child through the servers the space lists for it. Nothing here logs.
public actor SpacesProxy: SpacesRepository {
  /// Pages read from the server at most, so a huge space does not keep the screen waiting.
  static let maxPages = 10

  private let clientProxy: @Sendable () async -> ClientProxy?

  public init(authentication: MatrixAuthenticationRepository) {
    clientProxy = { await authentication.clientProxy }
  }

  public func children(of spaceId: String) async throws(SpacesError) -> [SpaceChild] {
    guard let client = await clientProxy()?.client else { throw .notSignedIn }
    do {
      let list = try await client.spaceService().spaceRoomList(spaceId: spaceId)
      for _ in 0..<Self.maxPages {
        if case .idle(let endReached) = list.paginationState(), endReached { break }
        try await list.paginate()
      }
      return list.rooms().filter { $0.roomId != spaceId }.map(Self.child)
    } catch {
      throw .requestFailed
    }
  }

  public func join(_ child: SpaceChild) async throws(SpacesError) -> String {
    guard let client = await clientProxy()?.client else { throw .notSignedIn }
    do {
      return try await client.joinRoomByIdOrAlias(roomIdOrAlias: child.id, serverNames: child.via)
        .id()
    } catch {
      throw .requestFailed
    }
  }

  static func child(_ room: SpaceRoom) -> SpaceChild {
    let isSpace = if case .space = room.roomType { true } else { false }
    return SpaceChild(
      id: room.roomId,
      name: room.displayName.isEmpty ? (room.canonicalAlias ?? room.roomId) : room.displayName,
      topic: room.topic.flatMap { $0.isEmpty ? nil : $0 },
      avatar: RoomSummaryMapper.avatar(room.avatarUrl),
      memberCount: Int(clamping: room.numJoinedMembers), isJoined: room.state == .joined,
      isSpace: isSpace, via: room.via)
  }
}
