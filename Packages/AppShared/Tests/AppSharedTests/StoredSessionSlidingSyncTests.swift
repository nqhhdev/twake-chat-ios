import AppShared
import Foundation
import Testing

/// TWAK-64 adds `slidingSyncVersion` to the Keychain record. A record saved by TWAK-63's build, without the key, must
/// still load, and a record with the key must keep it.
struct StoredSessionSlidingSyncTests {
  @Test func recordSavedBeforeTheFieldExistedStillDecodes() throws {
    let json = Data(
      """
      {"userId":"@alice:example.org","deviceId":"DEVICE","homeserverURL":"https:\\/\\/matrix.example.org",\
      "accessToken":"access-secret","refreshToken":"refresh-secret"}
      """.utf8)
    let decoded = try JSONDecoder().decode(StoredSession.self, from: json)
    #expect(
      decoded
        == StoredSession(
          userId: "@alice:example.org", deviceId: "DEVICE",
          homeserverURL: URL(string: "https://matrix.example.org")!,
          accessToken: "access-secret", refreshToken: "refresh-secret"))
    #expect(decoded.slidingSyncVersion == nil)
    #expect(decoded.authenticationIssuer == nil)
  }

  /// The SSO issuer of a token sign-in is kept for log out (ADR 0021).
  @Test func authenticationIssuerRoundTrips() throws {
    let value = StoredSession(
      userId: "@alice:example.org", deviceId: "DEVICE",
      homeserverURL: URL(string: "https://matrix.example.org")!,
      accessToken: "access-secret", refreshToken: nil, slidingSyncVersion: "native",
      authenticationIssuer: URL(string: "https://sign-up.example.org/")!)
    let decoded = try JSONDecoder().decode(StoredSession.self, from: JSONEncoder().encode(value))
    #expect(decoded == value)
    #expect(decoded.authenticationIssuer == URL(string: "https://sign-up.example.org/"))
  }

  @Test(arguments: ["native", "none"])
  func slidingSyncVersionRoundTrips(version: String) throws {
    let value = StoredSession(
      userId: "@alice:example.org", deviceId: "DEVICE",
      homeserverURL: URL(string: "https://matrix.example.org")!,
      accessToken: "access-secret", refreshToken: nil, slidingSyncVersion: version)
    let decoded = try JSONDecoder().decode(StoredSession.self, from: JSONEncoder().encode(value))
    #expect(decoded == value)
    #expect(decoded.slidingSyncVersion == version)
  }
}
