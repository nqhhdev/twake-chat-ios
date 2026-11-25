import Foundation
import Security

public struct StoredSession: Codable, Sendable, Equatable {
  public let userId: String
  public let deviceId: String
  public let homeserverURL: URL
  public let accessToken: String
  public let refreshToken: String?
  public let slidingSyncVersion: String?
  public let authenticationIssuer: URL?

  public init(
    userId: String, deviceId: String, homeserverURL: URL, accessToken: String,
    refreshToken: String?, slidingSyncVersion: String? = nil, authenticationIssuer: URL? = nil
  ) {
    self.userId = userId
    self.deviceId = deviceId
    self.homeserverURL = homeserverURL
    self.accessToken = accessToken
    self.refreshToken = refreshToken
    self.slidingSyncVersion = slidingSyncVersion
    self.authenticationIssuer = authenticationIssuer
  }
}

extension StoredSession: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    "StoredSession(userId: \(userId), deviceId: \(deviceId), homeserverURL: \(homeserverURL.absoluteString), tokens: <redacted>)"
  }

  public var debugDescription: String { description }
}

public struct KeychainSessionStoreError: Error, Sendable, Equatable {
  public let status: OSStatus

  public init(status: OSStatus) {
    self.status = status
  }
}

public struct KeychainSessionStore: Sendable {
  public static let defaultAccount = "session"

  private let service: String
  private let accessGroup: String
  private let account: String

  public init(service: String, accessGroup: String, account: String = defaultAccount) {
    self.service = service
    self.accessGroup = accessGroup
    self.account = account
  }

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

  @discardableResult
  public func saveRefreshedTokens(_ session: StoredSession) throws -> Bool {
    var query = baseQuery()
    query[kSecAttrLabel as String] = Self.label(for: session)
    let status = update(try encode(session), label: Self.label(for: session), matching: query)
    switch status {
    case errSecSuccess: return true
    case errSecItemNotFound: return false
    default: throw KeychainSessionStoreError(status: status)
    }
  }

  private func encode(_ session: StoredSession) throws -> Data {
    do {
      return try JSONEncoder().encode(session)
    } catch {
      throw KeychainSessionStoreError(status: errSecParam)
    }
  }

  private static func label(for session: StoredSession) -> String {
    "\(session.userId)\n\(session.deviceId)"
  }

  private func update(_ data: Data, label: String, matching query: [String: Any]) -> OSStatus {
    let attributes: [String: Any] = [kSecValueData as String: data, kSecAttrLabel as String: label]
    return SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
  }

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
      kSecAttrAccount as String: account,
      kSecAttrAccessGroup as String: accessGroup,
      kSecUseDataProtectionKeychain as String: true,
    ]
  }
}
