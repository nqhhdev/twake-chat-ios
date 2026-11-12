import Authentication
import AuthenticationTestSupport
import Domain
import Foundation
import Testing

@testable import TwakeChat

/// Added by the TWAK-65 tester (third round). The restore-failed screen's two actions on the root, on the branches the
/// other root tests do not reach: a Try again that fails again, a Log out that reports an error, a Log out and a Try
/// again that arrive while the other is running, and a Log out that arrives when the restore did not fail.
@MainActor
struct RootRestoreFailedTests {
  private let homeserver = URL(string: "https://matrix.example.org")!
  private let session = UserSession(
    userId: "@alice:example.org", deviceId: "DEVICE",
    homeserverURL: URL(string: "https://matrix.example.org")!, accessToken: "token",
    refreshToken: nil)

  /// Try again that fails once more stays on the restore-failed screen, keeps the session, and can be tried again.
  @Test func aRetryThatFailsAgainStaysOnTheRestoreFailedScreen() async {
    let repository = FakeAuthenticationRepository()
    repository.savedSession = session
    repository.restoreResult = .failure(.serverUnreachable)
    let root = RootCoordinator(repository: repository, defaultHomeserver: homeserver)
    await root.start()
    await root.start()
    #expect(repository.restoreCallCount == 2)
    #expect(repository.logoutCallCount == 0)
    #expect(repository.savedSession == session)
    #expect(root.state == .restoreFailed)
    #expect(root.authentication == nil)

    repository.restoreResult = .success(session)
    await root.start()
    #expect(repository.restoreCallCount == 3)
    #expect(root.state == .restored(session))
  }

  /// Log out on the restore-failed screen that reports an error stays on that screen with a message and keeps the
  /// session: MatrixAuthenticationRepository.logout throws when the saved session could not be removed, and the user is
  /// never shown as signed out while a session is still saved. Log out can be tried again.
  @Test(arguments: [AuthenticationError.serverUnreachable, .unknown])
  func logOutAfterAFailedRestoreThatReportsAnErrorStaysWithAMessage(
    error: AuthenticationError
  ) async {
    let repository = FakeAuthenticationRepository()
    repository.savedSession = session
    repository.restoreResult = .failure(.unknown)
    repository.logoutResult = .failure(error)
    let root = RootCoordinator(repository: repository, defaultHomeserver: homeserver)
    await root.start()
    await root.logOutAfterFailedRestore()
    #expect(repository.logoutCallCount == 1)
    #expect(repository.savedSession == session)
    #expect(root.state == .restoreFailed)
    #expect(root.logOutErrorMessage == "Could not log out. Please try again.")
    #expect(root.authentication == nil)

    repository.logoutResult = .success(())
    await root.logOutAfterFailedRestore()
    #expect(repository.logoutCallCount == 2)
    #expect(root.logOutErrorMessage == nil)
    #expect(root.state == .restored(nil))
    guard case .passwordLogin(let form) = root.authentication?.screen else {
      Issue.record("expected the sign-in form")
      return
    }
    #expect(form.homeserver == "https://matrix.example.org")
  }

  /// Try again hides the restore-failed screen while the restore runs, so a Log out that arrives during that restore
  /// does nothing: logout never runs beside a restore, and the restored session is shown.
  @Test func logOutDuringARetryThatIsStillRunningDoesNothing() async {
    let repository = FakeAuthenticationRepository()
    repository.savedSession = session
    repository.restoreResult = .failure(.serverUnreachable)
    let root = RootCoordinator(repository: repository, defaultHomeserver: homeserver)
    await root.start()
    #expect(root.state == .restoreFailed)

    repository.restoreResult = .success(session)
    repository.holdRestore()
    let retry = Task { await root.start() }
    while repository.restoreCallCount < 2 { await Task.yield() }
    #expect(root.state == .restoring)
    await root.logOutAfterFailedRestore()
    #expect(repository.logoutCallCount == 0)
    repository.releaseRestore()
    await retry.value
    #expect(repository.logoutCallCount == 0)
    #expect(repository.savedSession == session)
    #expect(root.state == .restored(session))
  }

  /// Try again while a Log out is running does nothing: no restore runs beside a logout.
  @Test func retryDuringALogOutThatIsStillRunningDoesNothing() async {
    let repository = FakeAuthenticationRepository()
    repository.savedSession = session
    repository.restoreResult = .failure(.serverUnreachable)
    let root = RootCoordinator(repository: repository, defaultHomeserver: homeserver)
    await root.start()

    repository.holdLogout()
    let logOut = Task { await root.logOutAfterFailedRestore() }
    while repository.logoutCallCount == 0 { await Task.yield() }
    await root.start()
    #expect(repository.restoreCallCount == 1)
    repository.releaseLogout()
    await logOut.value
    #expect(repository.restoreCallCount == 1)
    #expect(root.state == .restored(nil))
  }

  /// Log out of the restore-failed screen does nothing unless the restore failed: a restored session is not signed out.
  @Test func logOutAfterFailedRestoreDoesNothingWhenTheRestoreSucceeded() async {
    let repository = FakeAuthenticationRepository()
    repository.restoreResult = .success(session)
    let root = RootCoordinator(repository: repository, defaultHomeserver: homeserver)
    await root.start()
    let flow = root.authentication
    await root.logOutAfterFailedRestore()
    #expect(repository.logoutCallCount == 0)
    #expect(root.state == .restored(session))
    #expect(root.authentication === flow)
    guard case .signedIn(let screen) = root.authentication?.screen else {
      Issue.record("expected the signed-in screen")
      return
    }
    #expect(screen.userId == "@alice:example.org")
  }

  /// Log out before the restore has finished does nothing either.
  @Test func logOutAfterFailedRestoreDoesNothingWhileRestoring() async {
    let repository = FakeAuthenticationRepository()
    let root = RootCoordinator(repository: repository, defaultHomeserver: homeserver)
    await root.logOutAfterFailedRestore()
    #expect(repository.logoutCallCount == 0)
    #expect(root.state == .restoring)
    #expect(root.authentication == nil)
  }
}
