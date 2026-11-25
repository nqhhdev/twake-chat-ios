import Foundation
import Testing

@testable import AppShared

struct PushPayloadTests {
  @Test func theCountIsRead() {
    #expect(PushPayload.unreadCount(in: ["unread_count": 3, "room_id": "!a:b"]) == 3)
  }

  @Test func zeroIsACount() {
    #expect(PushPayload.unreadCount(in: ["unread_count": 0]) == 0)
  }

  @Test func theCountAsTheJsonDecoderGivesIt() throws {
    let json = Data(#"{"unread_count": 7, "event_id": "$e"}"#.utf8)
    let userInfo = try #require(try JSONSerialization.jsonObject(with: json) as? [AnyHashable: Any])
    #expect(PushPayload.unreadCount(in: userInfo) == 7)
  }

  @Test func noCountLeavesTheBadgeAlone() {
    #expect(PushPayload.unreadCount(in: ["room_id": "!a:b"]) == nil)
  }

  @Test func aValueThatIsNotACountIsIgnored() {
    #expect(PushPayload.unreadCount(in: ["unread_count": "3"]) == nil)
    #expect(PushPayload.unreadCount(in: ["unread_count": -1]) == nil)
  }

  @Test func theRoomEventAndThreadAreRead() {
    let userInfo: [AnyHashable: Any] = ["room_id": "!r:b", "event_id": "$e", "thread_id": "$t"]
    #expect(PushPayload.roomId(in: userInfo) == "!r:b")
    #expect(PushPayload.eventId(in: userInfo) == "$e")
    #expect(PushPayload.threadId(in: userInfo) == "$t")
  }

  @Test func missingEmptyOrWronglyTypedIdsAreNil() {
    let userInfo: [AnyHashable: Any] = ["room_id": "", "event_id": 3]
    #expect(PushPayload.roomId(in: userInfo) == nil)
    #expect(PushPayload.eventId(in: userInfo) == nil)
    #expect(PushPayload.threadId(in: userInfo) == nil)
  }
}
