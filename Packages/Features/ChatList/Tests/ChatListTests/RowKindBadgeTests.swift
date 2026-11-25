import Domain
import Testing

@testable import ChatList

struct RowKindBadgeTests {
  @Test func eachBadgeHasItsOwnSymbolAndAVoiceOverLabel() {
    let symbols = RoomKindBadge.allCases.map(\.systemImage)
    #expect(Set(symbols).count == RoomKindBadge.allCases.count)
    #expect(RoomKindBadge.space.systemImage == "cube.fill")
    #expect(RoomKindBadge.broadcast.systemImage == "megaphone.fill")
    #expect(RoomKindBadge.publicGroup.systemImage == "globe")
    #expect(RoomKindBadge.group.systemImage == "person.2.fill")
    #expect(RoomKindBadge.publicGroup.accessibilityLabel == "Public group")
    #expect(RoomKindBadge.allCases.allSatisfy { !$0.accessibilityLabel.isEmpty })
  }
}
