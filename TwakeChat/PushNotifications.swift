import Domain
import Observation
import SwiftUI
import UIKit
import UserNotifications

/// Push notifications for the signed-in account: asks permission once the user is signed in, hands Apple's device token
/// to the homeserver (`PushRepository`), shows notifications while the app is open, and remembers the room a tapped
/// notification is about so the shell opens it. Without a repository (tests), it does nothing.
@MainActor @Observable
final class PushCenter {
  /// A room the shell should open: a tapped notification's, or a direct chat started from a member's profile. The
  /// shell clears it once open.
  var pendingRoomId: String?
  /// Someone the user wants to write to and has no direct chat with yet: the shell shows the draft chat, and the
  /// first message creates the chat. The shell clears it once shown.
  var pendingDraftUserId: String?
  /// The chat on screen: its notifications are not shown as banners, and opening it clears them.
  @ObservationIgnored var openRoomId: String? {
    didSet { if let openRoomId { clearNotifications(roomId: openRoomId) } }
  }
  @ObservationIgnored private var didRegister = false
  /// Whether the user allowed notifications; `nil` until asked.
  private(set) var isAllowed: Bool?

  @ObservationIgnored private let repository: (any PushRepository)?
  @ObservationIgnored private let requestAuthorization: @MainActor () async -> Bool
  @ObservationIgnored private let registerForRemoteNotifications: @MainActor () -> Void

  init(
    repository: (any PushRepository)?,
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
    self.requestAuthorization = requestAuthorization
    self.registerForRemoteNotifications = registerForRemoteNotifications
  }

  /// Asks permission (iOS asks the user only once) and, when allowed, asks Apple for a device token.
  func start() async {
    guard repository != nil else { return }
    let allowed = await requestAuthorization()
    isAllowed = allowed
    if allowed {
      didRegister = true
      registerForRemoteNotifications()
    }
  }

  /// Asks Apple for the device token again when the app comes back, so a changed token reaches the homeserver.
  func refreshToken() async {
    guard repository != nil, didRegister else { return }
    registerForRemoteNotifications()
  }

  /// Removes the delivered notifications of a chat once the user sees it.
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

  /// Whether a notification about `roomId` shows while the app is open: not for the chat on screen.
  func showsBanner(forRoom roomId: String?) -> Bool {
    roomId == nil || roomId != openRoomId
  }

  /// Apple gave a device token: register it with the homeserver. Debug builds use the APNs sandbox.
  func didReceive(deviceToken: Data) async {
    #if DEBUG
      let isProduction = false
    #else
      let isProduction = true
    #endif
    try? await repository?.register(deviceToken: deviceToken, isProduction: isProduction)
  }

  /// Stops pushing to this device, before logging out.
  func stop() async {
    await repository?.unregister()
  }
}

/// UIKit's push callbacks, forwarded to the app's `PushCenter`.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  /// Set by the app at launch.
  @MainActor static var push: PushCenter?

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
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
    // No token, no push: the app still works and asks again at the next launch.
  }

  /// Notifications show as banners while the app is open, as Messages does.
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    let roomId = notification.request.content.userInfo["room_id"] as? String
    let shows = await MainActor.run { Self.push?.showsBanner(forRoom: roomId) ?? true }
    return shows ? [.banner, .list, .sound, .badge] : []
  }

  /// A tap on a notification opens its room.
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    let roomId = response.notification.request.content.userInfo["room_id"] as? String
    await MainActor.run { Self.push?.pendingRoomId = roomId }
  }
}
