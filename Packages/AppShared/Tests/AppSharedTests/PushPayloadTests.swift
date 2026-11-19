import Foundation
import Testing

@testable import AppShared

/// The badge count the notification service extension takes from the push (`unread_count`).
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
}
