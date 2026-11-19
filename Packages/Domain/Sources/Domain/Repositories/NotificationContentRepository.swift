import Foundation

/// What a push notification shows once its event is fetched and decrypted: who wrote, where, and a short text.
public struct NotificationContent: Sendable, Equatable {
  /// The sender in a direct chat; the room in a group.
  public let title: String
  /// The sender in a group; empty in a direct chat.
  public let subtitle: String
  /// The message text, or a short description of a picture, file or other event.
  public let body: String

  public init(title: String, subtitle: String, body: String) {
    self.title = title
    self.subtitle = subtitle
    self.body = body
  }
}

/// What the notification service extension does with a push once the SDK has looked at its event.
public enum NotificationOutcome: Sendable, Equatable {
  /// Rewrite the notification with this content.
  case show(NotificationContent)
  /// Show nothing: the event does not notify (an edit, a reaction, a redaction, a message that was deleted, or an
  /// event the user's push rules filter out).
  case hide
  /// Keep the push's generic text: the event could not be fetched or decrypted in time (ADR 0009).
  case generic
}

/// Fetches and decrypts the event a push is about, for the notification service extension (ADR 0009). Implemented in
/// MatrixData; no SDK type appears here (ADR 0006).
public protocol NotificationContentRepository: Sendable {
  /// What the notification shows for this event.
  func content(roomId: String, eventId: String) async -> NotificationOutcome
}
