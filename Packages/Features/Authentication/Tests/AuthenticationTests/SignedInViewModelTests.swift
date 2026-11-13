import AuthenticationTestSupport
import Domain
import Foundation
import Testing

@testable import Authentication

@MainActor
struct SignedInViewModelTests {
  private let session = UserSession(
    userId: "@alice:example.org", deviceId: "DEVICE",
    homeserverURL: URL(string: "https://matrix.example.org")!,
    accessToken: "token", refreshToken: nil)

  @Test func showsTheUserId() {
    let viewModel = SignedInViewModel(
      session: session, repository: FakeAuthenticationRepository(), onLoggedOut: {})
    #expect(viewModel.userId == "@alice:example.org")
  }

  @Test func logOutCallsTheRepositoryThenReportsIt() async {
    let repository = FakeAuthenticationRepository()
    var loggedOut = 0
    let viewModel = SignedInViewModel(session: session, repository: repository) {
      #expect(repository.logoutCallCount == 1)
      loggedOut += 1
    }
    await viewModel.logOut()
    #expect(repository.logoutCallCount == 1)
    #expect(loggedOut == 1)
    #expect(!viewModel.isLoggingOut)
  }

  @Test func aSecondTapWhileLoggingOutIsIgnored() async {
    let repository = FakeAuthenticationRepository()
    repository.holdLogout()
    var loggedOut = 0
    let viewModel = SignedInViewModel(session: session, repository: repository) { loggedOut += 1 }
    let first = Task { await viewModel.logOut() }
    while repository.logoutCallCount == 0 { await Task.yield() }
    #expect(viewModel.isLoggingOut)
    await viewModel.logOut()
    #expect(repository.logoutCallCount == 1)
    #expect(loggedOut == 0)
    repository.releaseLogout()
    await first.value
    #expect(repository.logoutCallCount == 1)
    #expect(loggedOut == 1)
    #expect(!viewModel.isLoggingOut)
  }

  /// A failed logout keeps the signed-in screen with an error and asks the repository nothing else; trying again
  /// logs out.
  @Test(arguments: [AuthenticationError.serverUnreachable, .unknown])
  func aFailedLogoutStaysSignedInUntilTriedAgain(error: AuthenticationError) async {
    let repository = FakeAuthenticationRepository()
    repository.logoutResult = .failure(error)
    var loggedOut = 0
    let viewModel = SignedInViewModel(session: session, repository: repository) { loggedOut += 1 }
    await viewModel.logOut()
    #expect(repository.logoutCallCount == 1)
    #expect(repository.restoreCallCount == 0)
    #expect(loggedOut == 0)
    #expect(viewModel.errorMessage == "Could not log out. Please try again.")
    #expect(!viewModel.isLoggingOut)

    repository.logoutResult = .success(())
    await viewModel.logOut()
    #expect(repository.logoutCallCount == 2)
    #expect(loggedOut == 1)
    #expect(viewModel.errorMessage == nil)
  }
}
