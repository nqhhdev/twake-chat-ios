import Domain
import Foundation
import MatrixRustSDK

/// `RoomLinkRepository` on the SDK client (ADR 0006): an alias resolves to its room id; a room the user joined or is
/// invited to opens; any other shows the server's preview (name, topic, members, join rule), as the Flutter
/// `PublicRoomPreviewSheet` does. Nothing here logs: room names and addresses are the user's.
public actor RoomLinkProxy: RoomLinkRepository {
  private let clientProxy: @Sendable () async -> ClientProxy?

  public init(authentication: MatrixAuthenticationRepository) {
    clientProxy = { await authentication.clientProxy }
  }

  public func target(of idOrAlias: String, via: [String]) async throws(RoomLinkError)
    -> RoomLinkTarget
  {
    guard let client = await clientProxy()?.client else { throw .notSignedIn }
    var roomId: String? = idOrAlias.hasPrefix("!") ? idOrAlias : nil
    var servers = via
    if roomId == nil {
      let resolved = try? await client.resolveRoomAlias(roomAlias: idOrAlias)
      roomId = resolved?.roomId
      servers += resolved?.servers ?? []
    }
    if let roomId, let room = try? client.getRoom(roomId: roomId),
      [.joined, .invited].contains(room.membership())
    {
      return .member(roomId: roomId)
    }
    let preview: RoomPreview
    do {
      if let roomId {
        preview = try await client.getRoomPreviewFromRoomId(roomId: roomId, viaServers: servers)
      } else {
        preview = try await client.getRoomPreviewFromRoomAlias(roomAlias: idOrAlias)
      }
    } catch {
      throw .notFound
    }
    let info = preview.info()
    if [.joined, .invited].contains(info.membership) { return .member(roomId: info.roomId) }
    return .preview(
      RoomLinkPreview(
        idOrAlias: roomId ?? idOrAlias, name: info.name.flatMap { $0.isEmpty ? nil : $0 },
        topic: info.topic.flatMap { $0.isEmpty ? nil : $0 },
        memberCount: Int(clamping: info.numJoinedMembers),
        avatar: RoomSummaryMapper.avatar(info.avatarUrl), isPublic: Self.isPublic(info.joinRule)))
  }

  public func join(_ idOrAlias: String, via: [String]) async throws(RoomLinkError) -> String {
    guard let client = await clientProxy()?.client else { throw .notSignedIn }
    do {
      return try await client.joinRoomByIdOrAlias(roomIdOrAlias: idOrAlias, serverNames: via).id()
    } catch {
      throw .requestFailed
    }
  }

  static func isPublic(_ rule: JoinRule?) -> Bool {
    if case .public = rule { true } else { false }
  }
}
