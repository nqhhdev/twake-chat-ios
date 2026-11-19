import DesignSystem
import Domain
import Foundation
import SettingsTestSupport
import Testing

@testable import Settings

@MainActor
struct SettingsViewModelTests {
  private func viewModel(_ repository: FakeAccountSettingsRepository, logOut: Bool = true)
    -> SettingsViewModel
  {
    SettingsViewModel(userId: "@alice:example.org", repository: repository) { logOut }
  }

  @Test func loadsTheProfileRecoveryAndNotificationDefaults() async {
    let repository = FakeAccountSettingsRepository()
    repository.name = "Alice Martin"
    repository.status = .incomplete
    try? await repository.setDefaultNotificationMode(.mute, isDirect: false)
    let viewModel = viewModel(repository)
    #expect(viewModel.displayName == "alice")
    await viewModel.load()
    #expect(viewModel.displayName == "Alice Martin")
    #expect(viewModel.recoveryStatus == .incomplete)
    #expect(viewModel.groupMode == .mute)
    #expect(viewModel.directMode == .allMessages)
  }

  @Test func aFailedProfileReadIsTriedAgainUntilTheNameLoads() async {
    let repository = FakeAccountSettingsRepository()
    repository.name = "Alice Martin"
    repository.nameFailures = 2
    let viewModel = viewModel(repository)
    viewModel.profileRetryDelays = [.zero, .zero]
    await viewModel.load()
    #expect(viewModel.displayName == "Alice Martin")
    #expect(repository.nameReads == 3)
  }

  @Test func aProfileReadThatKeepsFailingStopsAfterTheRetriesAndKeepsTheLastName() async {
    let repository = FakeAccountSettingsRepository()
    repository.name = "Alice Martin"
    let viewModel = viewModel(repository)
    viewModel.profileRetryDelays = [.zero, .zero]
    await viewModel.load()
    repository.name = "Alice M."
    repository.nameFailures = 10
    await viewModel.refreshDisplayName()
    #expect(viewModel.displayName == "Alice Martin")
    #expect(repository.nameReads == 4)
  }

  @Test func refreshingPicksUpANameChangedElsewhere() async {
    let repository = FakeAccountSettingsRepository()
    repository.name = "Alice Martin"
    let viewModel = viewModel(repository)
    await viewModel.load()
    repository.name = "Alice M."
    await viewModel.refreshDisplayName()
    #expect(viewModel.displayName == "Alice M.")
  }

  @Test func aProfileWithoutANameShowsTheLocalpart() async {
    let repository = FakeAccountSettingsRepository()
    repository.name = "Alice Martin"
    let viewModel = viewModel(repository)
    await viewModel.load()
    repository.name = nil
    await viewModel.refreshDisplayName()
    #expect(viewModel.displayName == "alice")
  }

  @Test func aRightRecoveryKeyUnlocksOldMessages() async {
    let repository = FakeAccountSettingsRepository()
    repository.status = .incomplete
    let viewModel = viewModel(repository)
    final class Flag: @unchecked Sendable { var value = false }
    let imported = Flag()
    let token = NotificationCenter.default.addObserver(
      forName: .encryptionKeysImported, object: nil, queue: nil
    ) { _ in imported.value = true }
    defer { NotificationCenter.default.removeObserver(token) }
    await viewModel.recover(with: "EsTc abcd")
    #expect(viewModel.didRecover)
    #expect(viewModel.recoveryStatus == .enabled)
    #expect(imported.value)
  }

  @Test func aWrongRecoveryKeySaysSo() async {
    let repository = FakeAccountSettingsRepository()
    repository.recoverResult = .failure(.wrongRecoveryKey)
    let viewModel = viewModel(repository)
    await viewModel.recover(with: "nope")
    #expect(!viewModel.didRecover)
    #expect(viewModel.errorMessage == "Wrong recovery key")
  }

  @Test func settingUpBackupShowsTheNewKeyOnce() async {
    let repository = FakeAccountSettingsRepository()
    let viewModel = viewModel(repository)
    await viewModel.enableRecovery()
    #expect(viewModel.newRecoveryKey == "EsTc abcd")
    viewModel.dismissNewRecoveryKey()
    #expect(viewModel.newRecoveryKey == nil)
  }

  @Test func aFailedNotificationChangeGoesBack() async {
    let repository = FakeAccountSettingsRepository()
    repository.setModeResult = .failure(.requestFailed)
    let viewModel = viewModel(repository)
    await viewModel.setNotificationMode(.mute, isDirect: true)
    #expect(viewModel.directMode == .allMessages)
    #expect(viewModel.errorMessage != nil)
  }

  @Test func aFailedLogoutShowsAMessage() async {
    let viewModel = viewModel(FakeAccountSettingsRepository(), logOut: false)
    await viewModel.logOut()
    #expect(viewModel.errorMessage == "Could not log out. Please try again.")
  }

  @Test func renamingChangesTheDisplayName() async {
    let repository = FakeAccountSettingsRepository()
    let viewModel = viewModel(repository)
    #expect(await viewModel.rename(to: "  Alice M.  "))
    #expect(viewModel.displayName == "Alice M.")
    #expect(repository.name == "Alice M.")
  }

  @Test func aFailedRenameKeepsTheOldName() async {
    let repository = FakeAccountSettingsRepository()
    repository.setNameResult = .failure(.requestFailed)
    let viewModel = viewModel(repository)
    let before = viewModel.displayName
    #expect(await viewModel.rename(to: "New") == false)
    #expect(viewModel.displayName == before)
    #expect(viewModel.errorMessage != nil)
  }

  @Test func blockedPeopleLoadAndUnblockingTakesThemOff() async {
    let repository = FakeAccountSettingsRepository()
    let bob = BlockedUser(id: "@bob:example.org", displayName: "Bob")
    let eve = BlockedUser(id: "@eve:example.org", displayName: nil)
    repository.blocked = [bob, eve]
    let viewModel = viewModel(repository)
    await viewModel.loadBlockedUsers()
    #expect(viewModel.blockedUsers == [bob, eve])
    await viewModel.unblock(bob)
    #expect(viewModel.blockedUsers == [eve])
    #expect(repository.blocked == [eve])
    #expect(eve.name == "@eve:example.org")
  }

  private let picture = PreparedPicture(jpeg: Data([1, 2, 3]), side: 512)

  @Test func choosingAPictureUploadsItAndShowsTheNewAvatar() async {
    let repository = FakeAccountSettingsRepository()
    let viewModel = viewModel(repository)
    await viewModel.setPicture(picture)
    #expect(repository.uploads.map(\.mimeType) == ["image/jpeg"])
    #expect(repository.uploads.first?.width == 512)
    #expect(viewModel.avatar?.source == "mxc://example.org/avatar1")
    #expect(viewModel.isUpdatingPicture == false)
    await viewModel.removePicture()
    #expect(viewModel.avatar == nil)
  }

  @Test func aFailedPictureChangeKeepsTheAvatarAndSaysSo() async {
    let repository = FakeAccountSettingsRepository()
    repository.avatarResult = .failure(.requestFailed)
    let viewModel = viewModel(repository)
    await viewModel.setPicture(picture)
    #expect(viewModel.avatar == nil)
    #expect(viewModel.errorMessage == "Could not change your picture. Please try again.")
  }
}

/// The Chat page: which room events chats show, saved on the device at each change.
@MainActor
struct ChatDisplaySettingsPageTests {
  private final class Store: ChatDisplaySettingsStore, @unchecked Sendable {
    var stored: ChatDisplaySettings
    var saves = 0
    init(_ stored: ChatDisplaySettings) { self.stored = stored }
    func load() -> ChatDisplaySettings { stored }
    func save(_ settings: ChatDisplaySettings) {
      stored = settings
      saves += 1
    }
  }

  @Test func theSavedChoiceShowsAndAChangeIsSaved() {
    let store = Store(ChatDisplaySettings(hidesUnimportantEvents: false))
    let viewModel = SettingsViewModel(
      userId: "@alice:example.org", repository: FakeAccountSettingsRepository(),
      chatDisplay: store
    ) { true }
    #expect(viewModel.hasChatPage)
    #expect(viewModel.chatDisplay.hidesUnimportantEvents == false)
    viewModel.chatDisplay.hidesUnknownEvents = false
    #expect(
      store.stored == ChatDisplaySettings(hidesUnimportantEvents: false, hidesUnknownEvents: false))
    viewModel.chatDisplay.hidesUnknownEvents = false
    #expect(store.saves == 1)
  }

  @Test func withoutAStoreThereIsNoChatPage() {
    let viewModel = SettingsViewModel(
      userId: "@alice:example.org", repository: FakeAccountSettingsRepository()
    ) { true }
    #expect(!viewModel.hasChatPage)
    #expect(viewModel.chatDisplay == ChatDisplaySettings())
  }

  @Test func resettingTheIdentityAsksForThePasswordThenFinishes() async {
    let repository = FakeAccountSettingsRepository()
    let settings = SettingsViewModel(userId: "@alice:example.org", repository: repository) { true }
    await settings.startIdentityReset()
    #expect(settings.identityReset == .password)
    await settings.finishIdentityReset(password: "secret")
    #expect(repository.resetPassword == "secret")
    #expect(settings.identityReset == nil)
    #expect(settings.didResetIdentity)
  }

  @Test func theContactsVisibilityChangesAndGoesBackWhenRefused() async {
    let repository = FakeAccountSettingsRepository()
    let settings = SettingsViewModel(userId: "@alice:example.org", repository: repository) { true }
    await settings.loadContactsVisibility()
    #expect(settings.contactsVisibility == .contacts)
    await settings.setContactsVisibility(.everyone)
    #expect(repository.visibility == .everyone)
    repository.visibilityFails = true
    await settings.setContactsVisibility(.nobody)
    #expect(settings.contactsVisibility == .everyone)
    #expect(settings.errorMessage == "Could not change who sees your e-mail and phone.")
  }

  @Test func clearingTheCacheShowsTheNewSize() async {
    let repository = FakeAccountSettingsRepository()
    let settings = SettingsViewModel(userId: "@alice:example.org", repository: repository) { true }
    await settings.loadCacheSize()
    #expect(settings.cacheSize == 2_048)
    await settings.clearCache()
    #expect(settings.cacheSize == 0)
    #expect(settings.errorMessage == nil)
  }

  @Test func theStatusMessageIsTrimmedAndClearedWhenEmpty() async {
    let repository = FakeAccountSettingsRepository()
    let settings = SettingsViewModel(userId: "@alice:example.org", repository: repository) { true }
    await settings.setStatusMessage("  In a meeting ")
    #expect(settings.statusMessage == "In a meeting")
    #expect(repository.statusText == "In a meeting")
    await settings.setStatusMessage("")
    #expect(settings.statusMessage == nil)
    #expect(repository.statusText == nil)
  }
}
