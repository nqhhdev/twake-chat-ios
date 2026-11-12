import Foundation
import Security

/// The session record kept in the Keychain. AppShared does not import Domain (ADR 0005), so MatrixData maps this record
/// to `UserSession`. There is no recovery-key field: the recovery key is never stored (ADR 0007).
/// `description` and `debugDescription` leave the tokens out.
public struct StoredSession: Codable, Sendable, Equatable {
  public let userId: String
  public let deviceId: String
  public let homeserverURL: URL
  public let accessToken: String
  public let refreshToken: String?

  public init(
    userId: String, deviceId: String, homeserverURL: URL, accessToken: String, refreshToken: String?
  ) {
    self.userId = userId
    self.deviceId = deviceId
    self.homeserverURL = homeserverURL
    self.accessToken = accessToken
    self.refreshToken = refreshToken
  }
}

extension StoredSession: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    "StoredSession(userId: \(userId), deviceId: \(deviceId), homeserverURL: \(homeserverURL.absoluteString), tokens: <redacted>)"
  }

  public var debugDescription: String { description }
}

/// A Keychain call failed. Carries only the status code, never the item's data.
public struct KeychainSessionStoreError: Error, Sendable, Equatable {
  public let status: OSStatus

  public init(status: OSStatus) {
    self.status = status
  }
}

/// Saves, loads and deletes one `StoredSession` as a generic-password item in a Keychain access group shared by the app
/// and the Notification Service Extension (ADR 0007). The app passes `$(AppIdentifierPrefix)app.twake.ios.chat`
/// (ADR 0012). The item is readable after the first unlock, so the extension can read it while the device is locked,
/// and never leaves this device. Nothing here logs.
public struct KeychainSessionStore: Sendable {
  private static let account = "session"

  private let service: String
  private let accessGroup: String

  public init(service: String, accessGroup: String) {
    self.service = service
    self.accessGroup = accessGroup
  }

  /// Saves the session of a new sign-in, replacing any saved one.
  /// When the item is missing it is added; if another process (the app or the extension) adds it in between, the add
  /// reports a duplicate and the save falls back to one more update instead of failing.
  /// Token refresh is out of this card's scope: a later card adds it (and its race with sign-out) when it is needed.
  public func save(_ session: StoredSession) throws {
    let data = try encode(session)
    let label = Self.label(for: session)
    let status = update(data, label: label, matching: baseQuery())
    switch status {
    case errSecSuccess:
      return
    case errSecItemNotFound:
      var add = baseQuery()
      add[kSecValueData as String] = data
      add[kSecAttrLabel as String] = label
      add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      let addStatus = SecItemAdd(add as CFDictionary, nil)
      switch addStatus {
      case errSecSuccess:
        return
      case errSecDuplicateItem:
        let retryStatus = update(data, label: label, matching: baseQuery())
        guard retryStatus == errSecSuccess else {
          throw KeychainSessionStoreError(status: retryStatus)
        }
      default:
        throw KeychainSessionStoreError(status: addStatus)
      }
    default:
      throw KeychainSessionStoreError(status: status)
    }
  }

  private func encode(_ session: StoredSession) throws -> Data {
    do {
      return try JSONEncoder().encode(session)
    } catch {
      throw KeychainSessionStoreError(status: errSecParam)
    }
  }

  /// Names the session the item holds: user and device, which are not secrets.
  private static func label(for session: StoredSession) -> String {
    "\(session.userId)\n\(session.deviceId)"
  }

  private func update(_ data: Data, label: String, matching query: [String: Any]) -> OSStatus {
    let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrLabel as String: label]
    return SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
  }

  /// The saved session, or `nil` when none is saved.
  public func load() throws -> StoredSession? {
    var query = baseQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
    case errSecSuccess:
      guard let data = result as? Data else {
        throw KeychainSessionStoreError(status: errSecDecode)
      }
      do {
        return try JSONDecoder().decode(StoredSession.self, from: data)
      } catch {
        throw KeychainSessionStoreError(status: errSecDecode)
      }
    case errSecItemNotFound:
      return nil
    default:
      throw KeychainSessionStoreError(status: status)
    }
  }

  /// Deletes the saved session. Deleting when none is saved is not an error.
  public func delete() throws {
    let status = SecItemDelete(baseQuery() as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainSessionStoreError(status: status)
    }
  }

  private func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: Self.account,
      kSecAttrAccessGroup as String: accessGroup,
      kSecUseDataProtectionKeychain as String: true,
    ]
  }
}
