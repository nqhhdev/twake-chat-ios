import Authentication
import AuthenticationTestSupport
import Domain
import Foundation
import Testing

@testable import TwakeChat

/// The root runs the unlock of ADR 0024 once per sign-in, and shows a key ToM did not keep.
@MainActor
struct RootDeviceUnlockTests {
  /// A new account whose key ToM refuses: the unlock sets it up and must show the key.
  private actor NewAccount: DeviceRecoveryRepository, RecoveryVault {
    private(set) var setUpCount = 0

    func isDeviceVerified() async -> Bool { false }
    func recoveryStatus() async -> RecoveryStatus { .disabled }
    func recover(recoveryKey: String, fixingBackup: Bool) async -> Bool { false }
    func setUpRecovery() async -> String? {
      setUpCount += 1
      return "EsTc fresh"
    }
    func fetchRecoveryKey() async throws(RecoveryVaultError) -> String? { nil }
    func saveRecoveryKey(_ recoveryKey: String) async -> RecoveryVaultSaveResult { .failed }
    func deleteRecoveryKey() async {}
  }

  private let session = UserSession(
    userId: "@alice:example.org", deviceId: "DEVICE",
    homeserverURL: URL(string: "https://matrix.example.org")!, accessToken: "token",
    refreshToken: nil)

  @Test func keyToMDidNotKeepIsShownOnce() async throws {
    let account = NewAccount()
    let repository = FakeAuthenticationRepository()
    repository.restoreResult = .success(session)
    let root = RootCoordinator(
      repository: repository,
      deviceUnlock: DeviceUnlocker(encryption: account, vault: account, sleep: { _ in }),
      signInConfiguration: SignInConfiguration(
        registrationURL: nil, workplaceHomeserver: nil, defaultHomeserver: nil,
        privacyURL: URL(string: "https://twake.app/policy")!),
      webAuthenticator: ClosedWebAuthenticator())
    await root.start()
    guard case .signedIn(let signedIn) = root.authentication?.screen else {
      Issue.record("expected the signed-in state")
      return
    }

    await root.unlockDevice(for: signedIn)
    #expect(root.unsavedRecoveryKey == "EsTc fresh")

    // The screen appearing again for the same sign-in does not set up a second time.
    root.unsavedRecoveryKey = nil
    await root.unlockDevice(for: signedIn)
    #expect(root.unsavedRecoveryKey == nil)
    #expect(await account.setUpCount == 1)
  }

  private actor KeptKey: DeviceRecoveryRepository, RecoveryVault {
    func isDeviceVerified() async -> Bool { false }
    func recoveryStatus() async -> RecoveryStatus { .enabled }
    func recover(recoveryKey: String, fixingBackup: Bool) async -> Bool { true }
    func setUpRecovery() async -> String? { nil }
    func fetchRecoveryKey() async throws(RecoveryVaultError) -> String? { "EsTc kept" }
    func saveRecoveryKey(_ recoveryKey: String) async -> RecoveryVaultSaveResult { .saved }
    func deleteRecoveryKey() async {}
  }

  private final class Counter: @unchecked Sendable {
    var count = 0
  }

  @Test func aDeviceUnlockedFromTheVaultAsksOpenChatsToDecryptAgain() async throws {
    let account = KeptKey()
    let repository = FakeAuthenticationRepository()
    repository.restoreResult = .success(session)
    let root = RootCoordinator(
      repository: repository,
      deviceUnlock: DeviceUnlocker(encryption: account, vault: account, sleep: { _ in }),
      signInConfiguration: SignInConfiguration(
        registrationURL: nil, workplaceHomeserver: nil, defaultHomeserver: nil,
        privacyURL: URL(string: "https://twake.app/policy")!),
      webAuthenticator: ClosedWebAuthenticator())
    await root.start()
    guard case .signedIn(let signedIn) = root.authentication?.screen else {
      Issue.record("expected the signed-in state")
      return
    }
    let posted = Counter()
    let observer = NotificationCenter.default.addObserver(
      forName: .encryptionKeysImported, object: nil, queue: nil
    ) { _ in posted.count += 1 }
    defer { NotificationCenter.default.removeObserver(observer) }

    await root.unlockDevice(for: signedIn)

    #expect(posted.count == 1)
    #expect(root.unsavedRecoveryKey == nil)
  }
}
