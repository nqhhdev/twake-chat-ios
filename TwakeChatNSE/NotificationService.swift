import AppShared
import Domain
import Foundation
import MatrixData
@preconcurrency import UserNotifications

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
    let userInfo = request.content.userInfo
    let unreadCount = PushPayload.unreadCount(in: userInfo)
    if let unreadCount { content.badge = NSNumber(value: unreadCount) }
    lock.withLock {
      deliver = contentHandler
      pending = content
    }
    guard let roomId = PushPayload.roomId(in: userInfo),
      let eventId = PushPayload.eventId(in: userInfo),
      let repository = Self.makeRepository()
    else {
      finish()
      return
    }
    content.threadIdentifier = roomId
    content.categoryIdentifier = PushPayload.messageCategory
    Task {
      switch await repository.content(roomId: roomId, eventId: eventId) {
      case .show(let found):
        let shown = lock.withLock { () -> UNMutableNotificationContent? in
          guard let pending else { return nil }
          Self.apply(found, to: pending)
          return pending.mutableCopy() as? UNMutableNotificationContent
        }
        if let shown,
          let updated = await CommunicationNotification.content(
            shown, intent: CommunicationNotification.intent(for: found, roomId: roomId))
        {
          lock.withLock { if pending != nil { pending = updated } }
        }
      case .hide:
        let empty = UNMutableNotificationContent()
        if let unreadCount { empty.badge = NSNumber(value: unreadCount) }
        lock.withLock { pending = empty }
      case .generic:
        break
      }
      finish()
    }
  }

  private static func apply(_ found: NotificationContent, to content: UNMutableNotificationContent)
  {
    content.title = found.title
    content.subtitle = found.subtitle
    content.body = found.body
    content.categoryIdentifier = found.isMessage ? PushPayload.messageCategory : ""
    if let threadId = found.threadId { content.userInfo[PushPayload.threadIdKey] = threadId }
  }

  override func serviceExtensionTimeWillExpire() {
    finish()
  }

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
