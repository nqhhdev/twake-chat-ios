import Domain
import Foundation
import MatrixRustSDK

/// `ActivityReactionsRepository` on the history the SDK already holds, as the web reads its loaded timelines (D58): each
/// room's live timeline, threads included, is opened from the event cache, its first items are read, and it is closed.
/// Nothing is paginated or asked of the server. Nothing here logs message content (ADR 0009).
public actor ActivityReactionsProxy: ActivityReactionsRepository {
  private let clientProxy: @Sendable () async -> ClientProxy?

  public init(authentication: MatrixAuthenticationRepository) {
    clientProxy = { await authentication.clientProxy }
  }

  /// How long a room's timeline may take to hand its first items; a room with nothing cached may send none.
  static let firstItemsTimeout: Duration = .seconds(2)

  public func reactions(inRooms roomIds: [String]) async -> [ActivityReaction] {
    guard let clientProxy = await clientProxy(), let ownUserId = try? clientProxy.userId else {
      return []
    }
    let client = clientProxy.client
    var found: [ActivityReaction] = []
    for chunk in stride(from: 0, to: roomIds.count, by: 8) {
      await withTaskGroup(of: [ActivityReaction].self) { group in
        for roomId in roomIds[chunk..<min(chunk + 8, roomIds.count)] {
          group.addTask {
            await Self.reactions(roomId: roomId, ownUserId: ownUserId, client: client)
          }
        }
        for await reactions in group { found += reactions }
      }
    }
    return ActivityReactions.newest(found, ownUserId: ownUserId)
  }

  /// The reactions on the user's messages among the room's cached items; none when the room is not joined here.
  private static func reactions(roomId: String, ownUserId: String, client: Client) async
    -> [ActivityReaction]
  {
    guard let room = try? client.getRoom(roomId: roomId), room.membership() == .joined,
      let timeline = try? await room.timelineWithConfiguration(configuration: configuration)
    else { return [] }
    let items = await firstItems(of: timeline)
    let roomName = room.displayName() ?? roomId
    var names: [String: String] = [:]
    var result: [ActivityReaction] = []
    for found in Self.ownReactions(in: items, ownUserId: ownUserId) {
      if names[found.senderId] == nil {
        names[found.senderId] =
          ((try? await room.memberDisplayName(userId: found.senderId)) ?? nil)
          .flatMap { $0.isEmpty ? nil : $0 } ?? found.senderId
      }
      result.append(
        ActivityReaction(
          roomId: roomId, roomName: roomName, eventId: found.eventId, key: found.key,
          senderId: found.senderId, senderName: names[found.senderId] ?? found.senderId,
          reactedAt: found.reactedAt, messageText: found.messageText))
    }
    return result
  }

  /// The main timeline with the threads' replies in it, as the web reads both; no read receipts.
  static var configuration: TimelineConfiguration {
    TimelineConfiguration(
      focus: .live(hideThreadedEvents: false), filter: .all, internalIdPrefix: "activity",
      dateDividerMode: .daily, trackReadReceipts: .disabled, reportUtds: false)
  }

  /// The items the timeline hands first (what the cache holds), or none if it hands nothing in time.
  private static func firstItems(of timeline: Timeline) async -> [MatrixRustSDK.TimelineItem] {
    let (diffs, continuation) = AsyncStream<[TimelineDiff]>.makeStream()
    let handle = await timeline.addListener(listener: DiffListener(continuation))
    defer {
      handle.cancel()
      continuation.finish()
    }
    let first = try? await withTimeout(firstItemsTimeout) {
      var iterator = diffs.makeAsyncIterator()
      return await iterator.next() ?? []
    }
    var items: [MatrixRustSDK.TimelineItem] = []
    for diff in first ?? [] { ListDiff(diff).apply(to: &items) }
    return items
  }

  /// A reaction found on one of the user's messages, before the sender's name is looked up.
  struct Found: Equatable {
    let eventId: String
    let key: String
    let senderId: String
    let reactedAt: Date
    let messageText: String?
  }

  /// The reactions of other people on the user's sent messages among these items.
  static func ownReactions(in items: [MatrixRustSDK.TimelineItem], ownUserId: String) -> [Found] {
    items.compactMap { $0.asEvent() }.flatMap { event in
      ownReactions(on: event, ownUserId: ownUserId)
    }
  }

  static func ownReactions(on event: EventTimelineItem, ownUserId: String) -> [Found] {
    guard event.isOwn, case .eventId(let eventId) = event.eventOrTransactionId,
      case .msgLike(let content) = event.content
    else { return [] }
    let text = TimelineItemMapper.line(of: event.content)
    return content.reactions.flatMap { reaction in
      reaction.senders.filter { $0.senderId != ownUserId }.map { sender in
        Found(
          eventId: eventId, key: reaction.key, senderId: sender.senderId,
          reactedAt: Date(timeIntervalSince1970: TimeInterval(sender.timestamp) / 1000),
          messageText: text)
      }
    }
  }
}
