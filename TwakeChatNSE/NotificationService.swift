import AppShared
import Domain
import Foundation
import MatrixData
@preconcurrency import UserNotifications

/// The Notification Service Extension (ADR 0009, container "Notification Service Extension"): APNs starts it for each
/// push the gateway sends with only a room id and an event id. It opens the app's session store from the App Group and
/// the shared Keychain group (ADR 0007), asks the SDK to fetch and decrypt the event, and rewrites the notification with
/// the sender and the text. If that fails or time runs out, the generic text from the push stays, never ciphertext.
/// An event that does not notify (an edit, a reaction, a redaction, one the push rules filter out) shows nothing. Nothing here logs: the content is the user's
/// message.
final class NotificationService: UNNotificationServiceExtension, @unchecked Sendable {
  private let lock = NSLock()
  private var deliver: ((UNNotificationContent) -> Void)?
  private var pending: UNMutableNotificationContent?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
      contentHandler(request.content)
      return
    }
    lock.withLock {
      deliver = contentHandler
      pending = content
    }
    let userInfo = request.content.userInfo
    guard let roomId = userInfo["room_id"] as? String, let eventId = userInfo["event_id"] as? String,
      let repository = Self.makeRepository()
    else {
      finish()
      return
    }
    content.threadIdentifier = roomId
    Task {
      switch await repository.content(roomId: roomId, eventId: eventId) {
      case .show(let found):
        lock.withLock {
          pending?.title = found.title
          pending?.subtitle = found.subtitle
          pending?.body = found.body
        }
      case .hide:
        // An empty content has nothing to show, so the system shows no notification for this push.
        lock.withLock { pending = UNMutableNotificationContent() }
      case .generic:
        break
      }
      finish()
    }
  }

  /// The system is about to stop the extension: show what is ready, the generic text if nothing more.
  override func serviceExtensionTimeWillExpire() {
    finish()
  }

  /// Delivers the content once.
  private func finish() {
    let (deliver, content) = lock.withLock {
      defer {
        self.deliver = nil
        self.pending = nil
      }
      return (self.deliver, self.pending)
    }
    if let deliver, let content { deliver(content) }
  }

  /// The SDK on the app's store, in this process, under the lock name "nse" (ADR 0007).
  private static func makeRepository() -> NotificationContentProxy? {
    MatrixPlatform.setUp()
    guard let storeDirectory = AppGroupContainer().sdkStoreDirectory(),
      let accessGroup = Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String
    else { return nil }
    let authentication = MatrixAuthenticationRepository(
      storeDirectory: storeDirectory,
      sessionStore: KeychainSessionStore(service: "app.twake.ios.chat", accessGroup: accessGroup),
      lockHolderName: "nse")
    return NotificationContentProxy(authentication: authentication)
  }
}
