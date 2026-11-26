import ChatListTestSupport
import Domain
import Foundation
import Testing

@testable import ChatList

@MainActor
struct UndecryptedPreviewRetryTests {
  private static func room(_ id: String, kind: RoomSummary.MessageKind?) -> RoomSummary {
    RoomSummary(
      id: id, name: id, lastMessageText: nil, lastMessageSender: "Alice",
      lastActivity: Date(timeIntervalSince1970: 0), lastMessageKind: kind)
  }

  private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<10_000 where !condition() { await Task.yield() }
  }

  @Test func asksTheRepositoryToDecryptOnlyTheRoomsWhosePreviewIsStillEncrypted() async {
    let repository = FakeRoomListRepository()
    let viewModel = ChatListViewModel(repository: repository, logOut: { true })
    let task = Task { await viewModel.start() }
    await waitUntil { repository.isStarted }
    let rooms = [
      Self.room("!locked:example.org", kind: .encrypted),
      Self.room("!plain:example.org", kind: .text),
      Self.room("!empty:example.org", kind: nil),
      Self.room("!locked2:example.org", kind: .encrypted),
    ]
    repository.send(rooms)
    await waitUntil { viewModel.loadedRooms == rooms }
    await viewModel.retryUndecryptedPreviews()
    #expect(repository.retriedDecryption == [["!locked:example.org", "!locked2:example.org"]])
    task.cancel()
    await task.value
  }

  @Test func asksNothingWhenEveryPreviewIsReadable() async {
    let repository = FakeRoomListRepository()
    let viewModel = ChatListViewModel(repository: repository, logOut: { true })
    let task = Task { await viewModel.start() }
    await waitUntil { repository.isStarted }
    let rooms = [Self.room("!plain:example.org", kind: .text)]
    repository.send(rooms)
    await waitUntil { viewModel.loadedRooms == rooms }
    await viewModel.retryUndecryptedPreviews()
    #expect(repository.retriedDecryption.isEmpty)
    task.cancel()
    await task.value
  }
}
