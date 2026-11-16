import Testing

@testable import Room

struct EmptyChatCardTests {
  @Test func aGroupListsWhatItOffersAndEncryptionOnlyWhenItHasIt() {
    let clear = EmptyChatCard.card(
      roomName: "Team", isDirect: false, isBroadcast: false, isEncrypted: false, canPost: true)
    #expect(clear.title == "Congratulations on your new chat!")
    #expect(
      clear.points == [
        "Up to 100,000 members", "Persistent chat history", "Admins with different rights",
      ])
    let encrypted = EmptyChatCard.card(
      roomName: "Team", isDirect: false, isBroadcast: false, isEncrypted: true, canPost: true)
    #expect(encrypted.points.contains("End-to-end encrypted messages"))
  }

  @Test func aDirectChatInvitesAFirstMessage() {
    let card = EmptyChatCard.card(
      roomName: "Bob", isDirect: true, isBroadcast: false, isEncrypted: false, canPost: true)
    #expect(card.title == "No message here yet")
    #expect(card.description == "Send a message to start the conversation")
    #expect(card.points.isEmpty)
  }

  @Test func aBroadcastSaysWhatItIsAlsoToAReader() {
    let card = EmptyChatCard.card(
      roomName: "News", isDirect: false, isBroadcast: true, isEncrypted: false, canPost: false)
    #expect(card.title == "Channel “News” is created")
    #expect(card.description?.hasPrefix("A broadcast channel shares news") == true)
  }

  @Test func someoneWhoMayNotPostIsNotInvitedToWrite() {
    let card = EmptyChatCard.card(
      roomName: "Team", isDirect: false, isBroadcast: false, isEncrypted: true, canPost: false)
    #expect(card == EmptyChatCard(title: "No message here yet", description: nil, points: []))
  }
}
