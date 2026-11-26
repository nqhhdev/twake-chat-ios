import Foundation
import Testing

@testable import AppShared

struct AccountsTests {
  private static let container = URL(
    filePath: "/private/var/mobile/Containers/Shared/AppGroup/ABC", directoryHint: .isDirectory)

  @Test func theLegacySlotKeepsTheSingleAccountStoreAndKeychainItem() {
    #expect(
      AccountSlot.legacy.storeDirectory(in: Self.container)
        == AppGroupContainer.sdkStoreDirectory(in: Self.container))
    #expect(AccountSlot.legacy.keychainAccount == "session")
  }

  @Test func anotherSlotHasItsOwnStoreAndKeychainItem() {
    let slot = AccountSlot(id: "abc")
    #expect(
      slot.storeDirectory(in: Self.container).path(percentEncoded: false)
        == "/private/var/mobile/Containers/Shared/AppGroup/ABC/Library/Application Support/TwakeChat/Accounts/abc/SDK/"
    )
    #expect(slot.keychainAccount == "session.abc")
  }

  @Test func noSlotStoreIsInsideAnotherSlotStore() {
    let legacy = AccountSlot.legacy.storeDirectory(in: Self.container).path(percentEncoded: false)
    let other = AccountSlot(id: "abc").storeDirectory(in: Self.container).path(
      percentEncoded: false)
    #expect(!legacy.hasPrefix(other))
    #expect(!other.hasPrefix(legacy))
  }

  @Test func freshSlotsDiffer() {
    #expect(AccountSlot.fresh() != AccountSlot.fresh())
    #expect(!AccountSlot.fresh().isLegacy)
  }

  @Test func theSignedInSingleAccountBecomesTheFirstAccountWithoutMoving() {
    let list = AccountList.migrated(nil, legacyUserId: "@alice:a")
    #expect(list.accounts == [AccountRecord(userId: "@alice:a", slot: .legacy)])
    #expect(list.active?.userId == "@alice:a")
  }

  @Test func nobodySignedInMigratesToNoAccount() {
    #expect(AccountList.migrated(nil, legacyUserId: nil).accounts.isEmpty)
    #expect(AccountList.migrated(nil, legacyUserId: "").accounts.isEmpty)
  }

  @Test func aRegisteredListIsKeptAsItIs() {
    let list = AccountList(
      accounts: [AccountRecord(userId: "@bob:b", slot: AccountSlot(id: "x"))],
      activeUserId: "@bob:b")
    #expect(AccountList.migrated(list, legacyUserId: "@alice:a") == list)
  }

  @Test func anEmptyRegisteredListTakesTheLegacySession() {
    let list = AccountList.migrated(AccountList(), legacyUserId: "@alice:a")
    #expect(list.active?.slot == .legacy)
  }

  @Test func addingAnAccountMakesItActive() {
    var list = AccountList.migrated(nil, legacyUserId: "@alice:a")
    let slot = AccountSlot(id: "b")
    #expect(list.add(userId: "@bob:b", slot: slot) == .added)
    #expect(list.accounts.map(\.userId) == ["@alice:a", "@bob:b"])
    #expect(list.active?.userId == "@bob:b")
  }

  @Test func anAccountAlreadyAddedIsRefused() {
    var list = AccountList.migrated(nil, legacyUserId: "@alice:a")
    #expect(list.add(userId: "@alice:a", slot: AccountSlot(id: "b")) == .alreadyAdded)
    #expect(list.accounts.count == 1)
  }

  @Test func signingInAgainInTheSameSlotIsNotADuplicate() {
    var list = AccountList.migrated(nil, legacyUserId: "@alice:a")
    #expect(list.add(userId: "@alice:a", slot: .legacy) == .added)
    #expect(list.accounts.count == 1)
  }

  @Test func atMostFiveAccounts() {
    var list = AccountList()
    for index in 0..<AccountList.maximum {
      #expect(list.add(userId: "@u\(index):a", slot: AccountSlot(id: "\(index)")) == .added)
    }
    #expect(list.isFull)
    #expect(list.add(userId: "@extra:a", slot: AccountSlot(id: "extra")) == .full)
  }

  @Test func aSlotInUseIsRefused() {
    var list = AccountList.migrated(nil, legacyUserId: "@alice:a")
    #expect(list.add(userId: "@bob:b", slot: .legacy) == .full)
  }

  @Test func removingTheActiveAccountActivatesTheFirstOther() {
    var list = AccountList.migrated(nil, legacyUserId: "@alice:a")
    _ = list.add(userId: "@bob:b", slot: AccountSlot(id: "b"))
    #expect(list.remove(slot: AccountSlot(id: "b"))?.userId == "@bob:b")
    #expect(list.active?.userId == "@alice:a")
    #expect(list.remove(slot: .legacy) != nil)
    #expect(list.active == nil)
    #expect(list.remove(slot: AccountSlot(id: "none")) == nil)
  }

  @Test func signingOutADuplicateSignInKeepsTheAccountAlreadyListed() {
    var list = AccountList.migrated(nil, legacyUserId: "@alice:a")
    let duplicate = AccountSlot(id: "dup")
    #expect(list.add(userId: "@alice:a", slot: duplicate) == .alreadyAdded)
    #expect(list.remove(slot: duplicate) == nil)
    #expect(list.accounts == [AccountRecord(userId: "@alice:a", slot: .legacy)])
  }

  @Test func activatingOnlyKnownAccounts() {
    var list = AccountList.migrated(nil, legacyUserId: "@alice:a")
    _ = list.add(userId: "@bob:b", slot: AccountSlot(id: "b"))
    list.activate(userId: "@alice:a")
    #expect(list.active?.userId == "@alice:a")
    list.activate(userId: "@nobody:a")
    #expect(list.active?.userId == "@alice:a")
  }

  @Test func theSignInSlotIsTheLegacyOneWhileItIsFree() {
    #expect(AccountList().slotForSignIn() == .legacy)
    let list = AccountList.migrated(nil, legacyUserId: "@alice:a")
    #expect(list.slotForSignIn() != .legacy)
  }

  @Test func anUnknownActiveUserFallsBackToTheFirstAccount() {
    let list = AccountList(
      accounts: [AccountRecord(userId: "@a:a", slot: .legacy)], activeUserId: "@gone:a")
    #expect(list.activeUserId == "@a:a")
  }

  @Test func thePushAccountIsFoundByItsClientIdentifier() {
    var list = AccountList.migrated(nil, legacyUserId: "@alice:a")
    _ = list.add(userId: "@bob:b", slot: AccountSlot(id: "b"))
    let hash: (String) -> String = { "h" + $0 }
    #expect(list.account(clientIdentifier: "h@bob:b", hash: hash)?.slot == AccountSlot(id: "b"))
    #expect(list.account(clientIdentifier: "h@carol:c", hash: hash) == nil)
  }

  @Test func theRegistryRoundTripsAndMigratesOnce() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "AccountsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let registry = AccountRegistry(containerURL: root)
    #expect(registry.load() == nil)
    let migrated = registry.migrate(legacyUserId: "@alice:a")
    #expect(registry.load() == migrated)
    let change = registry.update { $0.add(userId: "@bob:b", slot: AccountSlot(id: "b")) }
    #expect(change == .added)
    #expect(registry.migrate(legacyUserId: "@alice:a").accounts.count == 2)
    #expect(registry.load()?.active?.userId == "@bob:b")
    #expect(
      registry.fileURL.path(percentEncoded: false).hasSuffix(
        "Library/Application Support/TwakeChat/accounts.json"))
  }

  @Test func anUnreadableRegistryReadsAsNone() throws {
    let root = FileManager.default.temporaryDirectory.appending(
      path: "AccountsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: root) }
    let registry = AccountRegistry(containerURL: root)
    try FileManager.default.createDirectory(
      at: registry.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("{".utf8).write(to: registry.fileURL)
    #expect(registry.load() == nil)
    #expect(registry.migrate(legacyUserId: "@alice:a").active?.slot == .legacy)
  }

  private func twoAccounts() -> AccountList {
    var list = AccountList.migrated(nil, legacyUserId: "@alice:a")
    _ = list.add(userId: "@bob:b", slot: AccountSlot(id: "b"))
    list.activate(userId: "@alice:a")
    return list
  }

  @Test func aPushBeforeAnyAccountIsListedUsesTheLegacySlot() {
    #expect(AccountList().slot(forPush: "x", hash: { $0 }) == .legacy)
    #expect(AccountList().slot(forPush: nil, hash: { $0 }) == .legacy)
  }

  @Test func aPushGoesToTheAccountItNames() {
    let list = twoAccounts()
    #expect(list.slot(forPush: "@bob:b", hash: { $0 }) == AccountSlot(id: "b"))
    #expect(list.slot(forPush: "@alice:a", hash: { $0 }) == .legacy)
  }

  @Test func aPushWithoutIdentifierGoesToTheAccountOnScreen() {
    #expect(twoAccounts().slot(forPush: nil, hash: { $0 }) == .legacy)
    #expect(twoAccounts().slot(forPush: "", hash: { $0 }) == .legacy)
  }

  @Test func aPushForAnAccountNotListedShowsNothing() {
    #expect(twoAccounts().slot(forPush: "@carol:c", hash: { $0 }) == nil)
  }

  @Test func notificationsNameTheirAccountOnlyWithSeveralAccounts() {
    #expect(
      AccountList.migrated(nil, legacyUserId: "@alice:a").notificationLabel(for: .legacy) == nil)
    #expect(twoAccounts().notificationLabel(for: AccountSlot(id: "b")) == "@bob:b")
    #expect(twoAccounts().notificationLabel(for: AccountSlot(id: "none")) == nil)
  }

  @Test func theAccountFollowsTheSubtitle() {
    #expect(AccountLabel.subtitle("Alice", account: "@me:a") == "Alice · @me:a")
    #expect(AccountLabel.subtitle("", account: "@me:a") == "@me:a")
    #expect(AccountLabel.subtitle("Alice", account: nil) == "Alice")
    #expect(AccountLabel.subtitle("Alice", account: "") == "Alice")
  }

  @Test func theShareAccountIsThePersonWhoIsTheUser() {
    #expect(
      AccountLabel.accountUserId(senderIsMe: true, senderId: "@me:a", meRecipientId: nil)
        == "@me:a")
    #expect(
      AccountLabel.accountUserId(senderIsMe: false, senderId: "@alice:a", meRecipientId: "@me:a")
        == "@me:a")
    #expect(
      AccountLabel.accountUserId(senderIsMe: false, senderId: "@alice:a", meRecipientId: nil)
        == nil)
    #expect(AccountLabel.accountUserId(senderIsMe: true, senderId: "", meRecipientId: nil) == nil)
  }

  @Test func theBadgeSumsEveryAccountsLastCount() throws {
    let suite = "AccountsTests-\(UUID().uuidString)"
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    let badges = try #require(AccountBadges(suiteName: suite))
    let list = twoAccounts()
    badges.record(3, for: .legacy)
    badges.record(4, for: AccountSlot(id: "b"))
    #expect(badges.total(for: list, including: .legacy) == 7)
    badges.record(-2, for: AccountSlot(id: "b"))
    #expect(badges.count(for: AccountSlot(id: "b")) == 0)
    badges.forget(.legacy)
    #expect(badges.total(for: list, including: .legacy) == 0)
  }

  @Test func theBadgeCountsTheSlotOfAPushNotListedYet() throws {
    let suite = "AccountsTests-\(UUID().uuidString)"
    defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    let badges = try #require(AccountBadges(suiteName: suite))
    badges.record(5, for: .legacy)
    #expect(badges.total(for: AccountList(), including: .legacy) == 5)
  }
}
