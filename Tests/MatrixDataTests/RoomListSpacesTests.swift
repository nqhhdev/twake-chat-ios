import Domain
import Foundation
import Testing

@testable import MatrixData

struct RoomListSpacesTests {
  private func room(_ id: String, space: Bool = false) -> RoomSummary {
    RoomSummary(
      id: id, name: id, lastMessageText: nil, lastMessageSender: nil, lastActivity: nil,
      isSpace: space)
  }

  @Test func eachSpaceGetsTheRoomsUnderItAndRoomsGetNothing() {
    let rooms = [room("!s", space: true), room("!a"), room("!empty", space: true)]
    let tree = ["!s": ["!a", "!b"], "!a": ["!x"]]
    let result = RoomListProxy.withSpaces(tree, rooms)
    #expect(result.map(\.spaceDescendantIds) == [["!a", "!b"], [], []])
  }
}
