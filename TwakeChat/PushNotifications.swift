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
  /// The notification's title (the room or sender name), used until the room list knows the room.
  var pendingRoomName: String?
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

  /// Apple gave a device token: register it with the homeserver, for the APNs server the app is signed for.
  func didReceive(deviceToken: Data) async {
    try? await repository?.register(
      deviceToken: deviceToken, isProduction: ApnsEnvironment.isProduction())
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
    let content = response.notification.request.content
    let roomId = content.userInfo["room_id"] as? String
    let title = content.title
    await MainActor.run {
      Self.push?.pendingRoomId = roomId
      if !title.isEmpty { Self.push?.pendingRoomName = title }
    }
  }
}

/// Which APNs server gave the device token. The signing profile decides, not the build configuration: a Release build
/// installed from Xcode is signed for development and gets a sandbox token, which the production server refuses.
enum ApnsEnvironment {
  /// The profile Xcode embeds in a development, ad hoc or enterprise build. An App Store or TestFlight build has none.
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

  /// Production unless the profile says `aps-environment` is `development`. No profile (App Store, TestFlight) is
  /// production, and so is a profile without the key.
  static func isProduction(profile: Data? = embeddedProfile, isSimulator: Bool = isSimulator)
    -> Bool
  {
    // A simulator has no profile and gets its token from the sandbox.
    if isSimulator { return false }
    guard let profile else { return true }
    // The profile is a signed envelope around a property list; the list itself is plain text.
    let text = String(decoding: profile, as: UTF8.self)
    guard let key = text.range(of: "<key>aps-environment</key>"),
      let open = text.range(of: "<string>", range: key.upperBound..<text.endIndex),
      let close = text.range(of: "</string>", range: open.upperBound..<text.endIndex)
    else { return true }
    return text[open.upperBound..<close.lowerBound] != "development"
  }
}
