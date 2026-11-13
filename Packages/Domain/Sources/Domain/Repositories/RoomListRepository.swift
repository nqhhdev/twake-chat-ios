import Foundation

/// What the chat list needs from the data layer: the signed-in user's joined rooms, kept up to date. Implemented in
/// MatrixData; no SDK type appears here (ADR 0006).
public protocol RoomListRepository: Sendable {
  /// Starts sync and returns the joined rooms, ordered as the server's room list orders them (most recent activity
  /// first). The stream yields the whole list again each time it changes, and finishes when `stop()` is called. A
  /// second `start()` finishes the stream of the first.
  func start() async throws(RoomListError) -> AsyncStream<[RoomSummary]>

  /// Stops the updates and sync. Does nothing when not started.
  func stop() async
}
