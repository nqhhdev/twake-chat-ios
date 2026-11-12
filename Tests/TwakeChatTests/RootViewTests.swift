import Authentication
import AuthenticationTestSupport
import Domain
import Foundation
import Testing

@testable import TwakeChat

/// The root restores the saved session at launch and starts the authentication flow from the result.
@MainActor
struct RootViewTests {
  private let homeserver = URL(string: "https://matrix.example.org")!
  private let session = UserSession(
    userId: "@alice:example.org", deviceId: "DEVICE",
    homeserverURL: URL(string: "https://matrix.example.org")!, accessToken: "token",
    refreshToken: nil)

  @Test func startsRestoringWithNoFlow() {
    let root = RootCoordinator(
      repository: FakeAuthenticationRepository(), defaultHomeserver: homeserver)
    #expect(root.state == .restoring)
    #expect(root.authentication == nil)
  }

  @Test func aRestoredSessionShowsSignedIn() async {
    let repository = FakeAuthenticationRepository()
    repository.restoreResult = .success(session)
    let root = RootCoordinator(repository: repository, defaultHomeserver: homeserver)
    await root.start()
    #expect(repository.restoreCallCount == 1)
    #expect(root.state == .restored(session))
    guard case .signedIn(let signedIn) = root.authentication?.screen else {
      Issue.record("expected the signed-in screen")
      return
    }
    #expect(signedIn.userId == "@alice:example.org")
  }

  @Test func noSavedSessionShowsLogin() async {
    let repository = FakeAuthenticationRepository()
    repository.restoreResult = .success(nil)
    let root = RootCoordinator(repository: repository, defaultHomeserver: homeserver)
    await root.start()
    #expect(root.state == .restored(nil))
    guard case .passwordLogin(let login) = root.authentication?.screen else {
      Issue.record("expected the login form")
      return
    }
    #expect(login.homeserver == "https://matrix.example.org")
  }

  /// Every restore error keeps the saved session: the root does not log out, shows no flow and offers a retry. The
  /// Domain errors cannot tell a rejected session from a fault that passes (a locked Keychain, a held store lock, a
  /// 5xx), and logging out deletes the session and its encryption keys for good.
  @Test(arguments: [
    AuthenticationError.unknown, .invalidCredentials, .invalidHomeserverURL, .serverUnreachable,
  ])
  func aRestoreErrorKeepsTheSavedSession(error: AuthenticationError) async {
    let repository = FakeAuthenticationRepository()
    repository.savedSession = session
    repository.restoreResult = .failure(error)
    let root = RootCoordinator(repository: repository, defaultHomeserver: homeserver)
    await root.start()
    #expect(repository.restoreCallCount == 1)
    #expect(repository.logoutCallCount == 0)
    #expect(repository.savedSession == session)
    #expect(root.state == .restoreFailed)
    #expect(root.authentication == nil)
  }

  /// Hosted in the Debug app: the build configuration's development homeserver reaches the Info.plist key the
  /// composition root reads, as a usable URL (ADR 0019).
  @Test func theDebugBuildConfiguresTheStagingHomeserver() throws {
    let value = try #require(
      Bundle.main.object(forInfoDictionaryKey: "DefaultHomeserver") as? String)
    #expect(value == "https://matrix.stg.lin-saas.com")
    let url = try #require(URL(string: value))
    #expect(url.scheme == "https")
    #expect(url.host() == "matrix.stg.lin-saas.com")
  }

  @Test func signingInAfterAnEmptyRestoreShowsSignedIn() async throws {
    let repository = FakeAuthenticationRepository()
    repository.restoreResult = .success(nil)
    repository.loginResult = .success(session)
    let root = RootCoordinator(repository: repository, defaultHomeserver: homeserver)
    await root.start()
    guard case .passwordLogin(let login) = root.authentication?.screen else {
      Issue.record("expected the login form")
      return
    }
    login.username = "alice"
    login.password = "secret"
    await login.signIn()
    guard case .signedIn(let signedIn) = root.authentication?.screen else {
      Issue.record("expected the signed-in screen")
      return
    }
    await signedIn.logOut()
    #expect(repository.logoutCallCount == 1)
    guard case .passwordLogin = root.authentication?.screen else {
      Issue.record("expected the login form after logout")
      return
    }
  }

  @Test func startRestoresOnlyOnce() async {
    let repository = FakeAuthenticationRepository()
    let root = RootCoordinator(repository: repository, defaultHomeserver: homeserver)
    await root.start()
    await root.start()
    #expect(repository.restoreCallCount == 1)
  }

  /// After a failed restore, trying again restores the kept session, whatever the first error was.
  @Test func tryingAgainAfterARestoreErrorRestoresTheKeptSession() async {
    let repository = FakeAuthenticationRepository()
    repository.savedSession = session
    repository.restoreResult = .failure(.unknown)
    let root = RootCoordinator(repository: repository, defaultHomeserver: homeserver)
    await root.start()
    repository.restoreResult = .success(session)
    await root.start()
    #expect(repository.restoreCallCount == 2)
    #expect(repository.logoutCallCount == 0)
    #expect(root.state == .restored(session))
    guard case .signedIn = root.authentication?.screen else {
      Issue.record("expected the signed-in screen")
      return
    }
  }

  @Test func aSuccessfulRestoreDoesNotLogOut() async {
    let repository = FakeAuthenticationRepository()
    repository.restoreResult = .success(session)
    let root = RootCoordinator(repository: repository, defaultHomeserver: homeserver)
    await root.start()
    #expect(repository.logoutCallCount == 0)
  }

  /// Every window of the app shares one root coordinator, so two starts can overlap; only one restores.
  @Test func overlappingStartsRestoreOnlyOnce() async {
    let repository = FakeAuthenticationRepository()
    repository.restoreResult = .success(session)
    repository.holdRestore()
    let root = RootCoordinator(repository: repository, defaultHomeserver: homeserver)
    let first = Task { await root.start() }
    while repository.restoreCallCount == 0 { await Task.yield() }
    await root.start()
    #expect(repository.restoreCallCount == 1)
    #expect(root.state == .restoring)
    repository.releaseRestore()
    await first.value
    #expect(repository.restoreCallCount == 1)
    #expect(root.state == .restored(session))
  }
}
