import AppShared
import Foundation
import Testing

/// What the Keychain item itself looks like after a save (ADR 0007): it is in the app's shared access group, readable
/// after first unlock on this device only (the extension reads it while the device is locked), not synced, and there
/// is only ever one. Hosted on the simulator for the app's entitlements; a test-only service keeps real sessions safe.
@Suite(.serialized)
struct KeychainSessionStoreItemTests {
  private static let service = "app.twake.ios.chat.tests.keychain-session-store.item"

  private let group: String
  private let store: KeychainSessionStore

  init() throws {
    group = try #require(
      Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String)
    store = KeychainSessionStore(service: Self.service, accessGroup: group)
    try store.delete()
  }

  private func session(accessToken: String) -> StoredSession {
    StoredSession(
      userId: "@alice:example.org", deviceId: "DEVICE",
      homeserverURL: URL(string: "https://matrix.example.org")!,
      accessToken: accessToken, refreshToken: "refresh-1")
  }

  /// Every item of the test service in the group, with its attributes.
  private func items() throws -> [[String: Any]] {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccessGroup as String: group,
      kSecUseDataProtectionKeychain as String: true,
      kSecReturnAttributes as String: true,
      kSecMatchLimit as String: kSecMatchLimitAll,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return [] }
    try #require(status == errSecSuccess, "SecItemCopyMatching returned \(status)")
    return try #require(result as? [[String: Any]])
  }

  /// The Info.plist value is the expanded `$(AppIdentifierPrefix)app.twake.ios.chat`, not the raw build setting.
  @Test func accessGroupIsExpanded() {
    #expect(!group.contains("$("))
    #expect(group.hasSuffix("app.twake.ios.chat"))
  }

  @Test func savedItemIsInTheGroupReadableAfterFirstUnlockOnThisDeviceOnly() throws {
    defer { try? store.delete() }
    try store.save(session(accessToken: "token-1"))
    let item = try #require(try items().first)
    #expect(item[kSecAttrAccessGroup as String] as? String == group)
    #expect(
      item[kSecAttrAccessible as String] as? String
        == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
    #expect((item[kSecAttrSynchronizable as String] as? Bool ?? false) == false)
  }

  @Test func overwriteKeepsExactlyOneItem() throws {
    defer { try? store.delete() }
    try store.save(session(accessToken: "token-1"))
    try store.save(session(accessToken: "token-2"))
    try store.save(session(accessToken: "token-3"))
    #expect(try items().count == 1)
    #expect(try store.load()?.accessToken == "token-3")
  }

  /// Secrets live only in the Keychain (ADR 0007): a save writes no token to the app's or the App Group's defaults.
  @Test func saveWritesNoTokenToUserDefaults() throws {
    defer { try? store.delete() }
    try store.save(session(accessToken: "token-in-keychain-only"))
    let suites = [
      UserDefaults.standard, UserDefaults(suiteName: AppGroupContainer.defaultGroupIdentifier),
    ]
    for defaults in suites.compactMap({ $0 }) {
      let dump = String(describing: defaults.dictionaryRepresentation())
      #expect(!dump.contains("token-in-keychain-only"))
      #expect(!dump.contains("refresh-1"))
    }
  }

  @Test func deleteRemovesTheItem() throws {
    try store.save(session(accessToken: "token-1"))
    try store.delete()
    #expect(try items().isEmpty)
  }

  /// A record that is not a session (damaged, or written by something else) makes `load` throw the store's error,
  /// which carries no item data, instead of crashing or returning a half-read session.
  @Test func damagedRecordMakesLoadThrow() throws {
    defer { try? store.delete() }
    try store.save(session(accessToken: "token-1"))
    let account = try #require(try items().first?[kSecAttrAccount as String] as? String)
    let match: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: Self.service,
      kSecAttrAccount as String: account,
      kSecAttrAccessGroup as String: group,
      kSecUseDataProtectionKeychain as String: true,
    ]
    let garbage: [String: Any] = [kSecValueData as String: Data("not a session".utf8)]
    try #require(SecItemUpdate(match as CFDictionary, garbage as CFDictionary) == errSecSuccess)
    #expect(throws: KeychainSessionStoreError.self) { try store.load() }
  }
}
