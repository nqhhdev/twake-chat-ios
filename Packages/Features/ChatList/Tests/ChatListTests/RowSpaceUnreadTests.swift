import ChatListTestSupport
import Domain
import Foundation
import Testing

@testable import ChatList

@MainActor
struct RowSpaceUnreadTests {
  private func room(
    _ id: String, unread: Int = 0, space: Bool = false, under: [String] = []
  ) -> RoomSummary {
    RoomSummary(
      id: id, name: id, lastMessageText: nil, lastMessageSender: nil, lastActivity: nil,
      unreadCount: unread, isSpace: space, spaceDescendantIds: under)
  }

  private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<10_000 where !condition() { await Task.yield() }
  }

  @Test func aSpaceRowCountsTheUnreadOfItsRoomsAndAChatRowHasNone() async {
    let repository = FakeRoomListRepository()
    let viewModel = ChatListViewModel(repository: repository, logOut: { true })
    let task = Task { await viewModel.start() }
    await waitUntil { repository.isStarted }
    let space = room("!s", space: true, under: ["!a", "!b"])
    let chat = room("!a", unread: 1)
    repository.send([space, chat, room("!b", unread: 1), room("!c", unread: 7)])
    await waitUntil { viewModel.state != .loading }
    #expect(viewModel.spaceUnread(of: space)?.badgeCount == 2)
    #expect(viewModel.spaceUnread(of: chat) == nil)
    task.cancel()
  }
}
