import Domain
import Foundation
import Testing

@testable import MatrixData

struct DelayedEventsTests {
  @Test func onlyAServerAnnouncingMsc4140CanSchedule() {
    #expect(DelayedEvents.supports(["unstable_features": ["org.matrix.msc4140": true]]))
    #expect(!DelayedEvents.supports(["unstable_features": ["org.matrix.msc4140": false]]))
    #expect(!DelayedEvents.supports(["versions": ["v1.11"]]))
  }

  @Test func theDelayIsInMillisecondsAndAtLeastOneSecond() {
    let now = Date(timeIntervalSince1970: 1000)
    #expect(DelayedEvents.delay(until: now.addingTimeInterval(90), now: now) == 90_000)
    #expect(DelayedEvents.delay(until: now.addingTimeInterval(-5), now: now) == 1000)
  }

  @Test func aPlainTextIsSentWithoutHtmlAndWithEmptyMentions() {
    let content = DelayedEvents.content(text: "See you", replyTo: nil)
    #expect(content["msgtype"] as? String == "m.text")
    #expect(content["body"] as? String == "See you")
    #expect(content["formatted_body"] == nil)
    #expect((content["m.mentions"] as? [String: Any])?.isEmpty == true)
    #expect(content["m.relates_to"] == nil)
  }

  @Test func aFormattedReplyCarriesItsHtmlMentionsAndReply() {
    let content = DelayedEvents.content(
      text: "/me thanks **[Bob](https://matrix.to/#/@bob:example.org)**", replyTo: "$q")
    #expect(content["msgtype"] as? String == "m.emote")
    #expect(
      content["formatted_body"] as? String
        == "thanks <a href=\"https://matrix.to/#/@bob:example.org\"><strong>Bob</strong></a>")
    #expect(content["format"] as? String == "org.matrix.custom.html")
    let mentions = content["m.mentions"] as? [String: Any]
    #expect(mentions?["user_ids"] as? [String] == ["@bob:example.org"])
    let relation = content["m.relates_to"] as? [String: Any]
    #expect((relation?["m.in_reply_to"] as? [String: Any])?["event_id"] as? String == "$q")
  }

  @Test func theListKeepsThisRoomsTextMessagesInSendingOrder() {
    let response: [String: Any] = [
      "delayed_events": [
        [
          "delay_id": "late", "room_id": "!r", "type": "m.room.message", "delay": 120_000,
          "running_since": 1_000_000, "content": ["msgtype": "m.text", "body": "Later"],
        ],
        [
          "delay_id": "soon", "room_id": "!r", "type": "m.room.message", "delay": 60_000,
          "running_since": 1_000_000,
          "content": [
            "msgtype": "m.emote", "body": "waves",
            "m.relates_to": ["m.in_reply_to": ["event_id": "$q"]],
          ],
        ],
        [
          "delay_id": "other", "room_id": "!x", "type": "m.room.message", "delay": 1,
          "content": ["msgtype": "m.text", "body": "Elsewhere"],
        ],
        [
          "delay_id": "state", "room_id": "!r", "type": "m.room.message", "state_key": "",
          "delay": 1, "content": ["msgtype": "m.text", "body": "State"],
        ],
      ]
    ]
    let list = DelayedEvents.scheduled(response, roomId: "!r")
    #expect(list.map(\.id) == ["soon", "late"])
    #expect(list[0].text == "/me waves")
    #expect(list[0].replyTo == "$q")
    #expect(list[0].sendAt == Date(timeIntervalSince1970: 1060))
    #expect(
      DelayedEvents.scheduled(["scheduled": response["delayed_events"]!], roomId: "!r").count == 2)
  }

  @Test func theServersRefusalsAreNamed() {
    func body(_ object: [String: Any]) -> Data {
      (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }
    #expect(
      DelayedEvents.error(
        status: 400,
        body: body([
          "errcode": "M_UNKNOWN", "org.matrix.msc4140.errcode": "M_MAX_DELAY_EXCEEDED",
          "org.matrix.msc4140.max_delay": 86_400_000,
        ])) == .delayTooLong(maxDelay: 86_400))
    #expect(
      DelayedEvents.error(status: 429, body: body(["errcode": "M_LIMIT_EXCEEDED"])) == .tooMany)
    #expect(
      DelayedEvents.error(status: 400, body: body(["errcode": "M_UNRECOGNIZED"])) == .unsupported)
    #expect(DelayedEvents.error(status: 500, body: Data()) == .failed)
  }
}
