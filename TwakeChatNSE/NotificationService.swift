import AppShared
import CallKit
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
    let registry = AccountRegistry.inAppGroup()
    let accounts = registry?.load() ?? AccountList()
    guard
      let slot = accounts.slot(
        forPush: PushPayload.clientIdentifier(in: userInfo), hash: PusherProxy.clientIdentifier)
    else {
      contentHandler(UNMutableNotificationContent())
      return
    }
    let badge = Self.badge(PushPayload.unreadCount(in: userInfo), slot: slot, accounts: accounts)
    if let badge { content.badge = NSNumber(value: badge) }
    let account = Self.account(accounts, slot: slot)
    if let userId = account.userId { content.userInfo[PushPayload.userIdKey] = userId }
    lock.withLock {
      deliver = contentHandler
      pending = content
    }
    guard let roomId = PushPayload.roomId(in: userInfo),
      let eventId = PushPayload.eventId(in: userInfo),
      let registry, let repository = Self.makeRepository(registry: registry, slot: slot)
    else {
      finish()
      return
    }
    content.threadIdentifier = roomId
    content.categoryIdentifier = PushPayload.messageCategory
    Task {
      switch await repository.content(roomId: roomId, eventId: eventId) {
      case .show(let found):
        let ring = found.ring.map { $0.with(accountUserId: account.userId) }
        let ringing =
          ring.map { $0.isRinging() } == true
          && AccountCallAvailability.inAppGroup()?.isAvailable(for: slot) == true
        if let ring, ringing, await Self.reportRing(ring) {
          lock.withLock { pending = UNMutableNotificationContent() }
          break
        }
        let shown = lock.withLock { () -> UNMutableNotificationContent? in
          guard let pending else { return nil }
          Self.apply(found, label: account.label, to: pending)
          if let ring, ringing {
            pending.userInfo[CallRingPayload.userInfoKey] = ring.payload
          }
          return pending.mutableCopy() as? UNMutableNotificationContent
        }
        if let shown,
          let updated = await CommunicationNotification.content(
            shown,
            intent: CommunicationNotification.intent(
              for: found, roomId: roomId, accountUserId: account.userId))
        {
          lock.withLock { if pending != nil { pending = updated } }
        }
      case .hide:
        let empty = UNMutableNotificationContent()
        if let badge { empty.badge = NSNumber(value: badge) }
        lock.withLock { pending = empty }
      case .generic:
        break
      }
      finish()
    }
  }

  private static func apply(
    _ found: NotificationContent, label: String?, to content: UNMutableNotificationContent
  ) {
    content.title = found.title
    content.subtitle = AccountLabel.subtitle(found.subtitle, account: label)
    content.body = found.body
    content.categoryIdentifier = found.isMessage ? PushPayload.messageCategory : ""
    if let threadId = found.threadId { content.userInfo[PushPayload.threadIdKey] = threadId }
  }

  private static func reportRing(_ ring: CallRing) async -> Bool {
    do {
      try await CXProvider.reportNewIncomingVoIPPushPayload(ring.payload)
      return true
    } catch {
      return false
    }
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

  private static func account(_ accounts: AccountList, slot: AccountSlot) -> (
    userId: String?, label: String?
  ) {
    (accounts.account(slot: slot)?.userId, accounts.notificationLabel(for: slot))
  }

  private static func badge(_ unreadCount: Int?, slot: AccountSlot, accounts: AccountList) -> Int? {
    guard let unreadCount else { return nil }
    guard let badges = AccountBadges.inAppGroup() else { return unreadCount }
    badges.record(unreadCount, for: slot)
    return badges.total(for: accounts, including: slot)
  }

  private static func makeRepository(registry: AccountRegistry, slot: AccountSlot)
    -> NotificationContentProxy?
  {
    MatrixPlatform.setUp()
    guard
      let accessGroup = Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String
    else { return nil }
    let authentication = MatrixAuthenticationRepository(
      storeDirectory: registry.storeDirectory(for: slot),
      sessionStore: KeychainSessionStore(
        service: "app.twake.ios.chat", accessGroup: accessGroup, account: slot.keychainAccount),
      lockHolderName: "nse")
    return NotificationContentProxy(authentication: authentication)
  }
}
