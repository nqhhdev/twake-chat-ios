import Foundation

/// Where each chat was left, so reopening it shows the same message (issue #138, as the web client does). Kept in
/// memory for the app's run only; nothing is stored on disk.
@MainActor
public final class TimelineScrollMemory {
  /// Where a chat was left.
  public enum Position: Equatable, Sendable {
    /// On the newest message: the chat opens there and follows new messages.
    case bottom
    /// Scrolled up: the message at the top of the screen.
    case message(eventId: String)
  }

  private var positions: [String: Position] = [:]

  public init() {}

  /// Where `roomId` was left, or `nil` when it was not opened in this run.
  public func position(ofRoom roomId: String) -> Position? {
    positions[roomId]
  }

  public func remember(_ position: Position, ofRoom roomId: String) {
    positions[roomId] = position
  }
}
