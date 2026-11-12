import AppShared
import AuthenticationTestSupport
import Domain
import Foundation
import MatrixData
import Testing

@testable import TwakeChat

/// Added by the TWAK-65 tester. A launch with no network must not sign the user out.
/// `MatrixAuthenticationRepository.restoreSession` builds an SDK client that asks the homeserver which sliding sync
/// version it serves (`.discoverNative`), so restoring without a network throws. The Flutter app keeps its saved session
/// when it starts offline. Calling `logout()` on that error deletes the store directory and the Keychain session
/// (ADR 0007), and the user loses the session for good.
@MainActor
struct RootRestoreOfflineTests {
  private let session = UserSession(
    userId: "@alice:example.org", deviceId: "DEVICE",
    homeserverURL: URL(string: "https://matrix.example.org")!, accessToken: "token",
    refreshToken: nil)

  @Test func anUnreachableServerAtLaunchKeepsTheSavedSession() async {
    let repository = FakeAuthenticationRepository()
    repository.savedSession = session
    repository.restoreResult = .failure(.serverUnreachable)
    let root = RootCoordinator(
      repository: repository, defaultHomeserver: URL(string: "https://matrix.example.org")!)
    await root.start()
    #expect(repository.restoreCallCount == 1)
    #expect(repository.logoutCallCount == 0)
    #expect(repository.savedSession == session)
    #expect(root.state == .restoreFailed)
  }

  /// Trying again once the server answers restores the kept session.
  @Test func tryingAgainOnceTheServerAnswersRestoresTheSession() async {
    let repository = FakeAuthenticationRepository()
    repository.savedSession = session
    repository.restoreResult = .failure(.serverUnreachable)
    let root = RootCoordinator(
      repository: repository, defaultHomeserver: URL(string: "https://matrix.example.org")!)
    await root.start()
    repository.restoreResult = .success(session)
    await root.start()
    #expect(repository.restoreCallCount == 2)
    #expect(repository.logoutCallCount == 0)
    #expect(root.state == .restored(session))
  }

  /// A restore error that does not pass is not a dead end: Log out signs out and shows the sign-in form.
  @Test func logOutAfterAFailedRestoreShowsTheSignInForm() async {
    let repository = FakeAuthenticationRepository()
    repository.savedSession = session
    repository.restoreResult = .failure(.unknown)
    let root = RootCoordinator(
      repository: repository, defaultHomeserver: URL(string: "https://matrix.example.org")!)
    await root.start()
    #expect(root.state == .restoreFailed)
    await root.logOutAfterFailedRestore()
    #expect(repository.logoutCallCount == 1)
    #expect(root.state == .restored(nil))
    guard case .passwordLogin = root.authentication?.screen else {
      Issue.record("expected the sign-in form")
      return
    }
  }

  /// Second TWAK-65 tester round: the same launch with the real repository the composition root builds, not the fake.
  /// The saved session points at a closed local port, so the SDK cannot reach it and nothing leaves the machine. The
  /// root must keep the Keychain item and the store directory, and must not offer the sign-in form.
  @Test(.timeLimit(.minutes(1)))
  func anUnreachableServerAtLaunchKeepsTheSessionWithTheRealRepository() async throws {
    let group = try #require(
      Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String)
    let sessionStore = KeychainSessionStore(
      service: "app.twake.ios.chat.tests.root-restore-offline", accessGroup: group)
    let storeDirectory = FileManager.default.temporaryDirectory
      .appending(path: "RootRestoreOfflineTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    defer {
      try? sessionStore.delete()
      try? FileManager.default.removeItem(at: storeDirectory)
    }
    let saved = StoredSession(
      userId: "@alice:example.org", deviceId: "DEVICE",
      homeserverURL: URL(string: "http://127.0.0.1:9")!, accessToken: "access-token",
      refreshToken: nil, slidingSyncVersion: "native")
    try sessionStore.save(saved)
    try FileManager.default.createDirectory(
      at: storeDirectory.appending(path: "data"), withIntermediateDirectories: true)
    let repository = MatrixAuthenticationRepository(
      storeDirectory: storeDirectory, sessionStore: sessionStore, lockHolderName: "tests")
    let root = RootCoordinator(
      repository: repository, defaultHomeserver: URL(string: "https://matrix.example.org")!)

    await root.start()

    #expect(root.state == .restoreFailed)
    #expect(root.authentication == nil)
    #expect(try sessionStore.load() == saved)
    #expect(FileManager.default.fileExists(atPath: storeDirectory.path(percentEncoded: false)))
  }
}
