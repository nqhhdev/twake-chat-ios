import Foundation
import Testing

@testable import MatrixData

struct NotificationActionProxyTests {
  private func json(_ text: String?) throws -> [String: Any] {
    let text = try #require(text)
    return try #require(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
  }

  @Test func aReplyIsAPlainTextMessage() throws {
    let content = try json(
      NotificationActionProxy.replyContent(text: "  On my way \n", threadId: nil, eventId: "$e"))
    #expect(content["msgtype"] as? String == "m.text")
    #expect(content["body"] as? String == "On my way")
    #expect(content["m.relates_to"] == nil)
  }

  @Test func aReplyInAThreadStaysInTheThread() throws {
    let content = try json(
      NotificationActionProxy.replyContent(text: "Yes", threadId: "$root", eventId: "$e"))
    let relation = try #require(content["m.relates_to"] as? [String: Any])
    #expect(relation["rel_type"] as? String == "m.thread")
    #expect(relation["event_id"] as? String == "$root")
    #expect(relation["is_falling_back"] as? Bool == true)
    #expect((relation["m.in_reply_to"] as? [String: Any])?["event_id"] as? String == "$e")
  }

  @Test func anEmptyThreadIdIsNoThread() throws {
    let content = try json(
      NotificationActionProxy.replyContent(text: "Yes", threadId: "", eventId: "$e"))
    #expect(content["m.relates_to"] == nil)
  }

  @Test func blankTextSendsNothing() {
    #expect(NotificationActionProxy.replyContent(text: " \n ", threadId: nil, eventId: "$e") == nil)
  }
}
