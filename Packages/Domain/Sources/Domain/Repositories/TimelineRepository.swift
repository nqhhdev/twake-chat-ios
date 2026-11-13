import Foundation

/// What the room screen needs from the data layer for one room: its timeline, kept up to date, and the actions on it.
/// Implemented in MatrixData; no SDK type appears here (ADR 0006). One instance serves one room.
public protocol TimelineRepository: Sendable {
  /// Opens the room's timeline and returns its items, oldest first. The stream yields the whole list again each time
  /// it changes and finishes when `close()` is called.
  func open() async throws(TimelineError) -> AsyncStream<[TimelineItem]>

  /// Loads older items. Returns `true` when the start of the room has been reached.
  func loadOlder() async throws(TimelineError) -> Bool

  /// Sends a text message, written in Markdown as the Flutter app's composer sends it.
  func send(text: String) async throws(TimelineError)

  /// Sends a text message as a reply to the event `eventId`.
  func reply(text: String, to eventId: String) async throws(TimelineError)

  /// Replaces the text of the user's own message `eventId`.
  func edit(eventId: String, text: String) async throws(TimelineError)

  /// Deletes the message `eventId` for everyone.
  func redact(eventId: String) async throws(TimelineError)

  /// Adds the reaction `key` to the message `eventId`, or removes it when the user already sent it.
  func toggleReaction(_ key: String, on eventId: String) async throws(TimelineError)

  /// Marks the room as read up to its latest event.
  func markAsRead() async

  /// Stops following the timeline. Safe when not opened.
  func close() async
}
