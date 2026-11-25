import Domain
import Foundation
import Testing

/// The reactions of the Activity are ordered and capped as the web's `buildActivity` (D58).
struct ActivityReactionTests {
  private func reaction(_ sender: String, at seconds: TimeInterval, key: String = "👍")
    -> ActivityReaction
  {
    ActivityReaction(
      roomId: "!team:x", roomName: "Team", eventId: "$1", key: key, senderId: sender,
      senderName: sender, reactedAt: Date(timeIntervalSince1970: seconds), messageText: "Hi")
  }

  @Test func newestFirst() {
    let list = ActivityReactions.newest(
      [reaction("@a:x", at: 1), reaction("@b:x", at: 3), reaction("@c:x", at: 2)],
      ownUserId: "@me:x")
    #expect(list.map(\.senderId) == ["@b:x", "@c:x", "@a:x"])
  }

  @Test func theUsersOwnReactionIsLeftOut() {
    let list = ActivityReactions.newest(
      [reaction("@me:x", at: 2), reaction("@a:x", at: 1)], ownUserId: "@me:x")
    #expect(list.map(\.senderId) == ["@a:x"])
  }

  @Test func fiftyAtMost() {
    let many = (0..<60).map { reaction("@a:x", at: TimeInterval($0), key: "\($0)") }
    let list = ActivityReactions.newest(many, ownUserId: "@me:x")
    #expect(list.count == ActivityReactions.limit)
    #expect(list.first?.key == "59")
  }

  @Test func theIdTellsApartTheKeyAndTheSender() {
    #expect(reaction("@a:x", at: 1).id != reaction("@b:x", at: 1).id)
    #expect(reaction("@a:x", at: 1, key: "👍").id != reaction("@a:x", at: 1, key: "🎉").id)
  }
}
