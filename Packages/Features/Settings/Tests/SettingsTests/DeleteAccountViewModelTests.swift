import Domain
import Foundation
import Testing

@testable import Settings

struct FixedCapabilities: ServerCapabilitiesRepository {
  let value: ServerCapabilities
  func current() async -> ServerCapabilities { value }
  func refresh() async -> ServerCapabilities { value }
}

@MainActor
struct DeleteAccountViewModelTests {
  private final class Deletion: AccountDeletionRepository, @unchecked Sendable {
    var answers: [Result<AccountDeletion, DevicesError>] = []
    var auths: [DeviceAuth?] = []

    func deactivateAccount(auth: DeviceAuth?) async throws(DevicesError) -> AccountDeletion {
      auths.append(auth)
      return try answers.removeFirst().get()
    }
  }

  private final class SignOuts {
    var count = 0
  }

  private let challenge = DeviceAuthChallenge(
    session: "s1", webURL: URL(string: "https://matrix.example.org/sso"), acceptsPassword: true)

  private func viewModel(
    _ deletion: Deletion, _ signOuts: SignOuts,
    capabilities: ServerCapabilities = .none
  ) -> DeleteAccountViewModel {
    DeleteAccountViewModel(
      userId: "@alice:example.org", capabilities: FixedCapabilities(value: capabilities),
      repository: deletion, signOut: { signOuts.count += 1 })
  }

  @Test func aTwakeServerSendsTheUserToTheCommonSettingsPage() async {
    let model = viewModel(
      Deletion(), SignOuts(),
      capabilities: ServerCapabilities(
        twakeChat: .init(commonSettingsURL: "https://settings.example.org/{username}")))
    await model.load()
    #expect(model.route == .commonSettings(URL(string: "https://settings.example.org/alice")!))
  }

  @Test func anotherServerDeactivatesThroughMatrix() async {
    let model = viewModel(Deletion(), SignOuts())
    await model.load()
    #expect(model.route == .matrix)
  }

  @Test func theServerConfirmationIsAskedThenTheAccountIsDeletedAndSignedOut() async {
    let deletion = Deletion()
    deletion.answers = [.success(.needsConfirmation(challenge)), .success(.done)]
    let signOuts = SignOuts()
    let model = viewModel(deletion, signOuts)
    await model.delete()
    #expect(model.challenge == challenge)
    #expect(signOuts.count == 0)
    await model.confirm(password: "secret")
    #expect(deletion.auths == [nil, .password("secret", session: "s1")])
    #expect(model.challenge == nil)
    #expect(signOuts.count == 1)
  }

  @Test func confirmingOnTheWebPageRetriesWithTheSession() async {
    let deletion = Deletion()
    deletion.answers = [.success(.needsConfirmation(challenge)), .success(.done)]
    let model = viewModel(deletion, SignOuts())
    await model.delete()
    await model.confirm()
    #expect(deletion.auths.last == .confirmedOnWeb(session: "s1"))
  }

  @Test func aRefusedConfirmationOrAFailureIsReportedAndKeepsTheSession() async {
    let deletion = Deletion()
    deletion.answers = [
      .success(.needsConfirmation(challenge)), .success(.needsConfirmation(challenge)),
      .failure(.requestFailed),
    ]
    let signOuts = SignOuts()
    let model = viewModel(deletion, signOuts)
    await model.delete()
    await model.confirm(password: "wrong")
    #expect(model.errorMessage == "Could not confirm it is you. Please try again.")
    await model.delete()
    #expect(model.errorMessage == "Could not delete your account.")
    #expect(signOuts.count == 0)
  }
}
