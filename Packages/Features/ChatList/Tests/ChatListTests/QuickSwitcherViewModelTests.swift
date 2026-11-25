import ChatListTestSupport
import Domain
import Foundation
import Testing

@testable import ChatList

@MainActor
struct QuickSwitcherViewModelTests {
  private actor Directory: PublicRoomsRepository {
    private(set) var joined: [String] = []
    private var continuation: AsyncStream<[PublicRoom]>.Continuation?
    var rooms: [PublicRoom] = []

    func set(_ rooms: [PublicRoom]) { self.rooms = rooms }

    func search(_ term: String?) async throws(PublicRoomsError) -> AsyncStream<[PublicRoom]> {
      continuation?.finish()
      let (stream, continuation) = AsyncStream<[PublicRoom]>.makeStream()
      self.continuation = continuation
      continuation.yield(
        term.map { term in rooms.filter { $0.name.localizedCaseInsensitiveContains(term) } }
          ?? rooms)
      return stream
    }

    func loadMore() async throws(PublicRoomsError) -> Bool { true }

    func join(roomId: String) async throws(PublicRoomsError) -> String {
      joined.append(roomId)
      return roomId
    }

    func requestToJoin(roomId: String) async throws(PublicRoomsError) {}
  }

  private static func room(
    _ id: String, _ name: String, at seconds: TimeInterval?, unread: Int = 0,
    isInvite: Bool = false, isSpace: Bool = false
  ) -> RoomSummary {
    RoomSummary(
      id: id, name: name, lastMessageText: nil, lastMessageSender: nil,
      lastActivity: seconds.map { Date(timeIntervalSince1970: $0) }, unreadCount: unread,
      isInvite: isInvite, isSpace: isSpace)
  }

  private func waitUntil(_ condition: () -> Bool) async {
    for _ in 0..<10_000 where !condition() { await Task.yield() }
  }

  private func loadedList(
    _ rooms: [RoomSummary], publicRooms: (any PublicRoomsRepository)? = nil
  ) async -> (ChatListViewModel, Task<Void, Never>) {
    let repository = FakeRoomListRepository()
    let list = ChatListViewModel(
      repository: repository, publicRooms: publicRooms, logOut: { true })
    let task = Task { await list.start() }
    await waitUntil { repository.isStarted }
    repository.send(rooms)
    await waitUntil { list.state != .loading }
    return (list, task)
  }

  @Test func ranksUnreadChatsFirstThenTheMostRecent() {
    let rooms = [
      Self.room("!old", "Old", at: 1),
      Self.room("!new", "New", at: 9),
      Self.room("!unread", "Unread", at: 2, unread: 3),
      Self.room("!none", "No activity", at: nil),
    ]
    let ranked = QuickSwitcherViewModel.rank(rooms, query: "")
    #expect(ranked.map(\.id) == ["!unread", "!new", "!old", "!none"])
  }

  @Test func matchesTheNameWithoutCaseOrAccents() {
    let rooms = [
      Self.room("!r", "Réunion d'équipe", at: 1),
      Self.room("!s", "Sales", at: 2),
    ]
    #expect(QuickSwitcherViewModel.rank(rooms, query: " REUNION ").map(\.id) == ["!r"])
    #expect(QuickSwitcherViewModel.rank(rooms, query: "xyz").isEmpty)
  }

  @Test func leavesOutInvitationsAndSpacesAndShowsTwelveChatsAtMost() {
    let many = (0..<20).map { Self.room("!\($0)", "Chat \($0)", at: TimeInterval($0)) }
    let rooms =
      many + [
        Self.room("!invite", "Chat invite", at: 100, isInvite: true),
        Self.room("!space", "Chat space", at: 100, isSpace: true),
      ]
    let ranked = QuickSwitcherViewModel.rank(rooms, query: "chat")
    #expect(ranked.count == 12)
    #expect(ranked.first?.id == "!19")
    #expect(!ranked.contains { $0.id == "!invite" || $0.id == "!space" })
  }

  @Test func returnOpensTheFirstChatTheTextFinds() async {
    let (list, task) = await loadedList([
      Self.room("!team", "Team", at: 10), Self.room("!family", "Family", at: 5),
    ])
    var opened: [String] = []
    let switcher = QuickSwitcherViewModel(list: list) { opened.append($0.id) }
    switcher.query = "fam"
    await switcher.openCurrent()
    #expect(opened == ["!family"])
    task.cancel()
    await task.value
  }

  @Test func arrowsMoveTheHighlightAroundAndTypingResetsIt() async {
    let (list, task) = await loadedList([
      Self.room("!a", "Alpha", at: 3), Self.room("!b", "Beta", at: 2),
      Self.room("!c", "Gamma", at: 1),
    ])
    let switcher = QuickSwitcherViewModel(list: list) { _ in }
    #expect(switcher.current == .chat(Self.room("!a", "Alpha", at: 3)))
    switcher.move(by: 1)
    switcher.move(by: 1)
    #expect(switcher.current?.id == "chat:!c")
    switcher.move(by: 1)
    #expect(switcher.current?.id == "chat:!a")
    switcher.move(by: -1)
    #expect(switcher.current?.id == "chat:!c")
    switcher.query = "a"
    #expect(switcher.highlighted == 0)
    task.cancel()
    await task.value
  }

  @Test func showsNothingToOpenWhenNoChatMatches() async {
    let (list, task) = await loadedList([Self.room("!a", "Alpha", at: 3)])
    var opened: [String] = []
    let switcher = QuickSwitcherViewModel(list: list) { opened.append($0.id) }
    switcher.query = "zzz"
    #expect(switcher.options.isEmpty)
    await switcher.openCurrent()
    #expect(opened.isEmpty)
    task.cancel()
    await task.value
  }

  @Test func listsGroupsToJoinAfterTheChatsAndJoinsOne() async {
    let directory = Directory()
    await directory.set([
      PublicRoom(
        id: "!design", name: "Design", topic: nil, alias: nil, avatar: nil, memberCount: 4,
        access: .open),
      PublicRoom(
        id: "!desk", name: "Desk", topic: nil, alias: nil, avatar: nil, memberCount: 2,
        access: .open),
    ])
    let (list, task) = await loadedList(
      [Self.room("!desk", "Desk", at: 1)], publicRooms: directory)
    var opened: [String] = []
    let switcher = QuickSwitcherViewModel(list: list) { opened.append($0.id) }
    switcher.query = "d"
    #expect(switcher.groups.isEmpty)
    switcher.query = "des"
    for _ in 0..<200 where switcher.groups.isEmpty {
      try? await Task.sleep(for: .milliseconds(20))
    }
    #expect(switcher.options.map(\.id) == ["chat:!desk", "group:!design"])
    switcher.move(by: 1)
    await switcher.openCurrent()
    #expect(await directory.joined == ["!design"])
    #expect(opened == ["!design"])
    switcher.query = ""
    #expect(switcher.groups.isEmpty)
    switcher.stop()
    task.cancel()
    await task.value
  }
}
