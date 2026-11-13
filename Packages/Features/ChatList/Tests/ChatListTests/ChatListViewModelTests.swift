import ChatListTestSupport
import Domain
import Foundation
import Testing

@testable import ChatList

@MainActor
struct ChatListViewModelTests {
  private static func room(
    _ id: String, _ name: String, text: String?, sender: String? = "Alice",
    at seconds: TimeInterval = 0
  ) -> RoomSummary {
    RoomSummary(
      id: id, name: name, lastMessageText: text, lastMessageSender: sender,
      lastActivity: Date(timeIntervalSince1970: seconds))
  }

  private let team = room("!team:example.org", "Team", text: "Hello", at: 10)
  private let family = room("!family:example.org", "Family", text: "Dinner?", at: 5)

  /// Waits, yielding to the view model's task, until `condition` holds.
  private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<10_000 where !condition() { await Task.yield() }
  }

  @Test func startsLoading() {
    let viewModel = ChatListViewModel(repository: FakeRoomListRepository(), logOut: { true })
    #expect(viewModel.state == .loading)
  }

  @Test func initialLoadShowsTheRoomsInTheRepositoryOrder() async {
    let repository = FakeRoomListRepository()
    let viewModel = ChatListViewModel(repository: repository, logOut: { true })
    let task = Task { await viewModel.start() }
    await waitUntil { repository.isStarted }
    repository.send([team, family])
    await waitUntil { viewModel.state != .loading }
    #expect(viewModel.state == .loaded([team, family]))
    task.cancel()
    await task.value
  }

  @Test func liveUpdateReordersTheListAndChangesThePreview() async {
    let repository = FakeRoomListRepository()
    let viewModel = ChatListViewModel(repository: repository, logOut: { true })
    let task = Task { await viewModel.start() }
    await waitUntil { repository.isStarted }
    repository.send([team, family])
    await waitUntil { viewModel.state == .loaded([team, family]) }
    let newFamily = Self.room(
      "!family:example.org", "Family", text: "On my way", sender: "Bob", at: 20)
    repository.send([newFamily, team])
    await waitUntil { viewModel.state == .loaded([newFamily, team]) }
    #expect(viewModel.state == .loaded([newFamily, team]))
    #expect(ChatListViewModel.preview(of: newFamily) == "Bob: On my way")
    task.cancel()
    await task.value
  }

  @Test func anEmptyListShowsTheEmptyState() async {
    let repository = FakeRoomListRepository()
    let viewModel = ChatListViewModel(repository: repository, logOut: { true })
    let task = Task { await viewModel.start() }
    await waitUntil { repository.isStarted }
    repository.send([])
    await waitUntil { viewModel.state != .loading }
    #expect(viewModel.state == .empty)
    task.cancel()
    await task.value
  }

  @Test(arguments: [RoomListError.notSignedIn, .syncUnavailable])
  func aStartErrorShowsAnErrorMessage(error: RoomListError) async {
    let repository = FakeRoomListRepository()
    repository.startError = error
    let viewModel = ChatListViewModel(repository: repository, logOut: { true })
    await viewModel.start()
    #expect(viewModel.state == .failed("Could not load your rooms."))
  }

  @Test func theListStopsWhenTheScreenGoesAway() async {
    let repository = FakeRoomListRepository()
    let viewModel = ChatListViewModel(repository: repository, logOut: { true })
    let task = Task { await viewModel.start() }
    await waitUntil { repository.isStarted }
    task.cancel()
    await task.value
    #expect(repository.stopCallCount == 1)
  }

  @Test func logOutCallsTheInjectedAction() async {
    var calls = 0
    let viewModel = ChatListViewModel(repository: FakeRoomListRepository()) {
      calls += 1
      return true
    }
    await viewModel.logOut()
    #expect(calls == 1)
    #expect(viewModel.logOutErrorMessage == nil)
    #expect(!viewModel.isLoggingOut)
  }

  @Test func aFailedLogOutShowsAnErrorAndCanBeRetried() async {
    var results = [false, true]
    let viewModel = ChatListViewModel(repository: FakeRoomListRepository()) {
      results.removeFirst()
    }
    await viewModel.logOut()
    #expect(viewModel.logOutErrorMessage == "Could not log out. Please try again.")
    await viewModel.logOut()
    #expect(viewModel.logOutErrorMessage == nil)
  }

  // MARK: Tester (TWAK-66): the stream ending, and the screen coming back.

  /// The repository's stream ends (the SDK list ended): the last list stays shown and the room list is stopped.
  @Test func whenTheStreamEndsTheLastListStaysAndTheListIsStopped() async {
    let repository = FakeRoomListRepository()
    let viewModel = ChatListViewModel(repository: repository, logOut: { true })
    let task = Task { await viewModel.start() }
    await waitUntil { repository.isStarted }
    repository.send([team, family])
    await waitUntil { viewModel.state == .loaded([team, family]) }
    repository.finish()
    await task.value
    #expect(viewModel.state == .loaded([team, family]))
    #expect(repository.stopCallCount == 1)
  }

  /// The screen goes away and comes back: `start()` shows loading again, restarts the room list and shows the new list.
  @Test func startingAgainRestartsTheRoomList() async {
    let repository = FakeRoomListRepository()
    let viewModel = ChatListViewModel(repository: repository, logOut: { true })
    let first = Task { await viewModel.start() }
    await waitUntil { repository.isStarted }
    repository.send([team])
    await waitUntil { viewModel.state == .loaded([team]) }
    first.cancel()
    await first.value

    let second = Task { await viewModel.start() }
    await waitUntil { repository.startCallCount == 2 && repository.isStarted }
    #expect(viewModel.state == .loading)
    repository.send([family, team])
    await waitUntil { viewModel.state == .loaded([family, team]) }
    #expect(viewModel.state == .loaded([family, team]))
    second.cancel()
    await second.value
    #expect(repository.stopCallCount == 2)
  }

  /// Two overlapping `start()` calls (two windows, or a restarted `.task`): the later start ends the earlier stream, and
  /// the earlier call must not then stop the room list the later one follows.
  @Test func anEarlierStartDoesNotStopALaterOne() async {
    let repository = FakeRoomListRepository()
    let viewModel = ChatListViewModel(repository: repository, logOut: { true })
    let first = Task { await viewModel.start() }
    await waitUntil { repository.isStarted }
    repository.send([team])
    await waitUntil { viewModel.state == .loaded([team]) }

    let second = Task { await viewModel.start() }
    await waitUntil { repository.startCallCount == 2 && repository.isStarted }
    await first.value
    #expect(repository.stopCallCount == 0)
    #expect(repository.isStarted)

    repository.send([family, team])
    await waitUntil { viewModel.state == .loaded([family, team]) }
    #expect(viewModel.state == .loaded([family, team]))
    second.cancel()
    await second.value
    #expect(repository.stopCallCount == 1)
  }

  /// A start error after a list was shown replaces it with the error, not a stale list.
  @Test func aStartErrorAfterAListReplacesIt() async {
    let repository = FakeRoomListRepository()
    let viewModel = ChatListViewModel(repository: repository, logOut: { true })
    let first = Task { await viewModel.start() }
    await waitUntil { repository.isStarted }
    repository.send([team])
    await waitUntil { viewModel.state == .loaded([team]) }
    first.cancel()
    await first.value

    repository.startError = .syncUnavailable
    await viewModel.start()
    #expect(viewModel.state == .failed("Could not load your rooms."))
  }

  @Test func previewJoinsSenderAndText() {
    #expect(ChatListViewModel.preview(of: team) == "Alice: Hello")
    #expect(ChatListViewModel.preview(of: Self.room("!a:b", "A", text: "Hi", sender: nil)) == "Hi")
    #expect(ChatListViewModel.preview(of: Self.room("!a:b", "A", text: nil)) == nil)
  }
}

@MainActor
struct ChatListSearchTests {
  @Test func searchFiltersRoomsByName() async {
    let repository = FakeRoomListRepository()
    let viewModel = ChatListViewModel(repository: repository) { true }
    let task = Task { await viewModel.start() }
    let rooms = [
      RoomSummary(
        id: "!a", name: "Design team", lastMessageText: nil, lastMessageSender: nil,
        lastActivity: nil),
      RoomSummary(
        id: "!b", name: "Alice", lastMessageText: nil, lastMessageSender: nil, lastActivity: nil),
    ]
    while repository.startCallCount == 0 { await Task.yield() }
    repository.send(rooms)
    while viewModel.state != .loaded(rooms) { await Task.yield() }
    #expect(viewModel.visibleRooms.map(\.id) == ["!a", "!b"])
    viewModel.query = "design"
    #expect(viewModel.visibleRooms.map(\.id) == ["!a"])
    viewModel.query = "  "
    #expect(viewModel.visibleRooms.count == 2)
    task.cancel()
    repository.finish()
  }
}
