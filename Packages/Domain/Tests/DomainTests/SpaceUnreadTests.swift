import Testing

@testable import Domain

struct SpaceUnreadTests {
  private func room(
    _ id: String, unread: Int = 0, mentions: Int = 0, space: Bool = false,
    favourite: Bool = false, muted: Bool = false, markedUnread: Bool = false,
    invite: Bool = false, under: [String] = []
  ) -> RoomSummary {
    RoomSummary(
      id: id, name: id, lastMessageText: nil, lastMessageSender: nil, lastActivity: nil,
      unreadCount: unread, isMarkedUnread: markedUnread, mentionCount: mentions,
      isInvite: invite, isFavourite: favourite, isMuted: muted, isSpace: space,
      spaceDescendantIds: under)
  }

  @Test func aSpaceWithTwoUnreadRoomsShowsTwo() {
    let space = room("!s", space: true, under: ["!a", "!b", "!c"])
    let rooms = [space, room("!a", unread: 1), room("!b", unread: 1), room("!c")]
    #expect(SpaceUnread.of(space, in: rooms) == SpaceUnread(unread: 2, mentions: 0, muted: 0))
  }

  @Test func subSpacesAreCountedAndRoomsOutsideAreNot() {
    let space = room("!s", space: true, under: ["!sub", "!a", "!deep"])
    let rooms = [
      space, room("!sub", space: true), room("!a", unread: 3, mentions: 1),
      room("!deep", unread: 2), room("!elsewhere", unread: 9),
    ]
    #expect(SpaceUnread.of(space, in: rooms) == SpaceUnread(unread: 5, mentions: 1, muted: 0))
  }

  @Test func aFavouriteChannelIsNotCountedTwice() {
    let space = room("!s", space: true, under: ["!fav", "!a"])
    let rooms = [space, room("!fav", unread: 4, favourite: true), room("!a", unread: 1)]
    #expect(SpaceUnread.of(space, in: rooms).unread == 1)
  }

  @Test func mutedRoomsCountQuietlyAsTheAppBadgeDoes() {
    let space = room("!s", space: true, under: ["!m", "!a"])
    let quiet = [space, room("!m", unread: 5, mentions: 1, muted: true)]
    let quietUnread = SpaceUnread.of(space, in: quiet)
    #expect(quietUnread == SpaceUnread(unread: 0, mentions: 0, muted: 5))
    #expect(quietUnread.badgeCount == 5)
    #expect(quietUnread.isQuiet)
    let loud = quiet + [room("!a", unread: 1)]
    let loudUnread = SpaceUnread.of(space, in: loud)
    #expect(loudUnread.badgeCount == 1)
    #expect(!loudUnread.isQuiet)
  }

  @Test func aRoomMarkedUnreadCountsOneAndInvitationsNothing() {
    let space = room("!s", space: true, under: ["!marked", "!invite"])
    let rooms = [
      space, room("!marked", markedUnread: true), room("!invite", unread: 1, invite: true),
    ]
    #expect(SpaceUnread.of(space, in: rooms).unread == 1)
  }

  @Test func theGraphGivesEverySpaceAllItsDescendantsOnce() {
    let tree = SpaceGraph.descendants([
      SpaceNode(id: "!top", children: ["!a", "!sub"]),
      SpaceNode(id: "!sub", children: ["!b", "!subsub"]),
      SpaceNode(id: "!subsub", children: ["!c", "!a"]),
      SpaceNode(id: "!top", children: ["!a"]),
    ])
    #expect(tree["!top"] == ["!a", "!sub", "!b", "!subsub", "!c"])
    #expect(tree["!sub"] == ["!b", "!subsub", "!c", "!a"])
    #expect(tree["!subsub"] == ["!c", "!a"])
  }

  @Test func aLoopInTheGraphEnds() {
    let tree = SpaceGraph.descendants([
      SpaceNode(id: "!x", children: ["!y"]), SpaceNode(id: "!y", children: ["!x", "!r"]),
    ])
    #expect(tree["!x"] == ["!y", "!r"])
    #expect(tree["!y"] == ["!x", "!r"])
  }
}
