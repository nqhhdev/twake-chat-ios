import Domain
import Foundation
import MatrixRustSDK

/// `TimelineRepository` on the SDK timeline of one room (ADR 0006). It opens the room's timeline on the signed-in
/// client, applies each `TimelineDiff` to its list and publishes the list as Domain items, oldest first. The SDK room,
/// timeline and listener handle are kept by the client while sync runs, so they are released before it
/// (`ClientProxy.keepWhileSyncing`), and released when the screen closes. Nothing here logs: items hold message content (ADR 0009).
public actor TimelineProxy: TimelineRepository {
  /// How many events one "load older" asks for, as the Flutter app's timeline does.
  static let pageSize: UInt16 = 30

  private let roomId: String
  private let clientProxy: @Sendable () async -> ClientProxy?
  private var opened: Opened?

  /// - Parameters:
  ///   - roomId: The room this timeline shows.
  ///   - authentication: Gives the signed-in client.
  public init(roomId: String, authentication: MatrixAuthenticationRepository) {
    self.roomId = roomId
    clientProxy = { await authentication.clientProxy }
  }

  public func open() async throws(TimelineError) -> AsyncStream<[Domain.TimelineItem]> {
    await close()
    guard let client = await clientProxy() else { throw .notSignedIn }
    let timeline: Timeline
    let room: Room
    do {
      _ = try await client.startSync()
      guard let found = try client.client.getRoom(roomId: roomId) else {
        throw TimelineError.roomNotFound
      }
      room = found
      timeline = try await room.timeline()
    } catch let error as TimelineError {
      throw error
    } catch {
      throw .unavailable
    }
    let ownUserId = try? client.userId
    let (items, itemsContinuation) = AsyncStream<[Domain.TimelineItem]>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    let (diffs, diffsContinuation) = AsyncStream<[TimelineDiff]>.makeStream()
    // The listener is called on an SDK thread; diffs are applied in order by one task, which keeps the client alive
    // until it ends.
    let applying = Task { [client] in
      var mapped: [Domain.TimelineItem?] = []
      for await batch in diffs {
        guard !Task.isCancelled else { continue }
        for diff in batch {
          await ListDiff(diff).map { TimelineItemMapper.item($0, ownUserId: ownUserId) }.apply(
            to: &mapped)
        }
        itemsContinuation.yield(mapped.compactMap { $0 })
      }
      itemsContinuation.finish()
      withExtendedLifetime(client) {}
    }
    let handle = await timeline.addListener(listener: DiffListener(diffsContinuation))
    let objects = SyncBoundObjects(entries: handle, objects: [room, timeline])
    let kept = await client.keepWhileSyncing(objects)
    guard kept else {
      handle.cancel()
      diffsContinuation.finish()
      applying.cancel()
      throw .unavailable
    }
    // Loads the room's members so senders show their display names, not their Matrix ids; the timeline updates the
    // items it already published when the profiles arrive.
    Task { [timeline] in await timeline.fetchMembers() }
    opened = Opened(
      client: client, objects: objects, timeline: timeline, diffs: diffsContinuation,
      applying: applying)
    itemsContinuation.onTermination = { _ in diffsContinuation.finish() }
    return items
  }

  public func loadOlder() async throws(TimelineError) -> Bool {
    let timeline = try openedTimeline()
    do {
      return try await timeline.paginateBackwards(numEvents: Self.pageSize)
    } catch {
      throw .requestFailed
    }
  }

  public func send(text: String) async throws(TimelineError) {
    let timeline = try openedTimeline()
    do {
      _ = try await timeline.send(msg: messageEventContentFromMarkdown(md: text))
    } catch {
      throw .requestFailed
    }
  }

  public func reply(text: String, to eventId: String) async throws(TimelineError) {
    let timeline = try openedTimeline()
    do {
      try await timeline.sendReply(msg: messageEventContentFromMarkdown(md: text), eventId: eventId)
    } catch {
      throw .requestFailed
    }
  }

  public func edit(eventId: String, text: String) async throws(TimelineError) {
    let timeline = try openedTimeline()
    do {
      try await timeline.edit(
        eventOrTransactionId: .eventId(eventId: eventId),
        newContent: .roomMessage(content: messageEventContentFromMarkdown(md: text)))
    } catch {
      throw .requestFailed
    }
  }

  public func redact(eventId: String) async throws(TimelineError) {
    let timeline = try openedTimeline()
    do {
      try await timeline.redactEvent(eventOrTransactionId: .eventId(eventId: eventId), reason: nil)
    } catch {
      throw .requestFailed
    }
  }

  public func toggleReaction(_ key: String, on eventId: String) async throws(TimelineError) {
    let timeline = try openedTimeline()
    do {
      _ = try await timeline.toggleReaction(itemId: .eventId(eventId: eventId), key: key)
    } catch {
      throw .requestFailed
    }
  }

  public func markAsRead() async {
    try? await opened?.timeline.markAsRead(receiptType: .read)
  }

  /// Stops following the timeline and releases the SDK room and timeline while the client is alive.
  public func close() async {
    guard let opened else { return }
    self.opened = nil
    opened.diffs.finish()
    opened.applying.cancel()
    await opened.client.release(opened.objects)
  }

  private func openedTimeline() throws(TimelineError) -> Timeline {
    guard let opened else { throw .unavailable }
    return opened.timeline
  }

  private struct Opened {
    let client: ClientProxy
    let objects: SyncBoundObjects
    let timeline: Timeline
    let diffs: AsyncStream<[TimelineDiff]>.Continuation
    let applying: Task<Void, Never>
  }
}

/// Queues the SDK's timeline diffs for `TimelineProxy`, in the order they arrive.
private final class DiffListener: TimelineListener {
  private let diffs: AsyncStream<[TimelineDiff]>.Continuation

  init(_ diffs: AsyncStream<[TimelineDiff]>.Continuation) {
    self.diffs = diffs
  }

  func onUpdate(diff: [TimelineDiff]) {
    diffs.yield(diff)
  }
}
