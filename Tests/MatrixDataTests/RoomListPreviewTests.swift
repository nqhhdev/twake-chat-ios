import Domain
import Foundation
import Testing

@testable import MatrixData

/// Which rooms the room list asks a preview for (`RoomListProxy.roomsMissingPreview`).
struct RoomListPreviewTests {
  private func room(
    _ id: String, text: String? = nil, invite: Bool = false, archived: Bool = false, space: Bool = false
  ) -> RoomSummary {
    RoomSummary(
      id: id, name: id, lastMessageText: text, lastMessageSender: nil, lastActivity: nil,
      isInvite: invite, isArchived: archived, isSpace: space)
  }

  @Test func onlyJoinedChatsWithoutAMessageAreAsked() {
    let rooms = [
      room("!blank"), room("!text", text: "hello"), room("!invite", invite: true),
      room("!left", archived: true), room("!space", space: true), room("!blank2"),
    ]
    #expect(RoomListProxy.roomsMissingPreview(in: rooms, alreadyAsked: []) == ["!blank", "!blank2"])
  }

  @Test func aRoomIsAskedOnceAndNoMoreThanTheLimits() {
    let rooms = (0..<50).map { room("!\($0)") }
    let first = RoomListProxy.roomsMissingPreview(in: rooms, alreadyAsked: [])
    #expect(first.count == RoomListProxy.previewBatch)
    let second = RoomListProxy.roomsMissingPreview(in: rooms, alreadyAsked: Set(first))
    #expect(Set(first).isDisjoint(with: second))
    let full = Set((0..<RoomListProxy.previewLimit).map { "!asked\($0)" })
    #expect(RoomListProxy.roomsMissingPreview(in: rooms, alreadyAsked: full).isEmpty)
  }
}
