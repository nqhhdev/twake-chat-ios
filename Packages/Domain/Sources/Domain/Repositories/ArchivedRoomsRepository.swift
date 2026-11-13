import Foundation

/// The chats the user left (Flutter `archive`): leaving a chat archives it. Each can be joined again, which works
/// when the chat lets the user back in, or deleted for good (Matrix "forget"). Implemented in MatrixData (ADR 0006).
public protocol ArchivedRoomsRepository: Sendable {
  /// The chats the user left that this device knows of, the most recent first.
  func archivedRooms() async throws(RoomListError) -> [RoomSummary]
  /// Joins a left chat again.
  func rejoin(roomId: String) async throws(RoomListError)
  /// Deletes a left chat for good: it leaves the archive and its history is no longer kept.
  func forget(roomId: String) async throws(RoomListError)
}
