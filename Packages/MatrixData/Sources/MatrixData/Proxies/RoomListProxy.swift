import Domain
import Foundation
import MatrixRustSDK

/// `RoomListRepository` on the SDK room list service (ADR 0006). It starts sync on the signed-in client, subscribes to
/// all rooms with the dynamic adapters filtered to joined rooms, applies each `RoomListEntriesUpdate` to its list and
/// publishes the list as Domain `RoomSummary` values, in the SDK's order (most recent activity first). Only the rooms an
/// update carries are mapped again. Nothing here logs: the summaries hold message content (ADR 0009).
public actor RoomListProxy: RoomListRepository {
  /// One page large enough for the first version's room list; paging further is not part of this card.
  static let pageSize: UInt32 = 200

  let clientProxy: @Sendable () async -> ClientProxy?
  private var subscription: Subscription?

  /// - Parameter authentication: Gives the signed-in client; the room list starts only after login or restore.
  public init(authentication: MatrixAuthenticationRepository) {
    clientProxy = { await authentication.clientProxy }
  }

  public func start() async throws(Domain.RoomListError) -> AsyncStream<[RoomSummary]> {
    await stop()
    guard let client = await clientProxy() else { throw .notSignedIn }
    let roomList: RoomList
    let service: RoomListService
    do {
      service = try await client.startSync()
      roomList = try await service.allRooms()
    } catch {
      throw .syncUnavailable
    }
    let (rooms, roomsContinuation) = AsyncStream<[RoomSummary]>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    let (updates, updatesContinuation) = AsyncStream<RoomListEvent>.makeStream()
    // The listeners are called on SDK threads and mapping awaits each room's latest event, so updates and typing are
    // queued and applied in order by one task. The task keeps the client alive until it ends, so no SDK room it holds
    // outlives the client; it cancels the typing subscriptions before it ends.
    let applying = Task { [client, service] in
      var summaries: [RoomSummary] = []
      var askedPreviews: Set<String> = []
      var typing = RoomListTyping(client: client, events: updatesContinuation)
      let spaceService = await client.client.spaceService()
      let spaceHandle = await spaceService.subscribeToSpaceFilters(
        listener: SpaceFiltersListener(updatesContinuation))
      updatesContinuation.yield(.spaces)
      var spaceTree: [String: [String]] = [:]
      for await event in updates {
        guard !Task.isCancelled else { continue }
        switch event {
        case .entries(let batch):
          for update in batch {
            await ListDiff(update).map(RoomSummaryMapper.summary(for:)).apply(to: &summaries)
          }
          typing.follow(summaries)
          // The list syncs one event per room. When that event is nothing a row can show (a reaction, an edit, a
          // room event), the row stayed blank until the chat was opened. A room subscription syncs more of its
          // timeline, from which the SDK finds and stores the latest message (Element X subscribes to the rooms
          // on screen for the same reason).
          let missing = Self.roomsMissingPreview(in: summaries, alreadyAsked: askedPreviews)
          if !missing.isEmpty {
            askedPreviews.formUnion(missing)
            try? await service.subscribeToRooms(roomIds: missing)
          }
        case .typing(let roomId, let names):
          typing.names[roomId] = names
        case .spaces:
          spaceTree = SpaceGraph.descendants(
            await spaceService.spaceFilters().map {
              SpaceNode(id: $0.spaceRoom.roomId, children: $0.descendants)
            })
        }
        roomsContinuation.yield(Self.withSpaces(spaceTree, typing.applied(to: summaries)))
      }
      spaceHandle.cancel()
      typing.stopAll()
      roomsContinuation.finish()
      withExtendedLifetime(client) {}
    }
    let result = roomList.entriesWithDynamicAdapters(
      pageSize: Self.pageSize, listener: EntriesListener(updatesContinuation))
    let controller = result.controller()
    // The dynamic adapters publish nothing until a filter is set.
    // Joined rooms and invitations, as the Flutter chat list shows them.
    _ = controller.setFilter(kind: .nonLeft)
    let entries = result.entriesStream()
    // The client keeps the SDK list, controller and handle and releases them when sync stops, on logout before the
    // client signs out: freed after the client, they abort the process.
    // `result` is kept too, as Element X keeps it: it owns the entries task and the list it borrows.
    let objects = SyncBoundObjects(entries: entries, objects: [roomList, controller, result])
    let kept = await client.keepWhileSyncing(objects)
    guard kept else {
      await objects.cancelEntries()
      updatesContinuation.finish()
      applying.cancel()
      throw .syncUnavailable
    }
    subscription = Subscription(
      client: client, kept: objects.id, updates: updatesContinuation, applying: applying)
    roomsContinuation.onTermination = { _ in updatesContinuation.finish() }
    return rooms
  }

  static func withSpaces(_ tree: [String: [String]], _ rooms: [RoomSummary]) -> [RoomSummary] {
    rooms.map { room in
      guard room.isSpace else { return room }
      var room = room
      room.spaceDescendantIds = tree[room.id] ?? []
      return room
    }
  }

  /// The most rooms asked for a preview in one pass and over the life of a list, so an account full of empty rooms
  /// does not subscribe to all of them.
  static let previewBatch = 20
  static let previewLimit = 200

  /// The joined chats whose row has no message to show and that were not asked for yet, in list order.
  static func roomsMissingPreview(in rooms: [RoomSummary], alreadyAsked: Set<String>) -> [String] {
    let room = max(0, min(previewBatch, previewLimit - alreadyAsked.count))
    return Array(
      rooms.lazy
        .filter { !$0.isInvite && !$0.isArchived && !$0.isSpace }
        .filter { $0.lastMessageText == nil && $0.lastMessageKind == nil }
        .map(\.id)
        .filter { !alreadyAsked.contains($0) }
        .prefix(room))
  }

  public func accept(roomId: String) async throws(Domain.RoomListError) {
    guard let room = try? await clientProxy()?.client.getRoom(roomId: roomId) else {
      throw .requestFailed
    }
    do { try await room.join() } catch { throw .requestFailed }
  }

  public func setUnread(_ unread: Bool, roomId: String) async throws(Domain.RoomListError) {
    let room = try await room(roomId)
    do {
      if unread {
        try await room.setUnreadFlag(newValue: true)
      } else {
        try await room.markAsRead(receiptType: .read)
        try await room.setUnreadFlag(newValue: false)
      }
    } catch {
      throw .requestFailed
    }
  }

  public func setFavourite(_ favourite: Bool, roomId: String) async throws(Domain.RoomListError) {
    let room = try await room(roomId)
    do { try await room.setIsFavourite(isFavourite: favourite, tagOrder: nil) } catch {
      throw .requestFailed
    }
  }

  public func setLowPriority(_ lowPriority: Bool, roomId: String) async throws(Domain.RoomListError)
  {
    let room = try await room(roomId)
    do { try await room.setIsLowPriority(isLowPriority: lowPriority, tagOrder: nil) } catch {
      DebugLog.failure("setIsLowPriority", error)
      throw .requestFailed
    }
  }

  public func setMuted(_ muted: Bool, roomId: String) async throws(Domain.RoomListError) {
    guard let client = await clientProxy()?.client else { throw .requestFailed }
    let settings = await client.getNotificationSettings()
    do {
      if muted {
        try await settings.setRoomNotificationMode(roomId: roomId, mode: .mute)
      } else {
        try await settings.restoreDefaultRoomNotificationMode(roomId: roomId)
      }
    } catch {
      throw .requestFailed
    }
  }

  public func leave(roomId: String) async throws(Domain.RoomListError) {
    let room = try await room(roomId)
    let info = try? await room.roomInfo()
    do { try await room.leave() } catch { throw .requestFailed }
    guard let client = await clientProxy()?.client else { return }
    await ArchiveAccountData.archive(room, info: info, client: client)
  }

  /// Adds the room to the account data archive, or with `nil` drops it.
  func updateArchive(roomId: String, with entry: ArchivedRoomEntry?) async {
    guard let client = await clientProxy()?.client else { return }
    await ArchiveAccountData.update(client: client, roomId: roomId, with: entry)
  }

  private func room(_ roomId: String) async throws(Domain.RoomListError) -> Room {
    guard let room = try? await clientProxy()?.client.getRoom(roomId: roomId) else {
      throw .requestFailed
    }
    return room
  }

  public func decline(roomId: String) async throws(Domain.RoomListError) {
    guard let room = try? await clientProxy()?.client.getRoom(roomId: roomId) else {
      throw .requestFailed
    }
    do { try await room.leave() } catch { throw .requestFailed }
  }

  /// Stops following the room list and releases the SDK list. Sync keeps running: a chat opened over the chat list
  /// lives on it, and only sign-out stops it. Safe after logout and when not started.
  public func stop() async {
    guard let subscription else { return }
    self.subscription = nil
    subscription.updates.finish()
    subscription.applying.cancel()
    await subscription.client.release(subscription.kept)
  }

  /// What a started room list holds; the SDK list, its controller and the entries `TaskHandle` are kept by the client
  /// while sync runs (`ClientProxy.keepWhileSyncing`). Only their id is held here: a room list freed after its client
  /// aborts the process, and `stop()` may come after logout.
  private struct Subscription {
    let client: ClientProxy
    let kept: UUID
    let updates: AsyncStream<RoomListEvent>.Continuation
    let applying: Task<Void, Never>
  }
}

/// What the room list applies, in the order it arrives: the SDK's list updates and who types in a room.
enum RoomListEvent {
  case entries([RoomListEntriesUpdate])
  case typing(roomId: String, names: [String])
  case spaces
}

/// Who types in each joined room of the list, for its row (Flutter `chat_list_item_title.dart`, web `RoomList.tsx`).
/// The room list's sliding sync carries typing for every room in the list. One subscription per joined room; a room
/// that leaves the list is dropped. Names are the members' display names, or their ids.
struct RoomListTyping {
  let client: ClientProxy
  let events: AsyncStream<RoomListEvent>.Continuation
  private var handles: [String: TaskHandle] = [:]
  /// The people typing in each room, other than the user.
  var names: [String: [String]] = [:]

  init(client: ClientProxy, events: AsyncStream<RoomListEvent>.Continuation) {
    self.client = client
    self.events = events
  }

  /// Subscribes to typing in the joined rooms of `rooms` not followed yet, and stops following the others.
  mutating func follow(_ rooms: [RoomSummary]) {
    let followed = Set(
      rooms.filter { !$0.isSpace && !$0.isInvite && !$0.isArchived }.map(\.id))
    for id in handles.keys where !followed.contains(id) {
      handles.removeValue(forKey: id)?.cancel()
      names[id] = nil
    }
    let ownUserId = try? client.userId
    for id in followed where handles[id] == nil {
      guard let room = try? client.client.getRoom(roomId: id) else { continue }
      let events = events
      handles[id] = room.subscribeToTypingNotifications(
        listener: TypingListener { userIds in
          Task {
            var result: [String] = []
            for userId in userIds where userId != ownUserId {
              let name = (try? await room.memberDisplayName(userId: userId)) ?? nil
              result.append(name.flatMap { $0.isEmpty ? nil : $0 } ?? userId)
            }
            events.yield(.typing(roomId: id, names: result))
          }
        })
    }
  }

  /// `rooms` with who types in each.
  func applied(to rooms: [RoomSummary]) -> [RoomSummary] {
    rooms.map { room in
      var room = room
      room.typingNames = names[room.id] ?? []
      return room
    }
  }

  mutating func stopAll() {
    for handle in handles.values { handle.cancel() }
    handles = [:]
    names = [:]
  }
}

private final class SpaceFiltersListener: SpaceServiceSpaceFiltersListener {
  private let updates: AsyncStream<RoomListEvent>.Continuation

  init(_ updates: AsyncStream<RoomListEvent>.Continuation) {
    self.updates = updates
  }

  func onUpdate(filterUpdates: [SpaceFilterUpdate]) {
    updates.yield(.spaces)
  }
}

/// Queues the SDK's room list updates for `RoomListProxy`, in the order they arrive.
private final class EntriesListener: RoomListEntriesListener {
  private let updates: AsyncStream<RoomListEvent>.Continuation

  init(_ updates: AsyncStream<RoomListEvent>.Continuation) {
    self.updates = updates
  }

  func onUpdate(roomEntriesUpdate: [RoomListEntriesUpdate]) {
    updates.yield(.entries(roomEntriesUpdate))
  }
}

/// The web's archive in the account data (`app.twake.chat.archived_rooms`), kept by every way of leaving a chat.
enum ArchiveAccountData {
  /// Records a room just left, so it shows as archived on every device.
  static func archive(_ room: Room, info: RoomInfo?, client: Client) async {
    await update(
      client: client, roomId: room.id(),
      with: ArchivedRoomEntry(
        roomId: room.id(), name: room.displayName() ?? room.id(), isDirect: info?.isDirect ?? false,
        leftAt: Int64(Date.now.timeIntervalSince1970 * 1000), avatarURL: info?.avatarUrl))
  }

  /// Adds the room, or with `nil` drops it. A failure leaves the archive as it was.
  static func update(client: Client, roomId: String, with entry: ArchivedRoomEntry?) async {
    let current = try? await client.accountData(eventType: RoomArchive.accountDataType)
    guard
      let data = RoomArchive.json(
        updating: current.flatMap { $0 }.map { Data($0.utf8) }, roomId: roomId, with: entry),
      let content = String(data: data, encoding: .utf8)
    else { return }
    do {
      try await client.setAccountData(eventType: RoomArchive.accountDataType, content: content)
    } catch {
      DebugLog.failure("updateArchive", error)
    }
  }
}
