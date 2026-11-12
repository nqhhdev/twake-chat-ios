import AuthenticationTestSupport
import Domain
import Foundation
import Testing

@testable import Authentication

@MainActor
struct PasswordLoginViewModelTests {
  private let homeserver = URL(string: "https://matrix.example.org")!
  private let session = UserSession(
    userId: "@alice:example.org", deviceId: "DEVICE",
    homeserverURL: URL(string: "https://matrix.example.org")!,
    accessToken: "token", refreshToken: nil)

  private func makeViewModel(
    _ repository: FakeAuthenticationRepository,
    onSignedIn: @escaping @MainActor (UserSession) -> Void = { _ in }
  ) -> PasswordLoginViewModel {
    PasswordLoginViewModel(
      repository: repository, defaultHomeserver: homeserver, onSignedIn: onSignedIn)
  }

  @Test func homeserverIsPrefilledFromConfiguration() {
    let viewModel = makeViewModel(FakeAuthenticationRepository())
    #expect(viewModel.homeserver == "https://matrix.example.org")
    #expect(viewModel.username.isEmpty)
    #expect(viewModel.password.isEmpty)
    #expect(!viewModel.isLoading)
  }

  @Test func noDefaultHomeserverLeavesTheFieldEmpty() {
    let viewModel = PasswordLoginViewModel(
      repository: FakeAuthenticationRepository(), defaultHomeserver: nil, onSignedIn: { _ in })
    #expect(viewModel.homeserver.isEmpty)
  }

  @Test func emptyUsernameDoesNotSubmit() async {
    let repository = FakeAuthenticationRepository()
    let viewModel = makeViewModel(repository)
    viewModel.password = "secret"
    await viewModel.signIn()
    #expect(repository.loginCalls.isEmpty)
    #expect(viewModel.usernameError == "Please enter your Matrix Id or username")
    #expect(viewModel.passwordError == nil)
  }

  @Test func emptyPasswordDoesNotSubmit() async {
    let repository = FakeAuthenticationRepository()
    let viewModel = makeViewModel(repository)
    viewModel.username = "alice"
    await viewModel.signIn()
    #expect(repository.loginCalls.isEmpty)
    #expect(viewModel.usernameError == nil)
    #expect(viewModel.passwordError == "Please enter your password")
  }

  @Test func bothEmptyShowBothMessages() async {
    let repository = FakeAuthenticationRepository()
    let viewModel = makeViewModel(repository)
    await viewModel.signIn()
    #expect(repository.loginCalls.isEmpty)
    #expect(viewModel.usernameError != nil)
    #expect(viewModel.passwordError != nil)
    #expect(viewModel.errorMessage == nil)
  }

  @Test func filledFieldsClearTheEarlierMessages() async {
    let repository = FakeAuthenticationRepository()
    repository.loginResult = .success(session)
    let viewModel = makeViewModel(repository)
    await viewModel.signIn()
    viewModel.username = "alice"
    viewModel.password = "secret"
    await viewModel.signIn()
    #expect(viewModel.usernameError == nil)
    #expect(viewModel.passwordError == nil)
  }

  /// The Flutter app checks `text.isEmpty` with no trimming (lib/pages/login/login.dart:55-66), so a field of spaces
  /// is not empty and the form is sent as typed.
  @Test func blankButNotEmptyFieldsAreSentAsTyped() async {
    let repository = FakeAuthenticationRepository()
    repository.loginResult = .success(session)
    let viewModel = makeViewModel(repository)
    viewModel.username = " alice "
    viewModel.password = " "
    await viewModel.signIn()
    #expect(viewModel.usernameError == nil)
    #expect(viewModel.passwordError == nil)
    #expect(
      repository.loginCalls == [.init(homeserver: homeserver, username: " alice ", password: " ")])
  }

  @Test func emptyFieldsAfterAFailureClearTheLastErrorAndShowTheFieldMessage() async {
    let repository = FakeAuthenticationRepository()
    repository.loginResult = .failure(.invalidCredentials)
    let viewModel = makeViewModel(repository)
    viewModel.username = "alice"
    viewModel.password = "wrong"
    await viewModel.signIn()
    #expect(viewModel.errorMessage != nil)
    viewModel.password = ""
    await viewModel.signIn()
    #expect(repository.loginCalls.count == 1)
    #expect(viewModel.errorMessage == nil)
    #expect(viewModel.passwordError == "Please enter your password")
  }

  @Test func successSendsTheFormAndReportsTheSession() async {
    let repository = FakeAuthenticationRepository()
    repository.loginResult = .success(session)
    var signedIn: [UserSession] = []
    let viewModel = makeViewModel(repository) { signedIn.append($0) }
    viewModel.username = "alice"
    viewModel.password = "secret"
    await viewModel.signIn()
    #expect(
      repository.loginCalls == [
        .init(homeserver: homeserver, username: "alice", password: "secret")
      ])
    #expect(signedIn == [session])
    #expect(!viewModel.isLoading)
    #expect(viewModel.errorMessage == nil)
  }

  /// The homeserver field is editable: the address the user typed is sent, not the configured default.
  @Test func anEditedHomeserverIsTheOneSent() async {
    let repository = FakeAuthenticationRepository()
    repository.loginResult = .success(session)
    let viewModel = makeViewModel(repository)
    viewModel.homeserver = "https://other.example.net"
    viewModel.username = "alice"
    viewModel.password = "secret"
    await viewModel.signIn()
    #expect(
      repository.loginCalls == [
        .init(
          homeserver: URL(string: "https://other.example.net")!, username: "alice",
          password: "secret")
      ])
  }

  @Test func loadingIsShownWhileSigningInAndASecondTapIsIgnored() async {
    let repository = FakeAuthenticationRepository()
    repository.loginResult = .success(session)
    repository.holdLogin()
    var signedIn: [UserSession] = []
    let viewModel = makeViewModel(repository) { signedIn.append($0) }
    viewModel.username = "alice"
    viewModel.password = "secret"
    let first = Task { await viewModel.signIn() }
    while repository.loginCalls.isEmpty { await Task.yield() }
    #expect(viewModel.isLoading)
    await viewModel.signIn()
    #expect(repository.loginCalls.count == 1)
    repository.releaseLogin()
    await first.value
    #expect(!viewModel.isLoading)
    #expect(signedIn == [session])
  }

  @Test(
    arguments: [
      (AuthenticationError.invalidCredentials, "Invalid username or password"),
      (.serverUnreachable, "No connection to the server"),
      (.invalidHomeserverURL, "This is not a valid Matrix homeserver address"),
      (.unknown, "Oops, something went wrong…"),
    ])
  func eachErrorHasItsMessageAndKeepsTheForm(error: AuthenticationError, message: String) async {
    let repository = FakeAuthenticationRepository()
    repository.loginResult = .failure(error)
    var signedIn: [UserSession] = []
    let viewModel = makeViewModel(repository) { signedIn.append($0) }
    viewModel.username = "alice"
    viewModel.password = "secret"
    await viewModel.signIn()
    #expect(viewModel.errorMessage == message)
    #expect(signedIn.isEmpty)
    #expect(!viewModel.isLoading)
    #expect(viewModel.homeserver == "https://matrix.example.org")
    #expect(viewModel.username == "alice")
    #expect(viewModel.password == "secret")
  }

  @Test func theNextTryClearsTheLastError() async {
    let repository = FakeAuthenticationRepository()
    repository.loginResult = .failure(.serverUnreachable)
    let viewModel = makeViewModel(repository)
    viewModel.username = "alice"
    viewModel.password = "secret"
    await viewModel.signIn()
    repository.loginResult = .success(session)
    await viewModel.signIn()
    #expect(viewModel.errorMessage == nil)
  }

  /// The Flutter app checks the empty fields first and only then reaches the homeserver
  /// (lib/pages/login/login.dart:54-66): with an empty field the field message shows, not the homeserver error.
  @Test(arguments: ["", "not a url"])
  func emptyFieldsAreCheckedBeforeTheHomeserver(homeserver: String) async {
    let repository = FakeAuthenticationRepository()
    let viewModel = makeViewModel(repository)
    viewModel.homeserver = homeserver
    viewModel.password = "secret"
    await viewModel.signIn()
    #expect(repository.loginCalls.isEmpty)
    #expect(viewModel.usernameError == "Please enter your Matrix Id or username")
    #expect(viewModel.passwordError == nil)
    #expect(viewModel.errorMessage == nil)
    #expect(!viewModel.isLoading)
  }

  @Test(arguments: ["", "not a url", "matrix.example.org"])
  func anUnusableHomeserverDoesNotSubmit(homeserver: String) async {
    let repository = FakeAuthenticationRepository()
    let viewModel = makeViewModel(repository)
    viewModel.homeserver = homeserver
    viewModel.username = "alice"
    viewModel.password = "secret"
    await viewModel.signIn()
    #expect(repository.loginCalls.isEmpty)
    #expect(viewModel.errorMessage == "This is not a valid Matrix homeserver address")
  }
}
