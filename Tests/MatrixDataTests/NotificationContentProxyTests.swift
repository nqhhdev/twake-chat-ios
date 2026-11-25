import Testing

@testable import MatrixData

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

  @Test func aMessageCarriesWhatTheCommunicationNotificationNeeds() {
    let content = NotificationContentProxy.content(
      senderId: "@alice:b", sender: "Alice", room: "Team", isDirect: false, body: "Hi",
      threadId: "$root", isMessage: true)
    #expect(content.senderId == "@alice:b")
    #expect(content.senderName == "Alice")
    #expect(content.roomName == "Team")
    #expect(!content.isDirect)
    #expect(content.threadId == "$root")
    #expect(content.isMessage)
    #expect(content.senderAvatar == nil)
    #expect(content.roomAvatar == nil)
  }

  @Test func anInviteIsNotAMessageByDefault() {
    let content = NotificationContentProxy.content(
      senderId: "@alice:b", sender: "Alice", room: "Alice", isDirect: true,
      body: "Invited you to chat")
    #expect(!content.isMessage)
    #expect(content.threadId == nil)
  }
}
