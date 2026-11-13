import Domain
import Foundation
import Observation

/// The Settings tab, as the Flutter `settings` page lists it (`SettingEnum`): the profile, Privacy & Security (chat
/// backup with the recovery key), Notifications (the defaults for direct and group chats), About, and Logout. Logging out
/// is the app's job, passed in like the chat list's (ADR 0005).
@MainActor @Observable
public final class SettingsViewModel {
  public let userId: String
  public private(set) var displayName: String
  public private(set) var recoveryStatus: RecoveryStatus = .unknown
  public private(set) var directMode: NotificationMode = .allMessages
  public private(set) var groupMode: NotificationMode = .allMessages
  public private(set) var isWorking = false
  public private(set) var errorMessage: String?
  /// The recovery key just created, shown once so the user can save it.
  public private(set) var newRecoveryKey: String?
  public private(set) var didRecover = false
  public private(set) var isLoggingOut = false

  @ObservationIgnored private let repository: any AccountSettingsRepository
  @ObservationIgnored private let logOutAction: @MainActor () async -> Bool

  public init(
    userId: String, repository: any AccountSettingsRepository,
    logOut: @escaping @MainActor () async -> Bool
  ) {
    self.userId = userId
    self.displayName = Self.localpart(of: userId)
    self.repository = repository
    self.logOutAction = logOut
  }

  public func load() async {
    if let name = await repository.displayName() { displayName = name }
    directMode = await repository.defaultNotificationMode(isDirect: true)
    groupMode = await repository.defaultNotificationMode(isDirect: false)
    recoveryStatus = await repository.recoveryStatus()
  }

  public func setNotificationMode(_ mode: NotificationMode, isDirect: Bool) async {
    let previous = isDirect ? directMode : groupMode
    if isDirect { directMode = mode } else { groupMode = mode }
    do {
      try await repository.setDefaultNotificationMode(mode, isDirect: isDirect)
    } catch {
      if isDirect { directMode = previous } else { groupMode = previous }
      errorMessage = "Could not change the notifications. Please try again."
    }
  }

  /// Restores the keys with the recovery key the user typed.
  public func recover(with key: String) async {
    guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    errorMessage = nil
    do {
      try await repository.recover(recoveryKey: key)
      didRecover = true
      recoveryStatus = await repository.recoveryStatus()
    } catch .wrongRecoveryKey {
      errorMessage = "Wrong recovery key"
    } catch {
      errorMessage = "Oops, something went wrong…"
    }
  }

  /// Sets up chat backup and shows the new recovery key.
  public func enableRecovery() async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    errorMessage = nil
    do {
      newRecoveryKey = try await repository.enableRecovery()
      recoveryStatus = await repository.recoveryStatus()
    } catch {
      errorMessage = "Could not set up the chat backup. Please try again."
    }
  }

  public func dismissNewRecoveryKey() { newRecoveryKey = nil }

  public func logOut() async {
    guard !isLoggingOut else { return }
    isLoggingOut = true
    defer { isLoggingOut = false }
    errorMessage = nil
    if await !logOutAction() { errorMessage = "Could not log out. Please try again." }
  }

  public static func title(of mode: NotificationMode) -> String {
    switch mode {
    case .allMessages: "All messages"
    case .mentionsAndKeywords: "Mentions and keywords"
    case .mute: "Mute"
    }
  }

  /// `@alice:example.org` shows "alice" until the profile is loaded.
  static func localpart(of userId: String) -> String {
    let localpart = userId.dropFirst(userId.hasPrefix("@") ? 1 : 0).split(separator: ":").first
    return localpart.map(String.init) ?? userId
  }

  /// The app's version, as About shows it.
  public static var appVersion: String {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? "?"
    let build = info?["CFBundleVersion"] as? String ?? "?"
    return "\(version) (\(build))"
  }
}
