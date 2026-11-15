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

  @Test func favouritesComeFirstAndInvitesStayApart() async {
    let repository = FakeRoomListRepository()
    let viewModel = ChatListViewModel(repository: repository, logOut: { true })
    let favourite = RoomSummary(
      id: "!fav:example.org", name: "Fav", lastMessageText: nil, lastMessageSender: nil,
      lastActivity: nil, isFavourite: true)
    let invite = RoomSummary(
      id: "!inv:example.org", name: "Inv", lastMessageText: nil, lastMessageSender: nil,
      lastActivity: nil, isInvite: true)
    let task = Task { await viewModel.start() }
    await waitUntil { repository.isStarted }
    repository.send([team, favourite, invite, family])
    await waitUntil { viewModel.state != .loading }
    #expect(viewModel.favouriteRooms.map(\.id) == [favourite.id])
    #expect(viewModel.otherRooms.map(\.id) == [team.id, family.id])
    #expect(viewModel.invites.map(\.id) == [invite.id])
    task.cancel()
    repository.finish()
  }

  @Test func lowPriorityChatsGoLastUnlessFavourite() async {
    let repository = FakeRoomListRepository()
    let viewModel = ChatListViewModel(repository: repository, logOut: { true })
    let low = RoomSummary(
      id: "!low:example.org", name: "Low", lastMessageText: nil, lastMessageSender: nil,
      lastActivity: nil, isLowPriority: true)
    let both = RoomSummary(
      id: "!both:example.org", name: "Both", lastMessageText: nil, lastMessageSender: nil,
      lastActivity: nil, isFavourite: true, isLowPriority: true)
    let task = Task { await viewModel.start() }
    await waitUntil { repository.isStarted }
    repository.send([low, team, both])
    await waitUntil { viewModel.state != .loading }
    #expect(viewModel.favouriteRooms.map(\.id) == [both.id])
    #expect(viewModel.otherRooms.map(\.id) == [team.id])
    #expect(viewModel.lowPriorityRooms.map(\.id) == [low.id])
    await viewModel.setLowPriority(false, room: low)
    viewModel.selection = [team.id, low.id]
    await viewModel.leaveSelection()
    #expect(
      repository.decisions == [
        "normal !low:example.org", "leave !low:example.org", "leave !team:example.org",
      ])
    #expect(viewModel.selection.isEmpty)
    task.cancel()
    repository.finish()
  }

  @Test func doNotDisturbShowsUntilTurnedOff() async {
    let viewModel = ChatListViewModel(
      repository: FakeRoomListRepository(),
      doNotDisturb: .init(isOn: { true }, turnOff: { true }), logOut: { true })
    await viewModel.refreshDoNotDisturb()
    #expect(viewModel.isDoNotDisturbOn)
    await viewModel.turnOffDoNotDisturb()
    #expect(!viewModel.isDoNotDisturbOn)
    #expect(viewModel.actionErrorMessage == nil)
  }

  @Test func activityListsUnreadAndMentionedRooms() async {
    let repository = FakeRoomListRepository()
    let viewModel = ChatListViewModel(repository: repository, logOut: { true })
    let mention = RoomSummary(
      id: "!m:example.org", name: "M", lastMessageText: nil, lastMessageSender: nil,
      lastActivity: nil, unreadCount: 3, mentionCount: 2)
    let unread = RoomSummary(
      id: "!u:example.org", name: "U", lastMessageText: nil, lastMessageSender: nil,
      lastActivity: nil, unreadCount: 1)
    let task = Task { await viewModel.start() }
    await waitUntil { repository.isStarted }
    repository.send([mention, unread, team])
    await waitUntil { viewModel.state != .loading }
    #expect(viewModel.mentioned.map(\.id) == [mention.id])
    #expect(viewModel.inbox.map(\.id).contains(unread.id))
    #expect(viewModel.mentionTotal == 2)
    task.cancel()
    repository.finish()
  }

  @Test func theSearchFindsPeopleAndOpensTheirChat() async {
    let opened = OpenedPeople()
    let viewModel = ChatListViewModel(
      repository: FakeRoomListRepository(), people: FoundPeople(),
      openPerson: {
        opened.ids.append($0)
        return true
      }, logOut: { true })
    viewModel.query = "ali"
    await viewModel.searchMessages()
    #expect(viewModel.peopleResults.map(\.id) == ["@alice:example.org"])
    await viewModel.open(viewModel.peopleResults[0])
    #expect(opened.ids == ["@alice:example.org"])
  }

  @Test func swipeActionsAskTheRepository() async {
    let repository = FakeRoomListRepository()
    let viewModel = ChatListViewModel(repository: repository, logOut: { true })
    await viewModel.setUnread(true, room: team)
    await viewModel.setUnread(false, room: team)
    await viewModel.setFavourite(true, room: family)
    await viewModel.leave(family)
    #expect(
      repository.decisions == [
        "unread !team:example.org", "read !team:example.org", "favourite !family:example.org",
        "leave !family:example.org",
      ])
    #expect(viewModel.actionErrorMessage == nil)
  }

  @Test func theBroadcastsFilterKeepsTheRoomsWhereOnlyModeratorsPost() async {
    let repository = FakeRoomListRepository()
    let viewModel = ChatListViewModel(repository: repository, logOut: { true })
    let news = RoomSummary(
      id: "!news:example.org", name: "News", lastMessageText: nil, lastMessageSender: nil,
      lastActivity: nil, isBroadcast: true)
    let team = RoomSummary(
      id: "!team:example.org", name: "Team", lastMessageText: nil, lastMessageSender: nil,
      lastActivity: nil)
    let task = Task { await viewModel.start() }
    await waitUntil { repository.isStarted }
    repository.send([news, team])
    await waitUntil { viewModel.state != .loading }
    viewModel.filter = .broadcasts
    #expect(viewModel.joinedRooms.map(\.id) == [news.id])
    task.cancel()
    repository.finish()
  }

  @Test func filtersPickUnreadFavouritesPeopleAndGroups() async {
    let repository = FakeRoomListRepository()
    let viewModel = ChatListViewModel(repository: repository, logOut: { true })
    let unreadDM = RoomSummary(
      id: "!dm:example.org", name: "Alice", lastMessageText: nil, lastMessageSender: nil,
      lastActivity: nil, unreadCount: 2, isDirect: true)
    let group = RoomSummary(
      id: "!g:example.org", name: "Team", lastMessageText: nil, lastMessageSender: nil,
      lastActivity: nil, isFavourite: true)
    let task = Task { await viewModel.start() }
    await waitUntil { repository.isStarted }
    repository.send([unreadDM, group])
    await waitUntil { viewModel.state != .loading }
    viewModel.filter = .unread
    #expect(viewModel.joinedRooms.map(\.id) == [unreadDM.id])
    viewModel.filter = .people
    #expect(viewModel.joinedRooms.map(\.id) == [unreadDM.id])
    viewModel.filter = .groups
    #expect(viewModel.joinedRooms.map(\.id) == [group.id])
    viewModel.filter = .favourites
    #expect(viewModel.joinedRooms.map(\.id) == [group.id])
    // The app icon badge counts every room, whatever the filter.
    #expect(viewModel.allJoinedRooms.map(\.id) == [unreadDM.id, group.id])
    viewModel.selection = [unreadDM.id, group.id]
    viewModel.filter = .all
    await viewModel.toggleSelectionMuted()
    #expect(repository.decisions == ["mute !dm:example.org", "mute !g:example.org"])
    #expect(viewModel.selection.isEmpty)
    task.cancel()
    repository.finish()
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
    // The stream exists only once `start()` has stored its continuation; `startCallCount` grows before that, so
    // waiting on it let `send` reach no stream now and then (the flaky run).
    while !repository.isStarted { await Task.yield() }
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

  @Test func acceptingAndDecliningAnInvitationAskTheRepository() async {
    let repository = FakeRoomListRepository()
    let viewModel = ChatListViewModel(repository: repository, logOut: { true })
    let invite = RoomSummary(
      id: "!new:example.org", name: "New", lastMessageText: nil, lastMessageSender: nil,
      lastActivity: nil, isInvite: true)
    await viewModel.answerInvite(invite, accept: true)
    await viewModel.answerInvite(invite, accept: false)
    #expect(repository.decisions == ["accept !new:example.org", "decline !new:example.org"])
    #expect(viewModel.answering.isEmpty)
    #expect(viewModel.inviteErrorMessage == nil)
  }
}

private struct FoundPeople: PeopleRepository {
  func search(_ text: String) async throws(PeopleError) -> [Person] {
    [Person(id: "@alice:example.org", displayName: "Alice")]
  }
  func directChat(with userId: String) async throws(PeopleError) -> String { "!dm" }
  func createGroup(name: String, inviting userIds: [String]) async throws(PeopleError) -> String {
    "!g"
  }
}

@MainActor
private final class OpenedPeople {
  var ids: [String] = []
}
