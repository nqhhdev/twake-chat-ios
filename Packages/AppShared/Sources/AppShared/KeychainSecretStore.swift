import Foundation
import Security

public struct KeychainSecretStore: Sendable {
  private let service: String
  private let accessGroup: String?

  public init(service: String, accessGroup: String?) {
    self.service = service
    self.accessGroup = accessGroup
  }

  public func save(_ secret: String, account: String) throws {
    let data = Data(secret.utf8)
    let query = baseQuery(account)
    let status = SecItemUpdate(
      query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    switch status {
    case errSecSuccess:
      return
    case errSecItemNotFound:
      var add = query
      add[kSecValueData as String] = data
      add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      let addStatus = SecItemAdd(add as CFDictionary, nil)
      guard addStatus == errSecSuccess else { throw KeychainSessionStoreError(status: addStatus) }
    default:
      throw KeychainSessionStoreError(status: status)
    }
  }

  public func load(account: String) -> String? {
    var query = baseQuery(account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return String(data: data, encoding: .utf8)
  }

  public func delete(account: String) {
    SecItemDelete(baseQuery(account) as CFDictionary)
  }

  private func baseQuery(_ account: String) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
    return query
  }
}
