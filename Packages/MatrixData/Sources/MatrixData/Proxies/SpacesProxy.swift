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
    let isBroadcast =
      if case .custom(let value) = room.roomType { value == BroadcastDraft.roomType } else { false }
    return SpaceChild(
      id: room.roomId,
      name: room.displayName.isEmpty ? (room.canonicalAlias ?? room.roomId) : room.displayName,
      topic: room.topic.flatMap { $0.isEmpty ? nil : $0 },
      avatar: RoomSummaryMapper.avatar(room.avatarUrl),
      memberCount: Int(clamping: room.numJoinedMembers), isJoined: room.state == .joined,
      isSpace: isSpace, via: room.via, isBroadcast: isBroadcast)
  }

  /// The state the web writes, read from the server: the pinned SDK gives no custom room state. A room the user is not
  /// in usually refuses it, and gets no style.
  public func pageStyle(of roomId: String) async -> PageStyle? {
    guard let client = await clientProxy()?.client,
      let request = ClientServerRequest.make(
        client: client,
        path: "rooms/\(ClientServerRequest.encode(roomId))/state/\(PageStyle.stateEventType)/"),
      let content = await ClientServerRequest.object(request)
    else { return nil }
    return PageStyle(content: content) { RoomSummaryMapper.avatar($0) }
  }

  public func canAddChannel(to spaceId: String) async -> Bool {
    guard let client = await clientProxy()?.client else { return false }
    return await client.spaceService().editableSpaces().contains { $0.roomId == spaceId }
  }

  public func createChannel(named name: String, in spaceId: String) async throws(SpacesError)
    -> String
  {
    guard let client = await clientProxy()?.client else { throw .notSignedIn }
    do {
      let roomId = try await client.createRoom(
        request: CreateRoomParameters(
          name: name.trimmingCharacters(in: .whitespacesAndNewlines), isEncrypted: true,
          isDirect: false, visibility: .private, preset: .privateChat))
      try await client.spaceService().addChildToSpace(childId: roomId, spaceId: spaceId)
      return roomId
    } catch {
      DebugLog.failure("createChannel", error)
      throw .requestFailed
    }
  }

  public func createSpace(_ space: NewSpace, picture: PictureUpload?) async throws(SpacesError)
    -> String
  {
    guard let client = await clientProxy()?.client else { throw .notSignedIn }
    var avatarURL: String?
    if let picture {
      avatarURL = try? await client.uploadMedia(
        mimeType: picture.mimeType, data: picture.data, progressWatcher: nil)
    }
    let ownServer = (try? client.userId()).flatMap { id in
      id.firstIndex(of: ":").map { String(id[id.index(after: $0)...]) }
    }
    guard
      let request = ClientServerRequest.make(
        client: client, path: "createRoom", method: "POST",
        json: space.createRoomBody(ownServer: ownServer, avatarURL: avatarURL)),
      let (status, data) = await ClientServerRequest.answer(request), status == 200,
      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let roomId = object["room_id"] as? String
    else { throw .requestFailed }
    if let parentId = space.parentId {
      guard
        let child = ClientServerRequest.make(
          client: client,
          path: "rooms/\(ClientServerRequest.encode(parentId))/state/m.space.child/"
            + ClientServerRequest.encode(roomId), method: "PUT",
          json: NewSpace.childContent(childId: roomId, ownServer: ownServer)),
        await ClientServerRequest.succeeds(child)
      else { throw .requestFailed }
    }
    return roomId
  }
}
