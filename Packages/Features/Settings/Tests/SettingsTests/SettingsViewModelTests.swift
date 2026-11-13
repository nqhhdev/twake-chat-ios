import Domain
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
}
