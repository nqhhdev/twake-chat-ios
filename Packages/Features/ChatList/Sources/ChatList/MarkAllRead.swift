import Domain
import SwiftUI

extension ChatListViewModel {
  public var unreadRooms: [RoomSummary] {
    allJoinedRooms.filter { $0.isUnread && !$0.isSpace }
  }

  public func markAllRead(_ rooms: [RoomSummary]) async {
    for room in rooms { await setUnread(false, room: room) }
  }
}

struct MarkAllReadButton: View {
  let viewModel: ChatListViewModel
  let rooms: [RoomSummary]

  var body: some View {
    Button(localized("Mark All as Read"), systemImage: "envelope.open") {
      Task { await viewModel.markAllRead(rooms) }
    }
    .disabled(rooms.isEmpty)
  }
}
