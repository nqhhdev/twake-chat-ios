import Foundation
import Testing

@testable import MatrixData

/// The server search: what the request asks and how the answer reads.
struct RoomSearchProxyTests {
  @Test func theRequestSearchesOneRoomNewestFirstWithProfiles() throws {
    let data = try #require(RoomSearchProxy.body(term: "lunch", roomId: "!r:example.org"))
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let categories = try #require(object["search_categories"] as? [String: Any])
    let roomEvents = try #require(categories["room_events"] as? [String: Any])
    #expect(roomEvents["search_term"] as? String == "lunch")
    #expect(roomEvents["order_by"] as? String == "recent")
    let filter = try #require(roomEvents["filter"] as? [String: Any])
    #expect(filter["rooms"] as? [String] == ["!r:example.org"])
    #expect(filter["limit"] as? Int == 20)
    let context = try #require(roomEvents["event_context"] as? [String: Any])
    #expect(context["include_profile"] as? Bool == true)
  }

  @Test func theAnswerGivesMessagesWithSenderNamesAndTheNextPage() {
    let json = """
      {"search_categories":{"room_events":{"next_batch":"b2","results":[
        {"rank":1,"result":{"event_id":"$1","sender":"@alice:example.org","origin_server_ts":2000,
          "type":"m.room.message","content":{"msgtype":"m.text","body":"lunch at noon"}},
         "context":{"profile_info":{"@alice:example.org":{"displayname":"Alice"}}}},
        {"rank":1,"result":{"event_id":"$2","sender":"@bob:example.org","origin_server_ts":1000,
          "type":"m.room.message","content":{"msgtype":"m.text","body":"lunch?"}}},
        {"rank":1,"result":{"event_id":"$3","sender":"@bob:example.org","content":{}}}
      ]}}}
      """
    let page = RoomSearchProxy.page(from: Data(json.utf8))
    #expect(page.nextBatch == "b2")
    #expect(page.results.map(\.eventId) == ["$1", "$2"])
    #expect(page.results.map(\.senderName) == ["Alice", "@bob:example.org"])
    #expect(page.results[0].date == Date(timeIntervalSince1970: 2))
    #expect(page.results[0].text == "lunch at noon")
  }

  @Test func anUnreadableAnswerIsAnEmptyLastPage() {
    let page = RoomSearchProxy.page(from: Data("nope".utf8))
    #expect(page.results.isEmpty)
    #expect(page.nextBatch == nil)
  }
}
