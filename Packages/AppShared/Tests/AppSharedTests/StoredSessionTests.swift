import AppShared
import Foundation
import Testing

struct StoredSessionTests {
  private func session(refreshToken: String? = "refresh-secret") -> StoredSession {
    StoredSession(
      userId: "@alice:example.org", deviceId: "DEVICE",
      homeserverURL: URL(string: "https://matrix.example.org")!,
      accessToken: "access-secret", refreshToken: refreshToken)
  }

  @Test(arguments: ["refresh-secret", nil])
  func codableRoundTrip(refreshToken: String?) throws {
    let value = session(refreshToken: refreshToken)
    let decoded = try JSONDecoder().decode(StoredSession.self, from: JSONEncoder().encode(value))
    #expect(decoded == value)
  }

  /// The Keychain record holds the five session fields and nothing else: no recovery key (ADR 0007).
  @Test func encodesOnlyTheSessionFields() throws {
    let data = try JSONEncoder().encode(session())
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(
      Set(object.keys) == ["userId", "deviceId", "homeserverURL", "accessToken", "refreshToken"])
    #expect(!String(decoding: data, as: UTF8.self).lowercased().contains("recovery"))
  }

  @Test func descriptionsHideTheTokens() {
    let value = session()
    for text in [
      value.description, value.debugDescription, String(describing: value),
      String(reflecting: value),
    ] {
      #expect(!text.contains("access-secret"))
      #expect(!text.contains("refresh-secret"))
      #expect(text.contains("@alice:example.org"))
    }
  }
}
