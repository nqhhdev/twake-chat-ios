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
  /// The same session from a token (SSO) sign-in on a homeserver whose `.well-known` names an SSO issuer.
  private let ssoSession = UserSession(
    userId: "@alice:example.org", deviceId: "DEVICE",
    homeserverURL: URL(string: "https://matrix.example.org")!,
    accessToken: "token", refreshToken: nil,
    authenticationIssuer: URL(string: "https://sign-up.example.org/")!)

  @Test func showsTheUserId() {
    let viewModel = SignedInViewModel(
      session: session, repository: FakeAuthenticationRepository(),
      webAuthenticator: FakeWebAuthenticator(), onLoggedOut: {})
    #expect(viewModel.userId == "@alice:example.org")
  }

  @Test func logOutCallsTheRepositoryThenReportsIt() async {
    let repository = FakeAuthenticationRepository()
    var loggedOut = 0
    let viewModel = SignedInViewModel(
      session: session, repository: repository, webAuthenticator: FakeWebAuthenticator()
    ) {
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
    let viewModel = SignedInViewModel(
      session: session, repository: repository, webAuthenticator: FakeWebAuthenticator()
    ) { loggedOut += 1 }
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
    let viewModel = SignedInViewModel(
      session: session, repository: repository, webAuthenticator: FakeWebAuthenticator()
    ) { loggedOut += 1 }
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

  /// After a token sign-in, log out opens `<issuer>?logout=1` once the Matrix logout is done, and only then shows
  /// TwakeWelcome (connect_page_mixin.dart `tryLogoutSso`).
  @Test func aTokenSignInOpensTheSSOLogoutPageAfterTheMatrixLogout() async {
    let repository = FakeAuthenticationRepository()
    let web = FakeWebAuthenticator()
    var loggedOut = 0
    let viewModel = SignedInViewModel(
      session: ssoSession, repository: repository, webAuthenticator: web
    ) {
      #expect(web.calls.count == 1)
      loggedOut += 1
    }
    await viewModel.logOut()
    #expect(repository.logoutCallCount == 1)
    #expect(
      web.calls == [
        .init(
          url: URL(string: "https://sign-up.example.org/?logout=1")!, callbackScheme: "twake.chat")
      ])
    #expect(loggedOut == 1)
    #expect(!viewModel.isLoggingOut)
  }

  /// A password sign-in logs out as before: no web page.
  @Test func aPasswordSignInOpensNoPage() async {
    let repository = FakeAuthenticationRepository()
    let web = FakeWebAuthenticator()
    var loggedOut = 0
    let viewModel = SignedInViewModel(
      session: session, repository: repository, webAuthenticator: web
    ) {
      loggedOut += 1
    }
    await viewModel.logOut()
    #expect(repository.logoutCallCount == 1)
    #expect(web.calls.isEmpty)
    #expect(loggedOut == 1)
  }

  /// The logout page usually does not call back: closing it, or a session that fails, still ends signed out.
  @Test(arguments: [WebAuthenticationError.cancelled, .failed])
  func closingTheSSOLogoutPageStillLogsOut(error: WebAuthenticationError) async {
    let web = FakeWebAuthenticator()
    web.result = .failure(error)
    var loggedOut = 0
    let viewModel = SignedInViewModel(
      session: ssoSession, repository: FakeAuthenticationRepository(), webAuthenticator: web
    ) { loggedOut += 1 }
    await viewModel.logOut()
    #expect(web.calls.count == 1)
    #expect(loggedOut == 1)
    #expect(viewModel.errorMessage == nil)
  }

  /// While the Matrix logout fails the user is still signed in, so the SSO session is kept; trying again ends both.
  @Test func aFailedMatrixLogoutOpensNoPageUntilTriedAgain() async {
    let repository = FakeAuthenticationRepository()
    repository.logoutResult = .failure(.serverUnreachable)
    let web = FakeWebAuthenticator()
    var loggedOut = 0
    let viewModel = SignedInViewModel(
      session: ssoSession, repository: repository, webAuthenticator: web
    ) { loggedOut += 1 }
    await viewModel.logOut()
    #expect(web.calls.isEmpty)
    #expect(loggedOut == 0)

    repository.logoutResult = .success(())
    await viewModel.logOut()
    #expect(web.calls.count == 1)
    #expect(loggedOut == 1)
  }

  @Test func theSSOLogoutURLAddsLogoutToTheIssuer() {
    #expect(
      SignInConfiguration.ssoLogoutURL(issuer: URL(string: "https://sign-up.stg.lin-saas.com/")!)
        == URL(string: "https://sign-up.stg.lin-saas.com/?logout=1"))
    #expect(
      SignInConfiguration.ssoLogoutURL(issuer: URL(string: "https://sso.example.org/auth?realm=a")!)
        == URL(string: "https://sso.example.org/auth?realm=a&logout=1"))
  }
}
