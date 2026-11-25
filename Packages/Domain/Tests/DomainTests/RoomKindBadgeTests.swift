import Testing

@testable import Domain

struct RoomKindBadgeTests {
  private func room(
    space: Bool = false, broadcast: Bool = false, direct: Bool = false, isPublic: Bool = false
  ) -> RoomSummary {
    RoomSummary(
      id: "!r:example.org", name: "R", lastMessageText: nil, lastMessageSender: nil,
      lastActivity: nil, isDirect: direct, isSpace: space, isBroadcast: broadcast,
      isPublic: isPublic)
  }

  @Test func eachRoomKindGetsTheWebsBadge() {
    #expect(room(space: true).kindBadge == .space)
    #expect(room(space: true, isPublic: true).kindBadge == .space)
    #expect(room(broadcast: true).kindBadge == .broadcast)
    #expect(room(broadcast: true, isPublic: true).kindBadge == .broadcast)
    #expect(room(isPublic: true).kindBadge == .publicGroup)
    #expect(room().kindBadge == .group)
  }

  @Test func aDirectChatHasNoBadge() {
    #expect(room(direct: true).kindBadge == nil)
    #expect(room(direct: true, isPublic: true).kindBadge == nil)
  }
}
