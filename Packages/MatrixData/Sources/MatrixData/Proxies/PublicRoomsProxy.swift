import Domain
import Foundation
import MatrixRustSDK

/// `PublicRoomsRepository` on the SDK's `RoomDirectorySearch` (ADR 0006): one search at a time, its results kept from
/// the SDK's list updates and published without the rooms the user is in or invited to. Pages are 20 rooms, as the
/// Flutter app's search asks. Nothing here logs.
public actor PublicRoomsProxy: PublicRoomsRepository {
  /// Rooms a page asks for.
  static let pageSize: UInt32 = 20

  private let clientProxy: @Sendable () async -> ClientProxy?
  private var current:
    (
      search: RoomDirectorySearch, handle: TaskHandle,
      continuation: AsyncStream<[PublicRoom]>.Continuation
    )?

  public init(authentication: MatrixAuthenticationRepository) {
    clientProxy = { await authentication.clientProxy }
  }

  public func search(_ term: String?) async throws(PublicRoomsError) -> AsyncStream<[PublicRoom]> {
    guard let client = await clientProxy()?.client else { throw .notSignedIn }
    current?.handle.cancel()
    current?.continuation.finish()
    current = nil
    let search = client.roomDirectorySearch()
    let (stream, continuation) = AsyncStream<[PublicRoom]>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    let listener = Listener { [weak client] rooms in
      var known: Set<String> = []
      for room in client?.rooms() ?? [] where [.joined, .invited].contains(room.membership()) {
        known.insert(room.id())
      }
      continuation.yield(rooms.filter { !known.contains($0.roomId) }.map(Self.publicRoom))
    }
    let handle = await search.results(listener: listener)
    current = (search, handle, continuation)
    continuation.onTermination = { _ in handle.cancel() }
    do {
      let filter = term?.trimmingCharacters(in: .whitespacesAndNewlines)
      try await search.search(
        filter: filter?.isEmpty == false ? filter : nil, batchSize: Self.pageSize,
        viaServerName: nil)
    } catch {
      handle.cancel()
      continuation.finish()
      current = nil
      throw .requestFailed
    }
    return stream
  }

  public func loadMore() async throws(PublicRoomsError) -> Bool {
    guard let search = current?.search else { return true }
    do {
      if try await search.isAtLastPage() { return true }
      try await search.nextPage()
      return try await search.isAtLastPage()
    } catch {
      throw .requestFailed
    }
  }

  public func join(roomId: String) async throws(PublicRoomsError) -> String {
    guard let client = await clientProxy()?.client else { throw .notSignedIn }
    do { return try await client.joinRoomById(roomId: roomId).id() } catch { throw .requestFailed }
  }

  public func requestToJoin(roomId: String) async throws(PublicRoomsError) {
    guard let client = await clientProxy()?.client else { throw .notSignedIn }
    do {
      _ = try await client.knock(roomIdOrAlias: roomId, reason: nil, serverNames: [])
    } catch {
      throw .requestFailed
    }
  }

  static func publicRoom(_ description: RoomDescription) -> PublicRoom {
    let access: PublicRoom.Access =
      switch description.joinRule {
      case .public, nil: .open
      case .knock, .knockRestricted: .request
      default: .inviteOnly
      }
    return PublicRoom(
      id: description.roomId,
      name: description.name.flatMap { $0.isEmpty ? nil : $0 } ?? description.alias
        ?? description.roomId,
      topic: description.topic.flatMap { $0.isEmpty ? nil : $0 }, alias: description.alias,
      avatar: RoomSummaryMapper.avatar(description.avatarUrl),
      memberCount: Int(clamping: description.joinedMembers), access: access)
  }

  /// Keeps the SDK's list of results and hands each new version on.
  private final class Listener: RoomDirectorySearchEntriesListener, @unchecked Sendable {
    private let lock = NSLock()
    private var rooms: [RoomDescription] = []
    private let onChange: @Sendable ([RoomDescription]) -> Void

    init(onChange: @escaping @Sendable ([RoomDescription]) -> Void) {
      self.onChange = onChange
    }

    func onUpdate(roomEntriesUpdate: [RoomDirectorySearchEntryUpdate]) {
      let snapshot = lock.withLock {
        for update in roomEntriesUpdate { ListDiff(update).apply(to: &rooms) }
        return rooms
      }
      onChange(snapshot)
    }
  }
}

extension ListDiff where Element == RoomDescription {
  /// The SDK directory search update as a `ListDiff`.
  init(_ update: RoomDirectorySearchEntryUpdate) {
    switch update {
    case .append(let values): self = .append(values)
    case .clear: self = .clear
    case .pushFront(let value): self = .pushFront(value)
    case .pushBack(let value): self = .pushBack(value)
    case .popFront: self = .popFront
    case .popBack: self = .popBack
    case .insert(let index, let value): self = .insert(index: Int(index), value)
    case .set(let index, let value): self = .set(index: Int(index), value)
    case .remove(let index): self = .remove(index: Int(index))
    case .truncate(let length): self = .truncate(length: Int(length))
    case .reset(let values): self = .reset(values)
    }
  }
}
