import ChatListTestSupport
import Domain
import Foundation
import Testing

@testable import ChatList

@MainActor
struct SearchResultsTests {
  private struct Search: RoomSearchRepository {
    let found: [RoomSearchResult]

    func search(_ term: String, roomId: String, from nextBatch: String?)
      async throws(RoomSearchError) -> RoomSearchPage
    {
      RoomSearchPage(results: [], nextBatch: nil)
    }

    func searchEverywhere(_ term: String, from nextBatch: String?)
      async throws(RoomSearchError) -> RoomSearchPage
    {
      RoomSearchPage(results: found, nextBatch: nil)
    }
  }

  private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<10_000 where !condition() { await Task.yield() }
  }

  private let chat = RoomSummary(
    id: "!chat:example.org", name: "E2E Chat", lastMessageText: "Hello from Bob",
    lastMessageSender: "Bob", lastActivity: nil)

  private func loaded(found: [RoomSearchResult]) async -> (ChatListViewModel, Task<Void, Never>) {
    let repository = FakeRoomListRepository()
    let viewModel = ChatListViewModel(
      repository: repository, messageSearch: Search(found: found), logOut: { true })
    let task = Task { await viewModel.start() }
    await waitUntil { repository.isStarted }
    repository.send([chat])
    await waitUntil { viewModel.state != .loading }
    return (viewModel, task)
  }

  @Test func aMessageFoundOnTheServerShowsWhenNoChatNameMatches() async {
    let (viewModel, task) = await loaded(found: [
      RoomSearchResult(
        eventId: "$hello", senderId: "@bob:example.org", senderName: "Bob", date: .now,
        text: "Hello from Bob", roomId: "!chat:example.org")
    ])
    viewModel.query = "Hello from Bob"
    #expect(viewModel.visibleRooms.isEmpty)
    await viewModel.searchMessages()
    #expect(viewModel.messageResults.map(\.eventId) == ["$hello"])
    #expect(!viewModel.showsNoResults)
    task.cancel()
  }

  @Test func nothingFoundAnywhereSaysNoResults() async {
    let (viewModel, task) = await loaded(found: [])
    viewModel.query = "Nothing like this"
    await viewModel.searchMessages()
    #expect(viewModel.showsNoResults)
    viewModel.query = "E2E"
    #expect(!viewModel.showsNoResults)
    task.cancel()
  }
}
