import AuthenticationTestSupport
import Domain
import Foundation
import Testing

@testable import Authentication

@MainActor
struct AuthenticationCoordinatorTests {
  private let homeserver = URL(string: "https://matrix.example.org")!
  private let session = UserSession(
    userId: "@alice:example.org", deviceId: "DEVICE",
    homeserverURL: URL(string: "https://matrix.example.org")!,
    accessToken: "token", refreshToken: nil)

  private func passwordLogin(_ coordinator: AuthenticationCoordinator) -> PasswordLoginViewModel? {
    if case .passwordLogin(let viewModel) = coordinator.screen { viewModel } else { nil }
  }

  private func signedIn(_ coordinator: AuthenticationCoordinator) -> SignedInViewModel? {
    if case .signedIn(let viewModel) = coordinator.screen { viewModel } else { nil }
  }

  @Test func noSessionStartsOnThePrefilledForm() {
    let coordinator = AuthenticationCoordinator(
      repository: FakeAuthenticationRepository(), defaultHomeserver: homeserver, session: nil)
    #expect(passwordLogin(coordinator)?.homeserver == "https://matrix.example.org")
  }

  @Test func aRestoredSessionStartsSignedIn() {
    let coordinator = AuthenticationCoordinator(
      repository: FakeAuthenticationRepository(), defaultHomeserver: homeserver, session: session)
    #expect(signedIn(coordinator)?.userId == "@alice:example.org")
  }

  @Test func signingInShowsTheSignedInScreenAndLoggingOutReturnsToTheForm() async throws {
    let repository = FakeAuthenticationRepository()
    repository.loginResult = .success(session)
    let coordinator = AuthenticationCoordinator(
      repository: repository, defaultHomeserver: homeserver, session: nil)

    let form = try #require(passwordLogin(coordinator))
    form.username = "alice"
    form.password = "secret"
    await form.signIn()
    let signedInScreen = try #require(signedIn(coordinator))
    #expect(signedInScreen.userId == "@alice:example.org")

    await signedInScreen.logOut()
    #expect(repository.logoutCallCount == 1)
    let newForm = try #require(passwordLogin(coordinator))
    #expect(newForm !== form)
    #expect(newForm.username.isEmpty)
    #expect(newForm.password.isEmpty)
    #expect(newForm.homeserver == "https://matrix.example.org")
  }

  @Test func loggingOutOfARestoredSessionReturnsToTheForm() async throws {
    let repository = FakeAuthenticationRepository()
    let coordinator = AuthenticationCoordinator(
      repository: repository, defaultHomeserver: homeserver, session: session)
    let signedInScreen = try #require(signedIn(coordinator))
    await signedInScreen.logOut()
    #expect(repository.logoutCallCount == 1)
    #expect(passwordLogin(coordinator) != nil)
  }

  /// The form shown after a logout must sign in again: its callback is wired differently from the first form's.
  @Test func signingInAgainAfterLoggingOutShowsTheSignedInScreen() async throws {
    let repository = FakeAuthenticationRepository()
    repository.loginResult = .success(session)
    let coordinator = AuthenticationCoordinator(
      repository: repository, defaultHomeserver: homeserver, session: nil)

    for round in 1...2 {
      let form = try #require(passwordLogin(coordinator), "round \(round)")
      form.username = "alice"
      form.password = "secret"
      await form.signIn()
      let signedInScreen = try #require(signedIn(coordinator), "round \(round)")
      await signedInScreen.logOut()
    }
    #expect(repository.loginCalls.count == 2)
    #expect(repository.logoutCallCount == 2)
    #expect(passwordLogin(coordinator) != nil)
  }

  @Test func aRestoredSessionCanLogOutThenSignInAgain() async throws {
    let repository = FakeAuthenticationRepository()
    let other = UserSession(
      userId: "@bob:example.org", deviceId: "DEVICE2", homeserverURL: homeserver,
      accessToken: "token2", refreshToken: nil)
    repository.loginResult = .success(other)
    let coordinator = AuthenticationCoordinator(
      repository: repository, defaultHomeserver: homeserver, session: session)

    try await #require(signedIn(coordinator)).logOut()
    let form = try #require(passwordLogin(coordinator))
    form.username = "bob"
    form.password = "secret"
    await form.signIn()
    #expect(signedIn(coordinator)?.userId == "@bob:example.org")
  }

  @Test func aFailedLogoutStaysSignedIn() async throws {
    let repository = FakeAuthenticationRepository()
    repository.logoutResult = .failure(.serverUnreachable)
    let coordinator = AuthenticationCoordinator(
      repository: repository, defaultHomeserver: homeserver, session: session)
    let screen = try #require(signedIn(coordinator))
    await screen.logOut()
    #expect(repository.logoutCallCount == 1)
    #expect(signedIn(coordinator) === screen)
    #expect(passwordLogin(coordinator) == nil)
  }

  @Test func aFailedSignInStaysOnTheForm() async throws {
    let repository = FakeAuthenticationRepository()
    repository.loginResult = .failure(.invalidCredentials)
    let coordinator = AuthenticationCoordinator(
      repository: repository, defaultHomeserver: homeserver, session: nil)
    let form = try #require(passwordLogin(coordinator))
    form.username = "alice"
    form.password = "wrong"
    await form.signIn()
    #expect(passwordLogin(coordinator) === form)
  }
}
