import Domain
import Foundation
import MatrixRustSDK

/// `AccountSettingsRepository` on the SDK client (ADR 0006): profile, encryption recovery and notification defaults.
/// The recovery key is never logged or stored here; it is returned once to be shown to the user.
public actor AccountSettingsProxy: AccountSettingsRepository {
  private let clientProxy: @Sendable () async -> ClientProxy?

  public init(authentication: MatrixAuthenticationRepository) {
    clientProxy = { await authentication.clientProxy }
  }

  public func displayName() async -> String? {
    guard let client = await clientProxy() else { return nil }
    return (try? await client.client.displayName()).flatMap { $0.isEmpty ? nil : $0 }
  }

  public func avatar() async -> MediaReference? {
    guard let client = await clientProxy() else { return nil }
    return RoomSummaryMapper.avatar((try? await client.client.avatarUrl()) ?? nil)
  }

  public func blockedUsers() async throws(SettingsError) -> [BlockedUser] {
    guard let client = await clientProxy()?.client else { throw .notSignedIn }
    let ids: [String]
    do { ids = try await client.ignoredUsers() } catch { throw .requestFailed }
    var users: [BlockedUser] = []
    for id in ids {
      let name = (try? await client.getProfile(userId: id))?.displayName
      users.append(BlockedUser(id: id, displayName: name))
    }
    return users.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
  }

  public func unblock(userId: String) async throws(SettingsError) {
    guard let client = await clientProxy()?.client else { throw .notSignedIn }
    do { try await client.unignoreUser(userId: userId) } catch { throw .requestFailed }
  }

  public func setDisplayName(_ name: String) async throws(SettingsError) {
    guard let client = await clientProxy() else { throw .notSignedIn }
    do { try await client.client.setDisplayName(name: name) } catch { throw .requestFailed }
  }

  public func setAvatar(_ picture: PictureUpload) async throws(SettingsError) {
    guard let client = await clientProxy() else { throw .notSignedIn }
    do {
      try await client.client.uploadAvatar(mimeType: picture.mimeType, data: picture.data)
    } catch {
      throw .requestFailed
    }
  }

  public func removeAvatar() async throws(SettingsError) {
    guard let client = await clientProxy() else { throw .notSignedIn }
    do { try await client.client.removeAvatar() } catch { throw .requestFailed }
  }

  public func recoveryStatus() async -> RecoveryStatus {
    guard let client = await clientProxy() else { return .unknown }
    let encryption = client.client.encryption()
    await encryption.waitForE2eeInitializationTasks()
    return switch encryption.recoveryState() {
    case .enabled: .enabled
    case .disabled: .disabled
    case .incomplete: .incomplete
    default: .unknown
    }
  }

  public func recover(recoveryKey: String) async throws(SettingsError) {
    guard let client = await clientProxy() else { throw .notSignedIn }
    do {
      try await client.client.encryption().recover(
        recoveryKey: recoveryKey.trimmingCharacters(in: .whitespacesAndNewlines))
    } catch {
      throw .wrongRecoveryKey
    }
  }

  public func enableRecovery() async throws(SettingsError) -> String {
    guard let client = await clientProxy() else { throw .notSignedIn }
    do {
      return try await client.client.encryption().enableRecovery(
        waitForBackupsToUpload: false, passphrase: nil, progressListener: IgnoredRecoveryProgress())
    } catch {
      throw .requestFailed
    }
  }

  public func defaultNotificationMode(isDirect: Bool) async -> NotificationMode {
    guard let client = await clientProxy() else { return .allMessages }
    let settings = await client.client.getNotificationSettings()
    return NotificationModeMapper.domain(
      await settings.getDefaultRoomNotificationMode(isEncrypted: false, isOneToOne: isDirect))
  }

  public func setDefaultNotificationMode(_ mode: NotificationMode, isDirect: Bool)
    async throws(SettingsError)
  {
    guard let client = await clientProxy() else { throw .notSignedIn }
    let settings = await client.client.getNotificationSettings()
    do {
      // Encrypted and unencrypted rooms have separate rules; the user sets one mode for both.
      for isEncrypted in [false, true] {
        try await settings.setDefaultRoomNotificationMode(
          isEncrypted: isEncrypted, isOneToOne: isDirect, mode: NotificationModeMapper.sdk(mode))
      }
    } catch {
      throw .requestFailed
    }
  }
}

enum NotificationModeMapper {
  static func domain(_ mode: RoomNotificationMode) -> NotificationMode {
    switch mode {
    case .allMessages: .allMessages
    case .mentionsAndKeywordsOnly: .mentionsAndKeywords
    case .mute: .mute
    }
  }

  static func sdk(_ mode: NotificationMode) -> RoomNotificationMode {
    switch mode {
    case .allMessages: .allMessages
    case .mentionsAndKeywords: .mentionsAndKeywordsOnly
    case .mute: .mute
    }
  }
}

private final class IgnoredRecoveryProgress: EnableRecoveryProgressListener {
  func onUpdate(status: EnableRecoveryProgress) {}
}
