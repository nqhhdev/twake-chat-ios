import Foundation

/// Why the vault could not say whether it keeps a key.
public enum RecoveryVaultError: Error, Sendable, Equatable {
  /// The homeserver names no ToM server: there is no vault.
  case noServer
  /// ToM did not answer (outage, rate limit, network).
  case unavailable
}

/// What became of a key given to the vault.
public enum RecoveryVaultSaveResult: Sendable, Equatable {
  case saved
  /// The vault keeps another key already; it never replaces it (ToM answers 409).
  case alreadyKept
  case failed
}

/// Where the user's recovery key is kept for them, so a new device unlocks itself: ToM's `/_twake/recoveryWords`, the
/// key the Flutter app and the web client share (ADR 0024). The key is never logged.
public protocol RecoveryVault: Sendable {
  /// The kept key; `nil` when the vault keeps none.
  func fetchRecoveryKey() async throws(RecoveryVaultError) -> String?
  func saveRecoveryKey(_ recoveryKey: String) async -> RecoveryVaultSaveResult
  /// Lets go of a key that opens nothing. Best effort.
  func deleteRecoveryKey() async
}

/// What the unlock after sign-in needs from the encryption of this session (ADR 0024).
public protocol DeviceRecoveryRepository: Sendable {
  func isDeviceVerified() async -> Bool
  func recoveryStatus() async -> RecoveryStatus
  /// Verifies this device with the recovery key; `fixingBackup` also makes the key backup when it is missing.
  func recover(recoveryKey: String, fixingBackup: Bool) async -> Bool
  /// Sets up the key backup and the secret storage of an account that has none; the new recovery key, or `nil`.
  func setUpRecovery() async -> String?
}
