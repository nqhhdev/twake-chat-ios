import ChatListTestSupport
import Domain
import Foundation
import Testing

@testable import ChatList

@MainActor
struct MarkAllReadTests {
  private static func room(
    _ id: String, unreadCount: Int = 0, isMarkedUnread: Bool = false, isInvite: Bool = false,
    isMuted: Bool = false, isSpace: Bool = false, isFavourite: Bool = false
  ) -> RoomSummary {
    RoomSummary(
      id: id, name: id, lastMessageText: nil, lastMessageSender: nil, lastActivity: nil,
      unreadCount: unreadCount, isMarkedUnread: isMarkedUnread, isInvite: isInvite,
      isFavourite: isFavourite, isMuted: isMuted, isSpace: isSpace)
  }

  private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<10_000 where !condition() { await Task.yield() }
  }

  private func loaded(_ rooms: [RoomSummary]) async -> (
    ChatListViewModel, FakeRoomListRepository, Task<Void, Never>
  ) {
    let repository = FakeRoomListRepository()
    let viewModel = ChatListViewModel(repository: repository, logOut: { true })
    let task = Task { await viewModel.start() }
    await waitUntil { repository.isStarted }
    repository.send(rooms)
    await waitUntil { viewModel.state == .loaded(rooms) }
    return (viewModel, repository, task)
  }

  @Test func unreadRoomsAreTheJoinedRoomsWithSomethingUnread() async {
    let rooms = [
      Self.room("!a", unreadCount: 2),
      Self.room("!b"),
      Self.room("!c", isMarkedUnread: true),
      Self.room("!d", unreadCount: 1, isMuted: true),
      Self.room("!e", unreadCount: 1, isInvite: true),
      Self.room("!f", unreadCount: 1, isSpace: true),
    ]
    let (viewModel, _, task) = await loaded(rooms)
    #expect(viewModel.unreadRooms.map(\.id) == ["!a", "!c", "!d"])
    task.cancel()
    await task.value
  }

  @Test func unreadRoomsIgnoreTheSearchAndTheFilter() async {
    let rooms = [
      Self.room("!a", unreadCount: 1),
      Self.room("!b", unreadCount: 1, isFavourite: true),
    ]
    let (viewModel, _, task) = await loaded(rooms)
    viewModel.filter = .favourites
    viewModel.query = "!b"
    #expect(viewModel.unreadRooms.map(\.id) == ["!a", "!b"])
    task.cancel()
    await task.value
  }

  @Test func markAllReadMarksEachGivenRoomRead() async {
    let rooms = [Self.room("!a", unreadCount: 2), Self.room("!b", isMarkedUnread: true)]
    let (viewModel, repository, task) = await loaded(rooms)
    await viewModel.markAllRead(viewModel.unreadRooms)
    #expect(repository.decisions == ["read !a", "read !b"])
    #expect(viewModel.actionErrorMessage == nil)
    task.cancel()
    await task.value
  }

  @Test func markAllReadWithNothingUnreadSendsNothing() async {
    let (viewModel, repository, task) = await loaded([Self.room("!a")])
    await viewModel.markAllRead(viewModel.unreadRooms)
    #expect(repository.decisions.isEmpty)
    task.cancel()
    await task.value
  }
}
