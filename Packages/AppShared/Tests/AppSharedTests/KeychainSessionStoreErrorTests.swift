import AppShared
import Foundation
import Testing

struct KeychainSessionStoreErrorTests {
  @Test func equalityFollowsTheStatus() {
    #expect(
      KeychainSessionStoreError(status: errSecDecode)
        == KeychainSessionStoreError(status: errSecDecode))
    #expect(
      KeychainSessionStoreError(status: errSecDecode)
        != KeychainSessionStoreError(status: errSecMissingEntitlement))
  }

  /// The error carries the status code and nothing else, so it can never hold item data or a token (ADR 0007).
  @Test func carriesOnlyTheStatus() {
    let children = Mirror(reflecting: KeychainSessionStoreError(status: errSecDecode)).children
    #expect(children.map(\.label) == ["status"])
    #expect(children.first?.value as? OSStatus == errSecDecode)
  }
}
