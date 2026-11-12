import AppShared
import Authentication
import Domain
import Foundation
import MatrixData
import Testing

@testable import TwakeChat

/// Added by the TWAK-65 tester. The card's manual check (sign in, kill and relaunch, log out, relaunch), run with the
/// repository the composition root builds and a homeserver on the loopback interface (`FakeHomeserver`), so nothing
/// leaves the machine. A "relaunch" is a new `MatrixAuthenticationRepository` and a new `RootCoordinator` on the same
/// Keychain service and store directory. The Keychain service is used by this suite only.
@MainActor
@Suite(.serialized)
struct RootLaunchLifecycleTests {
  private static let loginAnswer = (
    status: "200 OK",
    body: """
      {"user_id":"@alice:example.org","access_token":"fixture-access","device_id":"NEWDEVICE",\
      "refresh_token":"fixture-refresh"}
      """
  )
  private let sessionStore: KeychainSessionStore
  private let storeDirectory: URL

  init() throws {
    let group = try #require(
      Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String)
    sessionStore = KeychainSessionStore(
      service: "app.twake.ios.chat.tests.root-launch-lifecycle", accessGroup: group)
    try sessionStore.delete()
    storeDirectory = FileManager.default.temporaryDirectory
      .appending(path: "RootLaunchLifecycleTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  }

  private func cleanUp() {
    try? sessionStore.delete()
    try? FileManager.default.removeItem(at: storeDirectory)
  }

  /// One app launch: a fresh repository and root coordinator on the shared store, started as `RootView.task` does.
  private func launch(_ name: String, homeserver: URL) async -> RootCoordinator {
    let repository = MatrixAuthenticationRepository(
      storeDirectory: storeDirectory, sessionStore: sessionStore, lockHolderName: name)
    let root = RootCoordinator(repository: repository, defaultHomeserver: homeserver)
    await root.start()
    return root
  }

  private func passwordLogin(_ root: RootCoordinator) -> PasswordLoginViewModel? {
    if case .passwordLogin(let viewModel) = root.authentication?.screen { viewModel } else { nil }
  }

  private func signedIn(_ root: RootCoordinator) -> SignedInViewModel? {
    if case .signedIn(let viewModel) = root.authentication?.screen { viewModel } else { nil }
  }

  /// Card: "A Debug build opens to a login form". Nothing is saved, so the restore asks no server.
  @Test(.timeLimit(.minutes(1)))
  func aFirstLaunchShowsThePrefilledLoginForm() async throws {
    defer { cleanUp() }
    let root = await launch("tests-first", homeserver: URL(string: "https://matrix.example.org")!)
    #expect(root.state == .restored(nil))
    let form = try #require(passwordLogin(root))
    #expect(form.homeserver == "https://matrix.example.org")
  }

  /// Card: sign in, kill and relaunch (still signed in), log out (back to login), relaunch (login shown).
  @Test(.timeLimit(.minutes(1)))
  func signInRelaunchLogOutRelaunch() async throws {
    defer { cleanUp() }
    let server = try FakeHomeserver(responses: [
      "/login": Self.loginAnswer, "/logout": (status: "200 OK", body: "{}"),
    ])
    defer { server.stop() }

    let first = await launch("tests-launch-1", homeserver: server.url)
    let form = try #require(passwordLogin(first))
    form.username = "alice"
    form.password = "fixture-password"
    await form.signIn()
    #expect(form.errorMessage == nil)
    #expect(signedIn(first)?.userId == "@alice:example.org")

    let second = await launch("tests-launch-2", homeserver: server.url)
    #expect(second.state.restoredUserId == "@alice:example.org")
    let signedInScreen = try #require(signedIn(second))
    #expect(signedInScreen.userId == "@alice:example.org")

    await signedInScreen.logOut()
    #expect(signedInScreen.errorMessage == nil)
    #expect(server.requests.contains { $0.hasPrefix("POST ") && $0.hasSuffix("/logout") })
    #expect(passwordLogin(second) != nil)

    let third = await launch("tests-launch-3", homeserver: server.url)
    #expect(third.state == .restored(nil))
    #expect(passwordLogin(third) != nil)
  }

  /// SignedInViewModel's documented promise: when the server refuses the logout, the repository still deletes the
  /// local session, the screen shows an error, and trying again returns to the form at once. A relaunch then shows
  /// the form. The fake homeserver answers every `/logout` with `400 M_UNKNOWN`.
  @Test(.timeLimit(.minutes(1)))
  func aLogoutTheServerRefusesSucceedsOnTheSecondTryAndARelaunchShowsLogin() async throws {
    defer { cleanUp() }
    let server = try FakeHomeserver(responses: ["/login": Self.loginAnswer])
    defer { server.stop() }

    let first = await launch("tests-refused-1", homeserver: server.url)
    let form = try #require(passwordLogin(first))
    form.username = "alice"
    form.password = "fixture-password"
    await form.signIn()
    let signedInScreen = try #require(signedIn(first))

    await signedInScreen.logOut()
    #expect(signedInScreen.errorMessage == "Could not log out. Please try again.")
    #expect(signedIn(first) === signedInScreen)
    #expect(try sessionStore.load() == nil)

    await signedInScreen.logOut()
    #expect(signedInScreen.errorMessage == nil)
    #expect(passwordLogin(first) != nil)

    let second = await launch("tests-refused-2", homeserver: server.url)
    #expect(second.state == .restored(nil))
    #expect(passwordLogin(second) != nil)
  }
}

extension RootCoordinator.State {
  fileprivate var restoredUserId: String? {
    if case .restored(let session?) = self { session.userId } else { nil }
  }
}
