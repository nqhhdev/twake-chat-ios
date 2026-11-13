import Testing

@testable import MatrixData

/// The notification text: who and where, and what was sent (ADR 0009).
struct NotificationContentProxyTests {
  @Test func aDirectChatIsTitledWithTheSender() {
    let content = NotificationContentProxy.content(
      sender: "Alice", room: "Alice", isDirect: true, body: "Hi")
    #expect(content.title == "Alice")
    #expect(content.subtitle == "")
    #expect(content.body == "Hi")
  }

  @Test func aGroupIsTitledWithTheRoomAndTheSenderBelow() {
    let content = NotificationContentProxy.content(
      sender: "Alice", room: "Team", isDirect: false, body: "Hi")
    #expect(content.title == "Team")
    #expect(content.subtitle == "Alice")
  }

}
