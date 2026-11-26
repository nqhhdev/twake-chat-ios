import AppShared
import Foundation
import MatrixData
import Testing

@Suite(.serialized)
struct StoreLockSharingTests {
  private let sessionStore: KeychainSessionStore
  private let storeDirectory: URL

  init() throws {
    let group = try #require(
      Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String)
    sessionStore = KeychainSessionStore(
      service: "app.twake.ios.chat.tests.store-lock-sharing", accessGroup: group)
    try sessionStore.delete()
    storeDirectory = FileManager.default.temporaryDirectory
      .appending(path: "StoreLockSharingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  }

  private func cleanUp() {
    try? sessionStore.delete()
    try? FileManager.default.removeItem(at: storeDirectory)
  }

  private func repository(_ holder: String) -> MatrixAuthenticationRepository {
    MatrixAuthenticationRepository(
      storeDirectory: storeDirectory, sessionStore: sessionStore, lockHolderName: holder)
  }

  @Test(.timeLimit(.minutes(1)))
  func theAppAndTheExtensionOpenTheStoreAtTheSameTimeOnAColdStart() async throws {
    defer { cleanUp() }
    let server = try FakeHomeserver()
    defer { server.stop() }
    try sessionStore.save(
      StoredSession(
        userId: "@alice:example.org", deviceId: "DEVICE", homeserverURL: server.url,
        accessToken: "access-token", refreshToken: nil, slidingSyncVersion: "native"))
    try await createStore()
    let app = repository("app")
    let extensionProcess = repository("nse")

    async let appSession = app.restoreSession()
    async let extensionSession = extensionProcess.restoreSession()
    let sessions = try await (appSession, extensionSession)

    #expect(sessions.0?.userId == "@alice:example.org")
    #expect(sessions.1?.userId == "@alice:example.org")
    let appClient = try #require(await app.clientProxy)
    let extensionClient = try #require(await extensionProcess.clientProxy)
    #expect(appClient !== extensionClient)
    #expect(try extensionClient.deviceId == "DEVICE")
  }

  private func createStore() async throws {
    let firstLaunch = repository("app")
    _ = try await firstLaunch.restoreSession()
    await firstLaunch.pauseSync()
  }

  @Test(.timeLimit(.minutes(1)))
  func theExtensionOpensTheStoreAgainAfterTheAppHadIt() async throws {
    defer { cleanUp() }
    let server = try FakeHomeserver()
    defer { server.stop() }
    try sessionStore.save(
      StoredSession(
        userId: "@alice:example.org", deviceId: "DEVICE", homeserverURL: server.url,
        accessToken: "access-token", refreshToken: nil, slidingSyncVersion: "native"))
    let app = repository("app")
    _ = try await app.restoreSession()
    for _ in 0..<3 {
      let extensionProcess = repository("nse")
      #expect(try await extensionProcess.restoreSession()?.deviceId == "DEVICE")
    }
    #expect(await app.clientProxy != nil)
  }
}
