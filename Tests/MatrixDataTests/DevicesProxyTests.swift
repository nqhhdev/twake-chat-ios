import Foundation
import Testing

@testable import MatrixData

/// The devices list: this session first, then the others by last seen.
struct DevicesProxyTests {
  @Test func thisSessionComesFirstThenTheMostRecent() throws {
    let json = """
      {"devices":[
        {"device_id":"OLD","display_name":"Web","last_seen_ts":1000},
        {"device_id":"ME","display_name":"Twake Chat on iPhone","last_seen_ts":500},
        {"device_id":"NEW","last_seen_ts":3000}
      ]}
      """
    let sessions = DevicesProxy.sessions(from: Data(json.utf8), currentId: "ME")
    #expect(sessions.map(\.id) == ["ME", "NEW", "OLD"])
    #expect(sessions[0].isCurrent)
    #expect(sessions[1].name == "NEW")
    #expect(sessions[2].lastSeen == Date(timeIntervalSince1970: 1))
  }

  @Test func aChallengeOffersTheSingleSignOnPageAndThePassword() throws {
    let json = Data(
      #"{"session":"abc","flows":[{"stages":["m.login.sso"]},{"stages":["m.login.password"]}]}"#
        .utf8)
    let base = try #require(URL(string: "https://matrix.example.org/_matrix/client/v3/"))
    let challenge = try #require(DevicesProxy.challenge(from: json, homeserver: base))
    #expect(challenge.session == "abc")
    #expect(challenge.acceptsPassword)
    #expect(
      challenge.webURL?.absoluteString
        == "https://matrix.example.org/_matrix/client/v3/auth/m.login.sso/fallback/web?session=abc")
    #expect(DevicesProxy.challenge(from: Data("{}".utf8), homeserver: base) == nil)
  }

  @Test func anUnreadableAnswerIsAnEmptyList() {
    #expect(DevicesProxy.sessions(from: Data("nope".utf8), currentId: nil).isEmpty)
  }
}
