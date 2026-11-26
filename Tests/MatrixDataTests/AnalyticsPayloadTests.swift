import Domain
import Foundation
import Testing

@testable import MatrixData

struct AnalyticsPayloadTests {
  private let at = Date(timeIntervalSince1970: 1_760_000_000)

  @Test func theConsentIsWrittenAsTheWebWritesIt() throws {
    let json = try #require(AnalyticsPayload.json(AnalyticsConsent(granted: true, at: at)))
    #expect(json == #"{"at":"2025-10-09T08:53:20.000Z","granted":true}"#)
    #expect(
      AnalyticsPayload.consent(fromJSON: Data(json.utf8)) == AnalyticsConsent(granted: true, at: at)
    )
  }

  @Test func aConsentWithoutAReadableDateIsStillAChoice() {
    #expect(
      AnalyticsPayload.consent(fromJSON: Data(#"{"granted":false,"at":"yesterday"}"#.utf8))?.granted
        == false)
    #expect(AnalyticsPayload.consent(fromJSON: Data(#"{"at":"2025-10-09T08:53:20Z"}"#.utf8)) == nil)
  }

  @Test func eventsLeaveInOneBatchWithTheAppAndItsVersion() throws {
    let data = try #require(
      AnalyticsPayload.body(
        [
          AnalyticsEvent(
            name: "room_opened",
            properties: ["roomId": .string("!a:x"), "count": .int(2), "isReply": .bool(false)],
            at: at)
        ], appVersion: "1.4.0"))
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["app"] as? String == "twake-chat")
    #expect(object["version"] as? String == "1.4.0")
    let event = try #require((object["events"] as? [[String: Any]])?.first)
    #expect(event["name"] as? String == "room_opened")
    #expect(event["at"] as? String == "2025-10-09T08:53:20.000Z")
    let properties = try #require(event["properties"] as? [String: Any])
    #expect(properties["roomId"] as? String == "!a:x")
    #expect(properties["count"] as? Int == 2)
    #expect(properties["isReply"] as? Bool == false)
  }
}
