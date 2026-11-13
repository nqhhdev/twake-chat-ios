import AppShared
import Foundation
import Testing

@testable import MatrixData

/// The session delegate `ClientProxy` gives the SDK for its multi-process lock (TWAK-64). Hosted, because it reads and
/// writes the Keychain; a test-only service keeps it off a real session. SDK values are built through the mapper, so
/// this file does not import the SDK (ADR 0006).
@Suite(.serialized)
struct KeychainClientSessionDelegateTests {
  private let store: KeychainSessionStore
  private let delegate: KeychainClientSessionDelegate

  init() throws {
    let group = try #require(
      Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String)
    store = KeychainSessionStore(
      service: "app.twake.ios.chat.tests.keychain-client-session-delegate", accessGroup: group)
    try store.delete()
    delegate = KeychainClientSessionDelegate(sessionStore: store)
  }

  private func stored(accessToken: String, deviceId: String = "DEVICE") -> StoredSession {
    StoredSession(
      userId: "@alice:example.org", deviceId: deviceId,
      homeserverURL: URL(string: "https://matrix.example.org")!,
      accessToken: accessToken, refreshToken: "refresh-\(accessToken)", slidingSyncVersion: "native")
  }

  @Test func retrieveReturnsTheSavedSessionOfThatUser() throws {
    defer { try? store.delete() }
    let saved = stored(accessToken: "token-1")
    try store.save(saved)
    let session = try delegate.retrieveSessionFromKeychain(userId: "@alice:example.org")
    #expect(try UserSessionMapper.storedSession(from: session) == saved)
  }

  @Test func retrieveForAnotherUserOrWithNothingSavedThrows() throws {
    defer { try? store.delete() }
    #expect(throws: (any Error).self) {
      _ = try delegate.retrieveSessionFromKeychain(userId: "@alice:example.org")
    }
    try store.save(stored(accessToken: "token-1"))
    #expect(throws: (any Error).self) {
      _ = try delegate.retrieveSessionFromKeychain(userId: "@bob:example.org")
    }
  }

  /// Refreshed tokens of the saved device replace the saved ones and keep the sliding sync version.
  @Test func savedRefreshedTokensReplaceTheSavedSession() throws {
    defer { try? store.delete() }
    try store.save(stored(accessToken: "token-1"))
    let refreshed = stored(accessToken: "token-2")
    delegate.saveSessionInKeychain(session: UserSessionMapper.sdkSession(from: refreshed))
    #expect(try store.load() == refreshed)
  }

  /// A refresh after sign-out deleted the item, or one of another device, never re-creates or replaces a session.
  @Test func savedTokensNeverRecreateADeletedSessionOrReplaceAnotherDevice() throws {
    defer { try? store.delete() }
    delegate.saveSessionInKeychain(session: UserSessionMapper.sdkSession(from: stored(accessToken: "token-2")))
    #expect(try store.load() == nil)

    let saved = stored(accessToken: "token-1")
    try store.save(saved)
    delegate.saveSessionInKeychain(
      session: UserSessionMapper.sdkSession(from: stored(accessToken: "token-3", deviceId: "OTHER")))
    #expect(try store.load() == saved)
  }
}
