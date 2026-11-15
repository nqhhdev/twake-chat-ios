import Foundation

/// What the chat list needs from the data layer: the signed-in user's joined rooms, kept up to date. Implemented in
/// MatrixData; no SDK type appears here (ADR 0006).
public protocol RoomListRepository: Sendable {
  /// Starts sync and returns the joined rooms, ordered as the server's room list orders them (most recent activity
  /// first). The stream yields the whole list again each time it changes, and finishes when `stop()` is called. A
  /// second `start()` finishes the stream of the first.
  func start() async throws(RoomListError) -> AsyncStream<[RoomSummary]>

  /// Joins a room the user is invited to.
  func accept(roomId: String) async throws(RoomListError)

  /// Declines an invitation; the room leaves the list.
  func decline(roomId: String) async throws(RoomListError)

  /// Marks the room as unread (`true`), or as read up to its latest message (`false`).
  func setUnread(_ unread: Bool, roomId: String) async throws(RoomListError)

  /// Adds the room to the favourites, or takes it out.
  func setFavourite(_ favourite: Bool, roomId: String) async throws(RoomListError)

  /// Puts the room in low priority (`m.lowpriority` tag), or takes it out.
  func setLowPriority(_ lowPriority: Bool, roomId: String) async throws(RoomListError)

  /// Mutes the room, or goes back to the account's default notifications.
  func setMuted(_ muted: Bool, roomId: String) async throws(RoomListError)

  /// Leaves a joined room; it leaves the list.
  func leave(roomId: String) async throws(RoomListError)

  /// Stops the updates and sync. Does nothing when not started.
  func stop() async
}

extension RoomListRepository {
  /// Repositories that keep no tags cannot set low priority.
  public func setLowPriority(_ lowPriority: Bool, roomId: String) async throws(RoomListError) {
    throw .requestFailed
  }
}
