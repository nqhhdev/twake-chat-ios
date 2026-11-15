import DesignSystem
import Domain
import Foundation
import Observation
import SwiftUI

/// The Settings tab, as the Flutter `settings` page lists it (`SettingEnum`): the profile, Privacy & Security (chat
/// backup with the recovery key), Notifications (the defaults for direct and group chats), About, and Logout. Logging out
/// is the app's job, passed in like the chat list's (ADR 0005).
@MainActor @Observable
public final class SettingsViewModel {
  public let userId: String
  public private(set) var displayName: String
  /// The user's picture, or `nil`.
  public private(set) var avatar: MediaReference?
  @ObservationIgnored private let media: (any MediaRepository)?
  /// Emoji verification of this session; `nil` hides it.
  @ObservationIgnored public let verification: VerificationViewModel?
  /// The account's sessions; `nil` hides them.
  @ObservationIgnored public let devices: DevicesViewModel?
  public private(set) var recoveryStatus: RecoveryStatus = .unknown
  public private(set) var directMode: NotificationMode = .allMessages
  public private(set) var groupMode: NotificationMode = .allMessages
  public private(set) var isWorking = false
  public private(set) var errorMessage: String?
  /// The recovery key just created, shown once so the user can save it.
  public private(set) var newRecoveryKey: String?
  public private(set) var didRecover = false
  public private(set) var isLoggingOut = false
  /// How chats show room events (Flutter Chat settings); every change is saved on this device at once.
  public var chatDisplay: ChatDisplaySettings {
    didSet { if chatDisplay != oldValue { chatDisplayStore?.save(chatDisplay) } }
  }
  /// Face ID, Touch ID or the passcode when the app opens; `nil` hides it.
  @ObservationIgnored public let appLock: (any AppLockSettings)?
  /// Where the chat display settings are kept; `nil` hides the Chat page.
  @ObservationIgnored private let chatDisplayStore: (any ChatDisplaySettingsStore)?

  @ObservationIgnored private let repository: any AccountSettingsRepository
  @ObservationIgnored private let logOutAction: @MainActor () async -> Bool

  public init(
    userId: String, repository: any AccountSettingsRepository,
    media: (any MediaRepository)? = nil,
    verification: VerificationViewModel? = nil, devices: DevicesViewModel? = nil,
    chatDisplay: (any ChatDisplaySettingsStore)? = nil,
    appLock: (any AppLockSettings)? = nil,
    logOut: @escaping @MainActor () async -> Bool
  ) {
    self.appLock = appLock
    self.chatDisplayStore = chatDisplay
    self.chatDisplay = chatDisplay?.load() ?? ChatDisplaySettings()
    self.verification = verification
    self.devices = devices
    self.userId = userId
    self.displayName = Self.localpart(of: userId)
    self.repository = repository
    self.media = media
    self.logOutAction = logOut
  }

  /// Whether Settings lists the Chat page.
  public var hasChatPage: Bool { chatDisplayStore != nil }

  /// Loads the user's picture as data, for the avatar.
  public func picture(_ reference: MediaReference) async -> Data? {
    try? await media?.thumbnail(reference, width: 192, height: 192)
  }

  public func load() async {
    if let name = await repository.displayName() { displayName = name }
    avatar = await repository.avatar()
    directMode = await repository.defaultNotificationMode(isDirect: true)
    groupMode = await repository.defaultNotificationMode(isDirect: false)
    doNotDisturb = await repository.isDoNotDisturbOn()
    statusMessage = await repository.statusMessage()
    recoveryStatus = await repository.recoveryStatus()
  }

  /// The people the user blocked; `nil` until loaded.
  public private(set) var blockedUsers: [BlockedUser]?

  public func loadBlockedUsers() async {
    do {
      blockedUsers = try await repository.blockedUsers()
    } catch {
      blockedUsers = []
      errorMessage = "Could not load the blocked people."
    }
  }

  /// Unblocks someone and takes them off the list.
  public func unblock(_ user: BlockedUser) async {
    errorMessage = nil
    do {
      try await repository.unblock(userId: user.id)
      withAnimation { blockedUsers?.removeAll { $0.id == user.id } }
    } catch {
      errorMessage = "Could not unblock \(user.name). Please try again."
    }
  }

  /// A new picture is uploading.
  public private(set) var isUpdatingPicture = false

  /// Makes a prepared picture the user's avatar (Flutter `settings_profile`), then shows the new one.
  public func setPicture(_ picture: PreparedPicture) async {
    guard !isUpdatingPicture else { return }
    isUpdatingPicture = true
    defer { isUpdatingPicture = false }
    errorMessage = nil
    do {
      try await repository.setAvatar(
        PictureUpload(
          data: picture.jpeg, mimeType: "image/jpeg", width: picture.side, height: picture.side))
      avatar = await repository.avatar()
    } catch {
      errorMessage = "Could not change your picture. Please try again."
    }
  }

  /// Removes the user's avatar; others see the initial.
  public func removePicture() async {
    guard !isUpdatingPicture else { return }
    isUpdatingPicture = true
    defer { isUpdatingPicture = false }
    errorMessage = nil
    do {
      try await repository.removeAvatar()
      avatar = nil
    } catch {
      errorMessage = "Could not remove your picture. Please try again."
    }
  }

  /// Changes the display name others see; an empty name is refused. Returns whether it worked.
  @discardableResult
  public func rename(to name: String) async -> Bool {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty, !isWorking else { return false }
    isWorking = true
    defer { isWorking = false }
    errorMessage = nil
    do {
      try await repository.setDisplayName(name)
      displayName = name
      return true
    } catch {
      errorMessage = "Could not change your name. Please try again."
      return false
    }
  }

  /// The e-mail addresses and phone numbers of the account; `nil` until loaded.
  public private(set) var linkedAddresses: [LinkedAddress]?

  public func loadLinkedAddresses() async {
    linkedAddresses = await repository.linkedAddresses()
  }

  /// Who sees the e-mail and phone; `nil` until ToM answers, and then the choice is not offered.
  public private(set) var contactsVisibility: ContactsVisibility?

  public func loadContactsVisibility() async {
    contactsVisibility = await repository.contactsVisibility()
  }

  /// Saves the choice; the picker shows it at once and goes back if the server refuses.
  public func setContactsVisibility(_ visibility: ContactsVisibility) async {
    let previous = contactsVisibility
    contactsVisibility = visibility
    errorMessage = nil
    do {
      try await repository.setContactsVisibility(visibility)
    } catch {
      contactsVisibility = previous
      errorMessage = "Could not change who sees your e-mail and phone."
    }
  }

  /// The cached messages and media on the device, in bytes; `nil` until read or when unknown.
  public private(set) var cacheSize: Int?
  public private(set) var isClearingCache = false

  public func loadCacheSize() async {
    cacheSize = await repository.cacheSize()
  }

  public func clearCache() async {
    guard !isClearingCache else { return }
    isClearingCache = true
    defer { isClearingCache = false }
    errorMessage = nil
    do {
      try await repository.clearCache()
      cacheSize = await repository.cacheSize()
    } catch {
      errorMessage = "Could not clear the cache. Please try again."
    }
  }

  /// The status message others see on the user's profile.
  public private(set) var statusMessage: String?

  public func setStatusMessage(_ text: String) async {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let previous = statusMessage
    statusMessage = trimmed.isEmpty ? nil : trimmed
    do {
      try await repository.setStatusMessage(trimmed)
    } catch {
      statusMessage = previous
      errorMessage = "Could not change your status. Please try again."
    }
  }

  /// Every notification of the account is off.
  public private(set) var doNotDisturb = false

  public func setDoNotDisturb(_ on: Bool) async {
    let previous = doNotDisturb
    doNotDisturb = on
    do {
      try await repository.setDoNotDisturb(on)
    } catch {
      doNotDisturb = previous
      errorMessage = "Could not change Do Not Disturb. Please try again."
    }
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

  /// What the identity reset under way waits for; `nil` when none is.
  public private(set) var identityReset: IdentityResetStep?
  public private(set) var didResetIdentity = false

  public func startIdentityReset() async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    errorMessage = nil
    do {
      let step = try await repository.startIdentityReset()
      if step == .done { await identityWasReset() } else { identityReset = step }
    } catch {
      errorMessage = "Could not reset your identity. Please try again."
    }
  }

  /// Sends the password, or after the web page, finishes the reset.
  public func finishIdentityReset(password: String? = nil) async {
    guard identityReset != nil, !isWorking else { return }
    isWorking = true
    defer { isWorking = false }
    do {
      try await repository.finishIdentityReset(password: password)
      identityReset = nil
      await identityWasReset()
    } catch {
      errorMessage =
        password == nil
        ? "The reset was not approved. Please try again." : "Wrong password, or the reset failed."
    }
  }

  public func cancelIdentityReset() async {
    identityReset = nil
    await repository.cancelIdentityReset()
  }

  private func identityWasReset() async {
    didResetIdentity = true
    recoveryStatus = await repository.recoveryStatus()
    await verification?.refreshState()
  }

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
