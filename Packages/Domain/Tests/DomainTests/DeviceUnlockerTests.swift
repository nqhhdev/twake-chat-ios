import Domain
import Testing

/// The unlock after sign-in of ADR 0024, one test per branch.
struct DeviceUnlockerTests {
  @Test func verifiedDeviceAsksNothing() async {
    let encryption = FakeEncryption(verified: true)
    let vault = FakeVault(fetches: [.key("words")])

    let outcome = await unlocker(encryption, vault).run()

    #expect(outcome == .alreadyVerified)
    #expect(await vault.fetchCount == 0)
  }

  @Test func keyFromVaultVerifiesTheDevice() async {
    let encryption = FakeEncryption(status: .incomplete, recoverSucceeds: { _, _ in true })
    let vault = FakeVault(fetches: [.key("words")])

    let outcome = await unlocker(encryption, vault).run()

    #expect(outcome == .verifiedFromVault)
    #expect(await encryption.recoverCalls == [RecoverCall(key: "words", fixingBackup: false)])
    #expect(await encryption.setUpCount == 0)
  }

  @Test func keyThatKeepsFailingIsRetriedThenTriedWithABackupFix() async {
    let encryption = FakeEncryption(status: .incomplete, recoverSucceeds: { _, fixing in fixing })
    let vault = FakeVault(fetches: [.key("words")])

    let outcome = await unlocker(encryption, vault).run()

    #expect(outcome == .verifiedFromVault)
    let calls = await encryption.recoverCalls
    #expect(calls.count == 21)
    #expect(calls.dropLast().allSatisfy { !$0.fixingBackup })
    #expect(calls.last == RecoverCall(key: "words", fixingBackup: true))
  }

  @Test func keyThatOpensNothingAsksTheUser() async {
    let encryption = FakeEncryption(status: .incomplete, recoverSucceeds: { _, _ in false })
    let vault = FakeVault(fetches: [.key("wrong")])

    let outcome = await unlocker(encryption, vault).run()

    #expect(outcome == .needsKey)
    #expect(await encryption.setUpCount == 0)
  }

  @Test func deadKeyOnAnAccountWithoutRecoveryIsReplaced() async {
    let encryption = FakeEncryption(status: .disabled, newKey: "fresh")
    let vault = FakeVault(fetches: [.key("dead")])

    let outcome = await unlocker(encryption, vault).run()

    #expect(outcome == .setUp)
    #expect(await encryption.recoverCalls.isEmpty)
    #expect(await vault.actions == [.delete, .save("fresh")])
  }

  @Test func keyOfADeviceStillSettingUpIsUsedOnceRecoveryExists() async {
    let encryption = FakeEncryption(
      statuses: [.disabled, .disabled, .enabled], recoverSucceeds: { _, _ in true })
    let vault = FakeVault(fetches: [.key("words")])

    let outcome = await unlocker(encryption, vault).run()

    #expect(outcome == .verifiedFromVault)
    #expect(await encryption.setUpCount == 0)
  }

  @Test func newAccountIsSetUpAndItsKeyKept() async {
    let encryption = FakeEncryption(status: .disabled, newKey: "fresh")
    let vault = FakeVault(fetches: [.empty])

    let outcome = await unlocker(encryption, vault).run()

    #expect(outcome == .setUp)
    #expect(await vault.actions == [.save("fresh")])
  }

  @Test func keyTheVaultRefusesIsShownToTheUser() async {
    let encryption = FakeEncryption(status: .disabled, newKey: "fresh")
    let vault = FakeVault(fetches: [.empty], saveResult: .alreadyKept)

    let outcome = await unlocker(encryption, vault).run()

    #expect(outcome == .setUpNotSaved(recoveryKey: "fresh"))
  }

  @Test func failedSetUpAsksTheUser() async {
    let encryption = FakeEncryption(status: .disabled, newKey: nil)
    let vault = FakeVault(fetches: [.empty])

    let outcome = await unlocker(encryption, vault).run()

    #expect(outcome == .needsKey)
    #expect(await vault.actions.isEmpty)
  }

  @Test func accountSetUpElsewhereWaitsForItsKey() async {
    let encryption = FakeEncryption(status: .enabled, recoverSucceeds: { _, _ in true })
    let vault = FakeVault(fetches: [.empty, .empty, .key("words")])

    let outcome = await unlocker(encryption, vault).run()

    #expect(outcome == .verifiedFromVault)
    #expect(await encryption.setUpCount == 0)
  }

  @Test func accountSetUpElsewhereWithoutAKeyAsksTheUser() async {
    let encryption = FakeEncryption(status: .enabled)
    let vault = FakeVault(fetches: [.empty])

    let outcome = await unlocker(encryption, vault).run()

    #expect(outcome == .needsKey)
    #expect(await encryption.setUpCount == 0)
    // The first read, then one a second for 20 s.
    #expect(await vault.fetchCount == 22)
  }

  @Test func withoutToMNothingIsSetUp() async {
    let encryption = FakeEncryption(status: .disabled, newKey: "fresh")
    let vault = FakeVault(fetches: [.failure(.noServer)])

    let outcome = await unlocker(encryption, vault).run()

    #expect(outcome == .needsKey)
    #expect(await encryption.setUpCount == 0)
  }

  @Test func vaultDownOnANewAccountShowsTheKey() async {
    let encryption = FakeEncryption(status: .disabled, newKey: "fresh")
    let vault = FakeVault(fetches: [.failure(.unavailable)])

    let outcome = await unlocker(encryption, vault).run()

    #expect(outcome == .setUpNotSaved(recoveryKey: "fresh"))
    #expect(await vault.actions.isEmpty)
  }

  @Test func vaultDownOnASetUpAccountAsksTheUser() async {
    let encryption = FakeEncryption(status: .enabled)
    let vault = FakeVault(fetches: [.failure(.unavailable)])

    let outcome = await unlocker(encryption, vault).run()

    #expect(outcome == .needsKey)
    #expect(await encryption.setUpCount == 0)
  }

  private func unlocker(_ encryption: FakeEncryption, _ vault: FakeVault) -> DeviceUnlocker {
    DeviceUnlocker(encryption: encryption, vault: vault, sleep: { _ in })
  }
}

struct RecoverCall: Equatable {
  let key: String
  let fixingBackup: Bool
}

private actor FakeEncryption: DeviceRecoveryRepository {
  private let verified: Bool
  /// The statuses returned in turn; the last one repeats.
  private var statuses: [RecoveryStatus]
  private let recoverSucceeds: @Sendable (String, Bool) -> Bool
  private let newKey: String?
  private(set) var recoverCalls: [RecoverCall] = []
  private(set) var setUpCount = 0

  init(
    verified: Bool = false, status: RecoveryStatus = .enabled, statuses: [RecoveryStatus]? = nil,
    recoverSucceeds: @escaping @Sendable (String, Bool) -> Bool = { _, _ in false },
    newKey: String? = "fresh"
  ) {
    self.verified = verified
    self.statuses = statuses ?? [status]
    self.recoverSucceeds = recoverSucceeds
    self.newKey = newKey
  }

  func isDeviceVerified() async -> Bool { verified }

  func recoveryStatus() async -> RecoveryStatus {
    statuses.count > 1 ? statuses.removeFirst() : statuses[0]
  }

  func recover(recoveryKey: String, fixingBackup: Bool) async -> Bool {
    recoverCalls.append(RecoverCall(key: recoveryKey, fixingBackup: fixingBackup))
    return recoverSucceeds(recoveryKey, fixingBackup)
  }

  func setUpRecovery() async -> String? {
    setUpCount += 1
    return newKey
  }
}

private actor FakeVault: RecoveryVault {
  enum Fetch {
    case key(String)
    case empty
    case failure(RecoveryVaultError)
  }

  enum Action: Equatable {
    case save(String)
    case delete
  }

  /// The answers to `fetchRecoveryKey` in turn; the last one repeats.
  private var fetches: [Fetch]
  private let saveResult: RecoveryVaultSaveResult
  private(set) var fetchCount = 0
  private(set) var actions: [Action] = []

  init(fetches: [Fetch], saveResult: RecoveryVaultSaveResult = .saved) {
    self.fetches = fetches
    self.saveResult = saveResult
  }

  func fetchRecoveryKey() async throws(RecoveryVaultError) -> String? {
    fetchCount += 1
    let fetch = fetches.count > 1 ? fetches.removeFirst() : fetches[0]
    switch fetch {
    case .key(let key): return key
    case .empty: return nil
    case .failure(let error): throw error
    }
  }

  func saveRecoveryKey(_ recoveryKey: String) async -> RecoveryVaultSaveResult {
    actions.append(.save(recoveryKey))
    return saveResult
  }

  func deleteRecoveryKey() async {
    actions.append(.delete)
  }
}
