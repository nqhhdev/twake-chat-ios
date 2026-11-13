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

  private func coordinator(
    _ repository: FakeAuthenticationRepository, session: UserSession? = nil,
    web: FakeWebAuthenticator = FakeWebAuthenticator()
  ) -> AuthenticationCoordinator {
    AuthenticationCoordinator(
      repository: repository,
      configuration: SignInConfiguration(
        registrationURL: URL(string: "https://sign-up.example.org/"),
        workplaceHomeserver: URL(string: "https://tom.example.org/"), defaultHomeserver: homeserver,
        privacyURL: URL(string: "https://twake.app/policy")!),
      webAuthenticator: web, session: session)
  }

  private func welcome(_ coordinator: AuthenticationCoordinator) -> TwakeWelcomeViewModel? {
    if case .welcome(let viewModel) = coordinator.screen { viewModel } else { nil }
  }

  private func picker(_ coordinator: AuthenticationCoordinator) -> HomeserverPickerViewModel? {
    if case .homeserverPicker(let viewModel) = coordinator.screen { viewModel } else { nil }
  }

  private func signedIn(_ coordinator: AuthenticationCoordinator) -> SignedInViewModel? {
    if case .signedIn(let viewModel) = coordinator.screen { viewModel } else { nil }
  }

  /// TwakeWelcome → company server → Continue on a password-only server → the password form.
  private func passwordForm(_ coordinator: AuthenticationCoordinator) async
    -> PasswordLoginViewModel?
  {
    welcome(coordinator)?.useCompanyServer()
    await picker(coordinator)?.continueTapped()
    if case .passwordLogin(let viewModel) = coordinator.screen { return viewModel }
    return nil
  }

  @Test func noSessionStartsOnTwakeWelcome() {
    #expect(welcome(coordinator(FakeAuthenticationRepository())) != nil)
  }

  @Test func aRestoredSessionStartsSignedIn() {
    let coordinator = coordinator(FakeAuthenticationRepository(), session: session)
    #expect(signedIn(coordinator)?.userId == "@alice:example.org")
  }

  @Test func theCompanyServerPickerIsPrefilledAndGoesBackToWelcome() throws {
    let coordinator = coordinator(FakeAuthenticationRepository())
    try #require(welcome(coordinator)).useCompanyServer()
    let picker = try #require(picker(coordinator))
    #expect(picker.server == "matrix.example.org")
    picker.back()
    #expect(welcome(coordinator) != nil)
  }

  @Test func aPasswordOnlyServerShowsThePasswordFormThatGoesBackToThePicker() async throws {
    let repository = FakeAuthenticationRepository()
    let coordinator = coordinator(repository)
    let form = try #require(await passwordForm(coordinator))
    #expect(repository.loginOptionsCalls == ["matrix.example.org"])
    #expect(form.homeserver == "https://matrix.example.org")
    #expect(form.canGoBack)
    form.back()
    #expect(picker(coordinator) != nil)
  }

  @Test func signingInShowsTheSignedInScreenAndLoggingOutReturnsToWelcome() async throws {
    let repository = FakeAuthenticationRepository()
    repository.loginResult = .success(session)
    let coordinator = coordinator(repository)

    let form = try #require(await passwordForm(coordinator))
    form.username = "alice"
    form.password = "secret"
    await form.signIn()
    let signedInScreen = try #require(signedIn(coordinator))
    #expect(signedInScreen.userId == "@alice:example.org")

    await signedInScreen.logOut()
    #expect(repository.logoutCallCount == 1)
    #expect(welcome(coordinator) != nil)
  }

  /// The screens shown after a logout must sign in again: their callbacks are wired again.
  @Test func signingInAgainAfterLoggingOutShowsTheSignedInScreen() async throws {
    let repository = FakeAuthenticationRepository()
    repository.loginResult = .success(session)
    let coordinator = coordinator(repository)

    for round in 1...2 {
      let form = try #require(await passwordForm(coordinator), "round \(round)")
      form.username = "alice"
      form.password = "secret"
      await form.signIn()
      let signedInScreen = try #require(signedIn(coordinator), "round \(round)")
      await signedInScreen.logOut()
    }
    #expect(repository.loginCalls.count == 2)
    #expect(repository.logoutCallCount == 2)
    #expect(welcome(coordinator) != nil)
  }

  @Test func aFailedLogoutStaysSignedIn() async throws {
    let repository = FakeAuthenticationRepository()
    repository.logoutResult = .failure(.serverUnreachable)
    let coordinator = coordinator(repository, session: session)
    let screen = try #require(signedIn(coordinator))
    await screen.logOut()
    #expect(repository.logoutCallCount == 1)
    #expect(signedIn(coordinator) === screen)
  }

  @Test func aFailedSignInStaysOnTheForm() async throws {
    let repository = FakeAuthenticationRepository()
    repository.loginResult = .failure(.invalidCredentials)
    let coordinator = coordinator(repository)
    let form = try #require(await passwordForm(coordinator))
    form.username = "alice"
    form.password = "wrong"
    await form.signIn()
    if case .passwordLogin(let shown) = coordinator.screen {
      #expect(shown === form)
    } else {
      Issue.record("expected the password form")
    }
  }

  /// Sign in on TwakeWelcome: the workplace homeserver's SSO is prepared, the registration site opens with the login
  /// redirect, and its callback signs in (twake_welcome.dart:62-139).
  @Test func twakeIDSignInUsesTheRegistrationSiteAndSignsIn() async throws {
    let repository = FakeAuthenticationRepository()
    repository.startSSOResult = .success(URL(string: "https://tom.example.org/sso")!)
    repository.finishSSOResult = .success(session)
    let web = FakeWebAuthenticator()
    let callback = URL(string: "twake.chat://redirect?loginToken=abc")!
    web.result = .success(callback)
    let coordinator = coordinator(repository, web: web)

    try await #require(welcome(coordinator)).signIn()

    #expect(
      repository.startSSOCalls == [
        .init(
          homeserver: URL(string: "https://tom.example.org/")!, identityProviderId: nil,
          redirectURL: URL(string: "twake.chat://redirect")!)
      ])
    #expect(
      web.calls == [
        .init(
          url: URL(
            string:
              "https://sign-up.example.org/?post_login_redirect_url=twake.chat://redirect&app=chat")!,
          callbackScheme: "twake.chat")
      ])
    #expect(repository.finishSSOCalls == [callback])
    #expect(signedIn(coordinator)?.userId == "@alice:example.org")
  }

  @Test func createTwakeIDUsesTheRegisteredRedirect() async throws {
    let repository = FakeAuthenticationRepository()
    repository.startSSOResult = .success(URL(string: "https://tom.example.org/sso")!)
    let web = FakeWebAuthenticator()
    let coordinator = coordinator(repository, web: web)
    try await #require(welcome(coordinator)).createTwakeID()
    #expect(web.calls.first?.url.query()?.hasPrefix("post_registered_redirect_url=") == true)
  }

  /// Closing the web page is not an error: the welcome screen stays, with no message, and the started SSO is dropped.
  @Test func closingTheSignInPageStaysOnWelcomeQuietly() async throws {
    let repository = FakeAuthenticationRepository()
    repository.startSSOResult = .success(URL(string: "https://tom.example.org/sso")!)
    let web = FakeWebAuthenticator()
    web.result = .failure(.cancelled)
    let coordinator = coordinator(repository, web: web)
    let screen = try #require(welcome(coordinator))
    await screen.signIn()
    #expect(repository.cancelSSOCallCount == 1)
    #expect(repository.finishSSOCalls.isEmpty)
    #expect(screen.errorMessage == nil)
    #expect(welcome(coordinator) === screen)
  }

  @Test func aRejectedLoginTokenShowsAnError() async throws {
    let repository = FakeAuthenticationRepository()
    repository.startSSOResult = .success(URL(string: "https://tom.example.org/sso")!)
    repository.finishSSOResult = .failure(.invalidCredentials)
    let web = FakeWebAuthenticator()
    web.result = .success(URL(string: "twake.chat://redirect?loginToken=abc")!)
    let coordinator = coordinator(repository, web: web)
    let screen = try #require(welcome(coordinator))
    await screen.signIn()
    #expect(screen.errorMessage == "Invalid username or password")
  }

  /// A server with SSO, no registration and one identity provider goes straight to that provider's page.
  @Test func aSingleProviderServerOpensItsSSOPage() async throws {
    let repository = FakeAuthenticationRepository()
    let provider = HomeserverLoginOptions.IdentityProvider(id: "oidc-twake", name: "Twake SSO")
    repository.loginOptionsResult = .success(
      HomeserverLoginOptions(
        homeserver: homeserver, supportsPassword: true, supportsSSO: true,
        identityProviders: [provider],
        registrationSupported: false))
    let ssoPage = URL(
      string: "https://matrix.example.org/_matrix/client/v3/login/sso/redirect/oidc-twake")!
    repository.startSSOResult = .success(ssoPage)
    repository.finishSSOResult = .success(session)
    let web = FakeWebAuthenticator()
    web.result = .success(URL(string: "twake.chat://login?loginToken=abc")!)
    let coordinator = coordinator(repository, web: web)

    try #require(welcome(coordinator)).useCompanyServer()
    try await #require(picker(coordinator)).continueTapped()

    #expect(
      repository.startSSOCalls == [
        .init(
          homeserver: homeserver, identityProviderId: "oidc-twake",
          redirectURL: URL(string: "twake.chat://login")!)
      ])
    #expect(web.calls.map(\.url) == [ssoPage])
    #expect(signedIn(coordinator) != nil)
  }

  /// A server that also registers accounts shows the connect page with its providers.
  @Test func aServerWithRegistrationShowsTheConnectPage() async throws {
    let repository = FakeAuthenticationRepository()
    let providers: [HomeserverLoginOptions.IdentityProvider] = [
      .init(id: "a", name: "A"), .init(id: "b", name: "B"),
    ]
    repository.loginOptionsResult = .success(
      HomeserverLoginOptions(
        homeserver: homeserver, supportsPassword: false, supportsSSO: true,
        identityProviders: providers,
        registrationSupported: true))
    let coordinator = coordinator(repository)
    try #require(welcome(coordinator)).useCompanyServer()
    try await #require(picker(coordinator)).continueTapped()
    guard case .connect(let connect) = coordinator.screen else {
      Issue.record("expected the connect page")
      return
    }
    #expect(connect.title == "matrix.example.org")
    #expect(connect.providers == providers)
    connect.back()
    #expect(picker(coordinator) != nil)
  }

  @Test func anUnknownServerShowsWrongServerName() async throws {
    let repository = FakeAuthenticationRepository()
    repository.loginOptionsResult = .failure(.invalidHomeserverURL)
    let coordinator = coordinator(repository)
    try #require(welcome(coordinator)).useCompanyServer()
    let picker = try #require(picker(coordinator))
    await picker.continueTapped()
    #expect(picker.isWrongServerName)
    #expect(picker.errorMessage == nil)
    #expect(self.picker(coordinator) === picker)
  }
}
