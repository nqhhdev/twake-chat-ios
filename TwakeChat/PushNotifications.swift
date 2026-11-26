import AppShared
import Domain
import Observation
import SwiftUI
import UIKit
import UserNotifications

@MainActor @Observable
final class PushCenter {
  var pendingRoomId: String?
  var pendingRoomName: String?
  var pendingThreadId: String?
  var pendingDraftUserId: String?
  @ObservationIgnored var openRoomId: String? {
    didSet { if let openRoomId { clearNotifications(roomId: openRoomId) } }
  }
  @ObservationIgnored private var didRegister = false
  private(set) var isAllowed: Bool?

  @ObservationIgnored private let repository: (any PushRepository)?
  @ObservationIgnored private let actions: (any NotificationActionRepository)?
  @ObservationIgnored var startSession: (@MainActor () async -> Void)?
  @ObservationIgnored private let replyFailed: @MainActor (NotificationAction) async -> Void
  @ObservationIgnored private let requestAuthorization: @MainActor () async -> Bool
  @ObservationIgnored private let registerForRemoteNotifications: @MainActor () -> Void

  init(
    repository: (any PushRepository)?,
    actions: (any NotificationActionRepository)? = nil,
    replyFailed: @escaping @MainActor (NotificationAction) async -> Void = {
      await NotificationAction.postReplyFailure($0)
    },
    requestAuthorization: @escaping @MainActor () async -> Bool = {
      (try? await UNUserNotificationCenter.current().requestAuthorization(options: [
        .alert, .badge, .sound,
      ])) ?? false
    },
    registerForRemoteNotifications: @escaping @MainActor () -> Void = {
      UIApplication.shared.registerForRemoteNotifications()
    }
  ) {
    self.repository = repository
    self.actions = actions
    self.replyFailed = replyFailed
    self.requestAuthorization = requestAuthorization
    self.registerForRemoteNotifications = registerForRemoteNotifications
  }

  func start() async {
    guard repository != nil else { return }
    let allowed = await requestAuthorization()
    isAllowed = allowed
    if allowed {
      didRegister = true
      registerForRemoteNotifications()
    }
  }

  func refreshToken() async {
    guard repository != nil, didRegister else { return }
    registerForRemoteNotifications()
  }

  func clearNotifications(roomId: String) {
    Task {
      let center = UNUserNotificationCenter.current()
      let ids = await center.deliveredNotifications().filter {
        $0.request.content.threadIdentifier == roomId
          || $0.request.content.userInfo["room_id"] as? String == roomId
      }.map(\.request.identifier)
      if !ids.isEmpty { center.removeDeliveredNotifications(withIdentifiers: ids) }
    }
  }

  func showsBanner(forRoom roomId: String?) -> Bool {
    roomId == nil || roomId != openRoomId
  }

  func didReceive(deviceToken: Data) async {
    try? await repository?.register(
      deviceToken: deviceToken, isProduction: ApnsEnvironment.isProduction())
  }

  func stop() async {
    await repository?.unregister()
  }

  func handle(_ action: NotificationAction) async {
    switch action.kind {
    case .open:
      pendingThreadId = action.threadId
      if !action.title.isEmpty { pendingRoomName = action.title }
      pendingRoomId = action.roomId
    case .reply(let text):
      await startSession?()
      do {
        guard let actions else { throw NotificationActionError.notSignedIn }
        try await actions.reply(
          text: text, roomId: action.roomId, threadId: action.threadId,
          eventId: action.eventId ?? "")
        clearNotifications(roomId: action.roomId)
      } catch {
        await replyFailed(action)
      }
    case .markAsRead:
      await startSession?()
      do {
        try await actions?.markAsRead(roomId: action.roomId)
        clearNotifications(roomId: action.roomId)
      } catch {}
    }
  }
}

struct NotificationAction: Sendable, Equatable {
  enum Kind: Sendable, Equatable {
    case open
    case reply(String)
    case markAsRead
  }

  let kind: Kind
  let roomId: String
  let eventId: String?
  let threadId: String?
  let title: String
  let userId: String?

  init?(
    actionIdentifier: String, userText: String?, userInfo: [AnyHashable: Any], title: String
  ) {
    guard let roomId = PushPayload.roomId(in: userInfo) else { return nil }
    switch actionIdentifier {
    case PushPayload.replyAction:
      guard let text = userText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty
      else { return nil }
      kind = .reply(text)
    case PushPayload.markAsReadAction:
      kind = .markAsRead
    case UNNotificationDefaultActionIdentifier:
      kind = .open
    default:
      return nil
    }
    self.roomId = roomId
    eventId = PushPayload.eventId(in: userInfo)
    threadId = PushPayload.threadId(in: userInfo)
    userId = PushPayload.userId(in: userInfo)
    self.title = title
  }

  static var categories: Set<UNNotificationCategory> {
    let reply = UNTextInputNotificationAction(
      identifier: PushPayload.replyAction, title: "Reply", options: [],
      textInputButtonTitle: "Send", textInputPlaceholder: "Message")
    let markAsRead = UNNotificationAction(
      identifier: PushPayload.markAsReadAction, title: "Mark as read", options: [])
    return [
      UNNotificationCategory(
        identifier: PushPayload.messageCategory, actions: [reply, markAsRead],
        intentIdentifiers: [], options: [])
    ]
  }

  static func replyFailureContent(for action: NotificationAction) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = action.title
    content.body = "Your reply was not sent. Open the chat to try again."
    content.threadIdentifier = action.roomId
    content.userInfo = [PushPayload.roomIdKey: action.roomId]
    if let threadId = action.threadId { content.userInfo[PushPayload.threadIdKey] = threadId }
    return content
  }

  static func postReplyFailure(_ action: NotificationAction) async {
    let request = UNNotificationRequest(
      identifier: UUID().uuidString, content: replyFailureContent(for: action), trigger: nil)
    try? await UNUserNotificationCenter.current().add(request)
  }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  @MainActor static var push: PushCenter?
  @MainActor static weak var accounts: AccountsCoordinator?

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    UNUserNotificationCenter.current().setNotificationCategories(NotificationAction.categories)
    return true
  }

  func application(
    _ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Task { @MainActor in await Self.push?.didReceive(deviceToken: deviceToken) }
  }

  func application(
    _ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error
  ) {
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    let roomId = PushPayload.roomId(in: notification.request.content.userInfo)
    let shows = await MainActor.run { Self.push?.showsBanner(forRoom: roomId) ?? true }
    return shows ? [.banner, .list, .sound, .badge] : []
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    let content = response.notification.request.content
    guard
      let action = NotificationAction(
        actionIdentifier: response.actionIdentifier,
        userText: (response as? UNTextInputNotificationResponse)?.userText,
        userInfo: content.userInfo, title: content.title)
    else { return }
    if let accounts = await Self.accounts {
      await accounts.handle(action)
    } else {
      let push = await Self.push
      await push?.handle(action)
    }
  }
}

enum ApnsEnvironment {
  static var embeddedProfile: Data? {
    Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision").flatMap {
      try? Data(contentsOf: $0)
    }
  }

  static var isSimulator: Bool {
    #if targetEnvironment(simulator)
      true
    #else
      false
    #endif
  }

  static func isProduction(profile: Data? = embeddedProfile, isSimulator: Bool = isSimulator)
    -> Bool
  {
    if isSimulator { return false }
    guard let profile else { return true }
    let text = String(decoding: profile, as: UTF8.self)
    guard let key = text.range(of: "<key>aps-environment</key>"),
      let open = text.range(of: "<string>", range: key.upperBound..<text.endIndex),
      let close = text.range(of: "</string>", range: open.upperBound..<text.endIndex)
    else { return true }
    return text[open.upperBound..<close.lowerBound] != "development"
  }
}
