import AppShared
import Domain
import Foundation
import MatrixData
import Testing

/// Tester (TWAK-66): `RoomListProxy` without a real homeserver. Hosted, because the Keychain needs the app's
/// entitlements; a test-only service and a temporary store keep it off a real session. The signed-in case uses the
/// loopback `FakeHomeserver` from `MatrixAuthenticationRepositoryTests`, so nothing leaves the machine.
@Suite(.serialized)
struct RoomListProxyTests {
  private let sessionStore: KeychainSessionStore
  private let storeDirectory: URL

  init() throws {
    let group = try #require(
      Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String)
    sessionStore = KeychainSessionStore(
      service: "app.twake.ios.chat.tests.room-list-proxy", accessGroup: group)
    try sessionStore.delete()
    storeDirectory = FileManager.default.temporaryDirectory
      .appending(path: "RoomListProxyTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  }

  private func repository() -> MatrixAuthenticationRepository {
    MatrixAuthenticationRepository(
      storeDirectory: storeDirectory, sessionStore: sessionStore, lockHolderName: "tests")
  }

  private func cleanUp() {
    try? sessionStore.delete()
    try? FileManager.default.removeItem(at: storeDirectory)
  }

  /// Before sign-in there is no client to sync: `start()` reports `notSignedIn`, and `stop()` before any start, or
  /// twice, does nothing.
  @Test func startBeforeSignInReportsNotSignedInAndStopIsSafe() async {
    defer { cleanUp() }
    let roomList = RoomListProxy(authentication: repository())
    await roomList.stop()
    await #expect(throws: RoomListError.notSignedIn) { _ = try await roomList.start() }
    await roomList.stop()
    await roomList.stop()
  }

  /// Card: logout stops sync before the session and store are cleared. This is the app's order: the chat list's Log out
  /// runs while the room list is started, then the screen goes away and its view model calls `stop()`. Logout still
  /// signs out and deletes the store and the Keychain item, the server sees no sync request after the logout request,
  /// `stop()` afterwards is safe, and the next `start()` reports `notSignedIn` instead of reusing the signed-out client.
  @Test(.timeLimit(.minutes(1)))
  func logoutWhileTheRoomListRunsStopsSyncAndSignsOut() async throws {
    defer { cleanUp() }
    let server = try FakeHomeserver(responses: ["/logout": (status: "200 OK", body: "{}")])
    defer { server.stop() }
    try sessionStore.save(
      StoredSession(
        userId: "@alice:example.org", deviceId: "DEVICE", homeserverURL: server.url,
        accessToken: "access-token", refreshToken: nil, slidingSyncVersion: "native"))
    let repository = repository()
    _ = try #require(try await repository.restoreSession())
    let roomList = RoomListProxy(authentication: repository)

    // The fake server answers sync with 404, so the room list may start or report `syncUnavailable`; either way the
    // sync service was built on the client, which is what logout has to stop.
    do {
      _ = try await roomList.start()
    } catch {
      #expect(error == .syncUnavailable)
    }

    try await repository.logout()
    // Give a sync loop that was not stopped time to send its next request.
    try await Task.sleep(for: .seconds(1))

    let requests = server.requests
    let logoutIndex = try #require(
      requests.lastIndex { $0.hasPrefix("POST ") && $0.hasSuffix("/logout") })
    let syncAfterLogout = requests[(logoutIndex + 1)...].filter { $0.contains("/sync") }
    #expect(syncAfterLogout.isEmpty, "sync requests after logout: \(syncAfterLogout)")
    #expect(!FileManager.default.fileExists(atPath: storeDirectory.path(percentEncoded: false)))
    #expect(try sessionStore.load() == nil)

    // What the app does next: the chat list screen goes away and its view model stops the room list.
    await roomList.stop()
    await #expect(throws: RoomListError.notSignedIn) { _ = try await roomList.start() }
  }

  // MARK: Tester (TWAK-66, round 2): the `RoomListRepository` contract on the proxy itself.

  /// `RoomListRepository`: the stream finishes when `stop()` is called, and a second `start()` finishes the stream of
  /// the first. The chat list view model relies on both to end its loop. Without them, the time limit fails the test.
  @Test(.timeLimit(.minutes(1)))
  func stopAndASecondStartFinishTheStream() async throws {
    defer { cleanUp() }
    let server = try FakeHomeserver(responses: ["/logout": (status: "200 OK", body: "{}")])
    defer { server.stop() }
    try sessionStore.save(
      StoredSession(
        userId: "@alice:example.org", deviceId: "DEVICE", homeserverURL: server.url,
        accessToken: "access-token", refreshToken: nil, slidingSyncVersion: "native"))
    let repository = repository()
    _ = try #require(try await repository.restoreSession())
    let roomList = RoomListProxy(authentication: repository)

    let first = try await roomList.start()
    let second = try await roomList.start()
    for await _ in first {}
    await roomList.stop()
    for await _ in second {}

    try await repository.logout()
  }
}
