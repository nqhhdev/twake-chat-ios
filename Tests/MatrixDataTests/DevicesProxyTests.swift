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

  @Test func anUnreadableAnswerIsAnEmptyList() {
    #expect(DevicesProxy.sessions(from: Data("nope".utf8), currentId: nil).isEmpty)
  }
}
