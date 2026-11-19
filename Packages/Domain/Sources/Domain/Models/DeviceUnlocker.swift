import Foundation

/// How the unlock after sign-in ended.
public enum DeviceUnlockOutcome: Sendable, Equatable {
  case alreadyVerified
  /// The key kept by the vault verified this device.
  case verifiedFromVault
  /// The account had no recovery: it was set up and the vault keeps its key.
  case setUp
  /// Set up, but the vault did not keep the key: show it to the user, or it is lost.
  case setUpNotSaved(recoveryKey: String)
  /// The user verifies this device by hand: the room banner and Settings.
  case needsKey
}

/// Makes this device able to read the encrypted history without asking the user, with the recovery key the vault
/// keeps (ADR 0024). Run once the session is ready, while the device is not verified.
public struct DeviceUnlocker: Sendable {
  /// How long to wait for another device that is about to give the vault its key, or to finish setting up.
  public static let waitForOtherDevice: Duration = .seconds(20)
  static let pollInterval: Duration = .seconds(1)

  private let encryption: any DeviceRecoveryRepository
  private let vault: any RecoveryVault
  private let sleep: @Sendable (Duration) async -> Void

  /// - Parameter sleep: Waits between two tries; the tests pass one that returns at once.
  public init(
    encryption: any DeviceRecoveryRepository, vault: any RecoveryVault,
    sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
  ) {
    self.encryption = encryption
    self.vault = vault
    self.sleep = sleep
  }

  public func run() async -> DeviceUnlockOutcome {
    if await encryption.isDeviceVerified() { return .alreadyVerified }
    let stored: String?
    switch await fetchKept() {
    case .success(let key):
      stored = key
    case .failure(.noServer):
      return .needsKey
    case .failure(.unavailable):
      // A vault that does not answer keeps nothing: a new account is set up and its key shown to the user.
      guard await encryption.recoveryStatus() == .disabled,
        let key = await encryption.setUpRecovery()
      else { return .needsKey }
      return .setUpNotSaved(recoveryKey: key)
    }
    if let stored { return await unlock(with: stored) }
    if await encryption.recoveryStatus() == .disabled { return await setUp(replacingKept: false) }
    // Set up by another device that has not given the vault its key yet.
    guard let key = await poll({ try? await vault.fetchRecoveryKey() }) else { return .needsKey }
    return await verify(with: key)
  }

  private func fetchKept() async -> Result<String?, RecoveryVaultError> {
    do throws(RecoveryVaultError) {
      return .success(try await vault.fetchRecoveryKey())
    } catch {
      return .failure(error)
    }
  }

  /// A key in the vault on an account without recovery belongs to a device still setting up, or to one that died
  /// before it did: wait for the first, replace the second.
  private func unlock(with key: String) async -> DeviceUnlockOutcome {
    let setUpElsewhere = await poll {
      await encryption.recoveryStatus() == .disabled ? nil : true
    }
    guard setUpElsewhere != nil else { return await setUp(replacingKept: true) }
    return await verify(with: key)
  }

  /// A failure other than a wrong key may mean the device that kept the key is still finishing: try again for a
  /// while, then once more making the missing backup, since the key opens the storage.
  private func verify(with key: String) async -> DeviceUnlockOutcome {
    var waited: Duration = .zero
    while waited < Self.waitForOtherDevice {
      if await encryption.recover(recoveryKey: key, fixingBackup: false) {
        return .verifiedFromVault
      }
      await sleep(Self.pollInterval)
      waited += Self.pollInterval
    }
    let fixed = await encryption.recover(recoveryKey: key, fixingBackup: true)
    return fixed ? .verifiedFromVault : .needsKey
  }

  private func setUp(replacingKept: Bool) async -> DeviceUnlockOutcome {
    guard let key = await encryption.setUpRecovery() else { return .needsKey }
    if replacingKept { await vault.deleteRecoveryKey() }
    return switch await vault.saveRecoveryKey(key) {
    case .saved: .setUp
    case .alreadyKept, .failed: .setUpNotSaved(recoveryKey: key)
    }
  }

  /// Asks `attempt` once a poll interval until it answers or the wait is over; `nil` then.
  private func poll<T: Sendable>(_ attempt: () async -> T?) async -> T? {
    var waited: Duration = .zero
    while true {
      if let value = await attempt() { return value }
      guard waited < Self.waitForOtherDevice else { return nil }
      await sleep(Self.pollInterval)
      waited += Self.pollInterval
    }
  }
}
