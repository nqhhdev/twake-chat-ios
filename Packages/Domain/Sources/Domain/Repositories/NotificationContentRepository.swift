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

/// Fetches and decrypts the event a push is about, for the notification service extension (ADR 0009). Implemented in
/// MatrixData; no SDK type appears here (ADR 0006).
public protocol NotificationContentRepository: Sendable {
  /// The notification's content, or `nil` when the event cannot be fetched or decrypted in time, in which case the
  /// extension keeps the generic text.
  func content(roomId: String, eventId: String) async -> NotificationContent?
}
