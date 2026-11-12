import Domain
import Foundation
import Testing

struct UserSessionTests {
  private let homeserver = URL(string: "https://matrix.example.org")!

  private func session(refreshToken: String? = "refresh-secret") -> UserSession {
    UserSession(
      userId: "@alice:example.org", deviceId: "DEVICE", homeserverURL: homeserver,
      accessToken: "access-secret", refreshToken: refreshToken)
  }

  @Test func keepsItsFields() {
    let value = session()
    #expect(value.userId == "@alice:example.org")
    #expect(value.deviceId == "DEVICE")
    #expect(value.homeserverURL == homeserver)
    #expect(value.accessToken == "access-secret")
    #expect(value.refreshToken == "refresh-secret")
  }

  @Test func refreshTokenMayBeNil() {
    #expect(session(refreshToken: nil).refreshToken == nil)
  }

  @Test func equalityComparesEveryField() {
    #expect(session() == session())
    #expect(session() != session(refreshToken: nil))
  }

  /// Two sessions that differ in any one field are not equal.
  @Test(arguments: 0..<5)
  func sessionsDifferingInOneFieldAreNotEqual(field: Int) {
    let base = session()
    let other = UserSession(
      userId: field == 0 ? "@bob:example.org" : base.userId,
      deviceId: field == 1 ? "OTHERDEVICE" : base.deviceId,
      homeserverURL: field == 2 ? URL(string: "https://other.example.org")! : base.homeserverURL,
      accessToken: field == 3 ? "other-access" : base.accessToken,
      refreshToken: field == 4 ? "other-refresh" : base.refreshToken)
    #expect(base != other)
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
