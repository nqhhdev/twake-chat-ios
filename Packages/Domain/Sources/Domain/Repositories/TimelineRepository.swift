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

  /// Uploads and sends a picture, video, voice message or file; the timeline shows it as sending until it is done.
  func sendAttachment(_ attachment: OutgoingAttachment) async throws(TimelineError)

  /// Tells the room the user is typing, or stopped.
  func setTyping(_ isTyping: Bool) async

  /// The names of the other members typing now, updated as they start and stop. Finishes when `close()` is called.
  func typingMembers() async -> AsyncStream<[String]>

  /// Sends a text message as a reply to the event `eventId`.
  func reply(text: String, to eventId: String) async throws(TimelineError)

  /// Replaces the text of the user's own message `eventId`.
  func edit(eventId: String, text: String) async throws(TimelineError)

  /// Deletes the message `eventId` for everyone.
  func redact(eventId: String) async throws(TimelineError)

  /// Adds the reaction `key` to the message `eventId`, or removes it when the user already sent it.
  func toggleReaction(_ key: String, on eventId: String) async throws(TimelineError)

  /// Pins the message `eventId` to the top of the room for everyone, or unpins it.
  func setPinned(_ pinned: Bool, eventId: String) async throws(TimelineError)

  /// The room's pinned messages, the most recently pinned last. Messages not loaded yet are left out.
  func pinnedMessages() async -> [TimelineMessage]

  /// Sends a copy of the message `eventId` (text, picture, file…) to the room `roomId`, without its reply.
  func forward(eventId: String, to roomId: String) async throws(TimelineError)

  /// The text the user left in the composer, kept by the SDK per room; `nil` when there is none.
  func loadDraft() async -> String?

  /// Keeps the composer's text for the next visit, or clears it when empty.
  func saveDraft(_ text: String) async

  /// Sends again the messages that failed to send (the SDK pauses a room's send queue after a failure).
  func retryFailedSends() async

  /// Reports the message `eventId` to the server's moderators, with an optional reason.
  func report(eventId: String, reason: String?) async throws(TimelineError)

  /// Hides everything from the user `userId` everywhere, as Matrix "ignore" does (the app calls it Block).
  func ignore(userId: String) async throws(TimelineError)

  /// Marks the room as read up to its latest event.
  func markAsRead() async

  /// Stops following the timeline. Safe when not opened.
  func close() async
}
