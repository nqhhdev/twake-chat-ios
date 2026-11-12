import AppShared
import Foundation
import Testing

/// Keychain round trips in the app's real access group, read from the host app's Info.plist. They run hosted on the
/// simulator because the Keychain needs the app's entitlements. A test-only service keeps them off a real session.
@Suite(.serialized)
struct KeychainSessionStoreTests {
  private let store: KeychainSessionStore

  init() throws {
    let group = try #require(
      Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String)
    #expect(group.hasSuffix("app.twake.ios.chat"))
    store = KeychainSessionStore(
      service: "app.twake.ios.chat.tests.keychain-session-store", accessGroup: group)
    try store.delete()
  }

  private func session(accessToken: String, refreshToken: String?) -> StoredSession {
    StoredSession(
      userId: "@alice:example.org", deviceId: "DEVICE",
      homeserverURL: URL(string: "https://matrix.example.org")!,
      accessToken: accessToken, refreshToken: refreshToken)
  }

  @Test func loadWhenEmptyReturnsNil() throws {
    #expect(try store.load() == nil)
  }

  @Test func saveThenLoad() throws {
    let saved = session(accessToken: "token-1", refreshToken: "refresh-1")
    try store.save(saved)
    #expect(try store.load() == saved)
    try store.delete()
  }

  @Test func overwriteThenLoadReturnsTheNewSession() throws {
    try store.save(session(accessToken: "token-1", refreshToken: "refresh-1"))
    let newer = session(accessToken: "token-2", refreshToken: nil)
    try store.save(newer)
    #expect(try store.load() == newer)
    try store.delete()
  }

  @Test func deleteThenLoadReturnsNil() throws {
    try store.save(session(accessToken: "token-1", refreshToken: nil))
    try store.delete()
    #expect(try store.load() == nil)
  }

  @Test func deleteWhenEmptyDoesNotThrow() throws {
    try store.delete()
    try store.delete()
  }

  /// Two service names in the same group keep separate records.
  @Test func storesWithDifferentServicesDoNotShareTheRecord() throws {
    let group = try #require(
      Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String)
    let other = KeychainSessionStore(
      service: "app.twake.ios.chat.tests.keychain-session-store.other", accessGroup: group)
    try other.delete()
    defer {
      try? other.delete()
      try? store.delete()
    }
    let saved = session(accessToken: "token-1", refreshToken: "refresh-1")
    try store.save(saved)
    #expect(try other.load() == nil)
    try other.delete()
    #expect(try store.load() == saved)
  }

  /// The app and the extension each build their own store from the same service and group (ADR 0007): a second
  /// instance reads what the first saved, and sees it gone after the first deletes it.
  @Test func anotherStoreWithTheSameServiceAndGroupSharesTheRecord() throws {
    let group = try #require(
      Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String)
    let twin = KeychainSessionStore(
      service: "app.twake.ios.chat.tests.keychain-session-store", accessGroup: group)
    defer { try? store.delete() }
    let saved = session(accessToken: "token-1", refreshToken: "refresh-1")
    try store.save(saved)
    #expect(try twin.load() == saved)
    try store.delete()
    #expect(try twin.load() == nil)
  }

  /// Values a real server can return survive the round trip unchanged: a homeserver URL with a port and a path, a
  /// non-ASCII user id and a long token.
  @Test func unusualValuesRoundTrip() throws {
    defer { try? store.delete() }
    let saved = StoredSession(
      userId: "@zoë_ü:matrix.example.org", deviceId: "DEVICE+/=",
      homeserverURL: URL(string: "https://matrix.example.org:8448/base/path/")!,
      accessToken: String(repeating: "a1-_.", count: 1_000), refreshToken: "refresh/+=")
    try store.save(saved)
    #expect(try store.load() == saved)
  }

  /// The store really writes into the group it is given (ADR 0007): a group the app has no entitlement for is refused
  /// instead of the item silently landing in the app's default group.
  @Test func groupWithoutEntitlementIsRefused() throws {
    let unentitled = KeychainSessionStore(
      service: "app.twake.ios.chat.tests.keychain-session-store",
      accessGroup: "app.twake.ios.chat.tests.not-entitled")
    #expect(throws: KeychainSessionStoreError.self) {
      try unentitled.save(session(accessToken: "token-1", refreshToken: nil))
    }
    #expect(try store.load() == nil)
  }

  /// Refreshed tokens replace the saved session of the same user and device (TWAK-64, the SDK's session delegate).
  @Test func refreshedTokensUpdateTheSameSession() throws {
    defer { try? store.delete() }
    try store.save(session(accessToken: "token-1", refreshToken: "refresh-1"))
    let refreshed = session(accessToken: "token-2", refreshToken: "refresh-2")
    #expect(try store.saveRefreshedTokens(refreshed))
    #expect(try store.load() == refreshed)
  }

  /// A refresh that arrives after sign-out deleted the item (the race TWAK-63 deferred) does not bring it back.
  @Test func refreshedTokensAfterSignOutAreDropped() throws {
    try store.save(session(accessToken: "token-1", refreshToken: "refresh-1"))
    try store.delete()
    #expect(try !store.saveRefreshedTokens(session(accessToken: "token-2", refreshToken: "refresh-2")))
    #expect(try store.load() == nil)
  }

  /// Refreshed tokens of another device never replace the session that is saved now.
  @Test func refreshedTokensOfAnotherDeviceAreDropped() throws {
    defer { try? store.delete() }
    let saved = session(accessToken: "token-1", refreshToken: "refresh-1")
    try store.save(saved)
    let other = StoredSession(
      userId: "@alice:example.org", deviceId: "OTHER",
      homeserverURL: URL(string: "https://matrix.example.org")!,
      accessToken: "token-2", refreshToken: "refresh-2")
    #expect(try !store.saveRefreshedTokens(other))
    #expect(try store.load() == saved)
  }
}
