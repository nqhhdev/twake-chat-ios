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

  private let clientProxy: @Sendable () async -> ClientProxy?
  private var subscription: Subscription?

  /// - Parameter authentication: Gives the signed-in client; the room list starts only after login or restore.
  public init(authentication: MatrixAuthenticationRepository) {
    clientProxy = { await authentication.clientProxy }
  }

  public func start() async throws(Domain.RoomListError) -> AsyncStream<[RoomSummary]> {
    await stop()
    guard let client = await clientProxy() else { throw .notSignedIn }
    let roomList: RoomList
    do {
      roomList = try await client.startSync().allRooms()
    } catch {
      throw .syncUnavailable
    }
    let (rooms, roomsContinuation) = AsyncStream<[RoomSummary]>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    let (updates, updatesContinuation) = AsyncStream<[RoomListEntriesUpdate]>.makeStream()
    // The listener is called on an SDK thread and mapping awaits each room's latest event, so updates are queued and
    // applied in order by one task. The task keeps the client alive until it ends, so no SDK room it holds outlives the
    // client.
    let applying = Task { [client] in
      var summaries: [RoomSummary] = []
      for await batch in updates {
        guard !Task.isCancelled else { continue }
        for update in batch {
          await ListDiff(update).map(RoomSummaryMapper.summary(for:)).apply(to: &summaries)
        }
        roomsContinuation.yield(summaries)
      }
      roomsContinuation.finish()
      withExtendedLifetime(client) {}
    }
    let result = roomList.entriesWithDynamicAdapters(
      pageSize: Self.pageSize, listener: EntriesListener(updatesContinuation))
    let controller = result.controller()
    // The dynamic adapters publish nothing until a filter is set.
    _ = controller.setFilter(kind: .joined)
    let entries = result.entriesStream()
    // The client keeps the SDK list, controller and handle and releases them when sync stops, on logout before the
    // client signs out: freed after the client, they abort the process.
    let kept = await client.keepWhileSyncing(
      SyncBoundObjects(entries: entries, objects: [roomList, controller]))
    guard kept else {
      entries.cancel()
      updatesContinuation.finish()
      applying.cancel()
      throw .syncUnavailable
    }
    subscription = Subscription(client: client, updates: updatesContinuation, applying: applying)
    roomsContinuation.onTermination = { _ in updatesContinuation.finish() }
    return rooms
  }

  /// Stops following the room list and stops sync, which releases the SDK list. Safe after logout and when not started.
  public func stop() async {
    guard let subscription else { return }
    self.subscription = nil
    subscription.updates.finish()
    subscription.applying.cancel()
    await subscription.client.stopSync()
  }

  /// What a started room list holds; the SDK list, its controller and the entries `TaskHandle` are kept by the client
  /// while sync runs (`ClientProxy.keepWhileSyncing`).
  private struct Subscription {
    let client: ClientProxy
    let updates: AsyncStream<[RoomListEntriesUpdate]>.Continuation
    let applying: Task<Void, Never>
  }
}

/// Queues the SDK's room list updates for `RoomListProxy`, in the order they arrive.
private final class EntriesListener: RoomListEntriesListener {
  private let updates: AsyncStream<[RoomListEntriesUpdate]>.Continuation

  init(_ updates: AsyncStream<[RoomListEntriesUpdate]>.Continuation) {
    self.updates = updates
  }

  func onUpdate(roomEntriesUpdate: [RoomListEntriesUpdate]) {
    updates.yield(roomEntriesUpdate)
  }
}
