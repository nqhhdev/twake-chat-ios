import Foundation

/// How a room notifies the user, as the Flutter notification settings name the choices.
public enum NotificationMode: Sendable, Equatable, CaseIterable {
  case allMessages
  case mentionsAndKeywords
  case mute
}

/// Whether the user's encryption keys are backed up with a recovery key (`m.secret_storage`), as the SDK reports it.
public enum RecoveryStatus: Sendable, Equatable {
  /// Not known yet: the client is still setting up encryption.
  case unknown
  /// Keys are backed up and this device holds them.
  case enabled
  /// No recovery is set up for this account.
  case disabled
  /// Recovery is set up, but this device lacks the keys: enter the recovery key to read older encrypted messages.
  case incomplete
}

public enum SettingsError: Error, Sendable, Equatable {
  case notSignedIn
  /// The recovery key does not match the account's backup.
  case wrongRecoveryKey
  case requestFailed
}

/// What the Settings tab needs about the signed-in account: its display name, its encryption recovery, and its default
/// notification modes. Implemented in MatrixData; no SDK type appears here (ADR 0006).
public protocol AccountSettingsRepository: Sendable {
  /// The user's display name, or `nil` when the profile has none.
  func displayName() async -> String?

  func recoveryStatus() async -> RecoveryStatus

  /// Restores the keys from the backup with the recovery key, so older encrypted messages can be read.
  func recover(recoveryKey: String) async throws(SettingsError)

  /// Sets up key backup and recovery, and returns the new recovery key to show the user once.
  func enableRecovery() async throws(SettingsError) -> String

  /// The mode new rooms of this kind use unless the user sets one for the room.
  func defaultNotificationMode(isDirect: Bool) async -> NotificationMode

  func setDefaultNotificationMode(_ mode: NotificationMode, isDirect: Bool)
    async throws(SettingsError)
}
