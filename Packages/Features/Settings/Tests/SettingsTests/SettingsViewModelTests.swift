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

  @Test func aRightRecoveryKeyUnlocksOldMessages() async {
    let repository = FakeAccountSettingsRepository()
    repository.status = .incomplete
    let viewModel = viewModel(repository)
    await viewModel.recover(with: "EsTc abcd")
    #expect(viewModel.didRecover)
    #expect(viewModel.recoveryStatus == .enabled)
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
}
