import Foundation

public enum NotificationActionError: Error, Sendable, Equatable {
  case notSignedIn
  case roomNotFound
  case requestFailed
}

public protocol NotificationActionRepository: Sendable {
  func reply(text: String, roomId: String, threadId: String?, eventId: String)
    async throws(NotificationActionError)

  func markAsRead(roomId: String) async throws(NotificationActionError)
}
