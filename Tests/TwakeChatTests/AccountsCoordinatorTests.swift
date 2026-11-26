import AppShared
import AuthenticationTestSupport
import Foundation
import MatrixData
import Testing

@testable import TwakeChat

@MainActor
struct AccountsCoordinatorTests {
  @MainActor
  private final class Roots {
    var made:
      [(slot: AccountSlot, root: RootCoordinator, repository: FakeAuthenticationRepository)] =
        []

    func make(_ slot: AccountSlot, _ change: @escaping @Sendable (SessionChange) -> Void)
      -> RootCoordinator
    {
      let repository = FakeAuthenticationRepository()
      let root = RootCoordinator(repository: repository, defaultHomeserver: nil)
      made.append((slot, root, repository))
      return root
    }
  }

  private let root: URL
  private let registry: AccountRegistry

  init() {
    root = FileManager.default.temporaryDirectory.appending(
      path: "AccountsCoordinatorTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    registry = AccountRegistry(containerURL: root)
  }

  private func cleanUp() {
    try? FileManager.default.removeItem(at: root)
  }

  private func coordinator(_ roots: Roots, legacyUserId: String? = "@alice:a")
    -> AccountsCoordinator
  {
    AccountsCoordinator(registry: registry, legacyUserId: legacyUserId, makeRoot: roots.make)
  }

  @Test func theSignedInSingleAccountOpensInItsOwnSlot() {
    defer { cleanUp() }
    let roots = Roots()
    let accounts = coordinator(roots)
    #expect(accounts.rootSlot == .legacy)
    #expect(accounts.activeUserId == "@alice:a")
    #expect(registry.load()?.accounts.map(\.userId) == ["@alice:a"])
    #expect(AppDelegate.push === accounts.root.push)
  }

  @Test func aFirstLaunchSignsInInTheLegacySlot() {
    defer { cleanUp() }
    let accounts = coordinator(Roots(), legacyUserId: nil)
    #expect(accounts.rootSlot == .legacy)
    #expect(accounts.activeUserId == nil)
    #expect(accounts.list.accounts.isEmpty)
  }

  @Test func aSignInInTheRootSlotListsTheAccount() async {
    defer { cleanUp() }
    let accounts = coordinator(Roots(), legacyUserId: nil)
    await accounts.sessionChanged(.signedIn(userId: "@alice:a"), in: .legacy)
    #expect(accounts.activeUserId == "@alice:a")
    #expect(accounts.adding == nil)
  }

  @Test func anAddedAccountComesOnScreenInAFreshSlot() async throws {
    defer { cleanUp() }
    let roots = Roots()
    let accounts = coordinator(roots)
    let first = accounts.root
    accounts.startAddingAccount()
    let slot = try #require(accounts.addingSlot)
    #expect(!slot.isLegacy)
    let adding = try #require(accounts.adding)
    await accounts.sessionChanged(.signedIn(userId: "@bob:b"), in: slot)
    #expect(accounts.root === adding)
    #expect(accounts.root !== first)
    #expect(accounts.rootSlot == slot)
    #expect(accounts.adding == nil)
    #expect(accounts.list.accounts.map(\.userId) == ["@alice:a", "@bob:b"])
    #expect(accounts.activeUserId == "@bob:b")
  }

  @Test func anAccountAlreadyListedIsSignedOutAgainAndNamed() async throws {
    defer { cleanUp() }
    let roots = Roots()
    let accounts = coordinator(roots)
    let first = accounts.root
    accounts.startAddingAccount()
    let slot = try #require(accounts.addingSlot)
    await accounts.sessionChanged(.signedIn(userId: "@alice:a"), in: slot)
    #expect(accounts.notice == .alreadyAdded("@alice:a"))
    #expect(accounts.root === first)
    #expect(accounts.adding == nil)
    #expect(roots.made.last?.repository.logoutCallCount == 1)
    await accounts.sessionChanged(.signedOut(userId: "@alice:a"), in: slot)
    #expect(accounts.list.accounts.map(\.userId) == ["@alice:a"])
    #expect(accounts.root === first)
  }

  @Test func noAccountIsAddedPastTheMaximum() async throws {
    defer { cleanUp() }
    let accounts = coordinator(Roots())
    for index in 1..<AccountList.maximum {
      accounts.startAddingAccount()
      let slot = try #require(accounts.addingSlot)
      await accounts.sessionChanged(.signedIn(userId: "@u\(index):a"), in: slot)
    }
    #expect(accounts.list.isFull)
    #expect(!accounts.canAddAccount)
    accounts.startAddingAccount()
    #expect(accounts.adding == nil)
  }

  @Test func switchingBuildsTheOtherAccountsRoot() async throws {
    defer { cleanUp() }
    let roots = Roots()
    let accounts = coordinator(roots)
    accounts.startAddingAccount()
    let slot = try #require(accounts.addingSlot)
    await accounts.sessionChanged(.signedIn(userId: "@bob:b"), in: slot)
    accounts.switchTo(userId: "@alice:a")
    #expect(accounts.rootSlot == .legacy)
    #expect(accounts.activeUserId == "@alice:a")
    #expect(registry.load()?.active?.userId == "@alice:a")
    #expect(roots.made.last?.slot == .legacy)
    let count = roots.made.count
    accounts.switchTo(userId: "@alice:a")
    accounts.switchTo(userId: "@nobody:a")
    #expect(roots.made.count == count)
  }

  @Test func signingOutOfTheAccountOnScreenOpensTheNextOne() async throws {
    defer { cleanUp() }
    let accounts = coordinator(Roots())
    accounts.startAddingAccount()
    let slot = try #require(accounts.addingSlot)
    await accounts.sessionChanged(.signedIn(userId: "@bob:b"), in: slot)
    await accounts.sessionChanged(.signedOut(userId: "@bob:b"), in: slot)
    #expect(accounts.rootSlot == .legacy)
    #expect(accounts.activeUserId == "@alice:a")
    #expect(accounts.list.accounts.map(\.userId) == ["@alice:a"])
  }

  @Test func signingOutOfTheLastAccountStaysOnItsSignInScreen() async {
    defer { cleanUp() }
    let accounts = coordinator(Roots())
    let only = accounts.root
    await accounts.sessionChanged(.signedOut(userId: "@alice:a"), in: .legacy)
    #expect(accounts.root === only)
    #expect(accounts.list.accounts.isEmpty)
  }

  @Test func cancellingAnAdditionDeletesWhatItsSlotHolds() async throws {
    defer { cleanUp() }
    let accounts = coordinator(Roots())
    accounts.startAddingAccount()
    let slot = try #require(accounts.addingSlot)
    let store = registry.storeDirectory(for: slot)
    try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
    await accounts.cancelAddingAccount()
    #expect(accounts.adding == nil)
    #expect(!FileManager.default.fileExists(atPath: store.path(percentEncoded: false)))
    #expect(accounts.list.accounts.map(\.userId) == ["@alice:a"])
  }

  @Test func theNoticesSayWhatHappened() {
    #expect(
      AccountsCoordinator.Notice.alreadyAdded("@a:b").message
        == "@a:b is already signed in on this device.")
    #expect(AccountsCoordinator.Notice.full.message == "You can add up to 5 accounts.")
  }
}
