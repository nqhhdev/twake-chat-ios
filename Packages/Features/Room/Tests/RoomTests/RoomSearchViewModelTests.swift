import Domain
import Foundation
import RoomTestSupport
import Testing

@testable import Room

/// A server search that answers from a list of pages and records what it was asked.
private final class FakeRoomSearch: RoomSearchRepository, @unchecked Sendable {
  private let lock = NSLock()
  private var _pages: [String?: RoomSearchPage] = [:]
  private var _asked: [String] = []

  func answer(_ page: RoomSearchPage, from nextBatch: String? = nil) {
    lock.withLock { _pages[nextBatch] = page }
  }

  var asked: [String] { lock.withLock { _asked } }

  private var _onDevice: [RoomSearchResult] = []
  private var _askedOnDevice: [String] = []

  var onDevice: [RoomSearchResult] {
    get { lock.withLock { _onDevice } }
    set { lock.withLock { _onDevice = newValue } }
  }
  var askedOnDevice: [String] { lock.withLock { _askedOnDevice } }

  func searchOnDevice(_ term: String, roomId: String) async -> [RoomSearchResult] {
    lock.withLock {
      _askedOnDevice.append("\(term)@\(roomId)")
      return _onDevice
    }
  }

  func search(_ term: String, roomId: String, from nextBatch: String?)
    async throws(RoomSearchError) -> RoomSearchPage
  {
    let page = lock.withLock {
      _asked.append("\(term)@\(nextBatch ?? "start")")
      return _pages[nextBatch]
    }
    guard let page else { throw .requestFailed }
    return page
  }
}

@MainActor
struct RoomSearchViewModelTests {
  private func result(_ id: String) -> RoomSearchResult {
    RoomSearchResult(
      eventId: id, senderId: "@bob:example.org", senderName: "Bob", date: .now, text: "lunch")
  }

  private func item(_ id: String, _ text: String) -> TimelineItem {
    TimelineItem(
      id: id,
      kind: .message(
        TimelineMessage(
          eventId: "$\(id)", senderId: "@bob:example.org", senderName: "Bob", isOwn: false,
          date: .now, body: .text(text))))
  }

  @Test func aChatThatIsNotEncryptedAsksTheServerAndPages() async {
    let server = FakeRoomSearch()
    server.answer(RoomSearchPage(results: [result("$1")], nextBatch: "b2"))
    server.answer(RoomSearchPage(results: [result("$2")], nextBatch: nil), from: "b2")
    let viewModel = RoomSearchViewModel(
      roomId: "!r", server: server, textTimeline: FakeTimelineRepository(),
      isEncrypted: { false })
    await viewModel.start()
    #expect(viewModel.mode == .server)
    viewModel.query = "lunch"
    while viewModel.results.isEmpty { await Task.yield() }
    #expect(viewModel.results.map(\.eventId) == ["$1"])
    #expect(viewModel.hasMore)
    await viewModel.loadMore()
    #expect(viewModel.results.map(\.eventId) == ["$1", "$2"])
    #expect(viewModel.hasMore == false)
    #expect(server.asked == ["lunch@start", "lunch@b2"])
  }

  @Test func typingQuicklyAsksTheServerOnceForTheLastText() async throws {
    let server = FakeRoomSearch()
    server.answer(RoomSearchPage(results: [result("$1")], nextBatch: nil))
    let viewModel = RoomSearchViewModel(
      roomId: "!r", server: server, textTimeline: nil, isEncrypted: { false })
    await viewModel.start()
    viewModel.query = "l"
    viewModel.query = "lu"
    viewModel.query = "lunch"
    while viewModel.results.isEmpty { await Task.yield() }
    #expect(server.asked == ["lunch@start"])
  }

  @Test func theServerTermLeavesOutLinkSchemes() {
    #expect(RoomSearchViewModel.serverTerm("see https://twake.app") == "see twake.app")
    #expect(RoomSearchViewModel.serverTerm("  lunch ") == "lunch")
  }

  @Test func anEncryptedChatIsSearchedOnTheDeviceIgnoringCaseAndAccents() async {
    let timeline = FakeTimelineRepository()
    let viewModel = RoomSearchViewModel(
      roomId: "!r", server: FakeRoomSearch(), textTimeline: timeline, isEncrypted: { true })
    let task = Task { await viewModel.start() }
    while !timeline.calls.contains(.open) { await Task.yield() }
    timeline.publish([
      item("1", "Déjeuner à midi"), item("2", "see you"), item("3", "dejeuner demain"),
    ])
    while viewModel.mode != .onDevice { await Task.yield() }
    viewModel.query = "d"
    #expect(viewModel.results.isEmpty)
    viewModel.query = "DEJEUNER"
    while viewModel.results.count < 2 { await Task.yield() }
    #expect(viewModel.results.map(\.eventId) == ["$3", "$1"])
    viewModel.query = "dejeuner midi"
    #expect(viewModel.results.map(\.eventId) == ["$1"])
    timeline.finish()
    await task.value
  }

  @Test func anEncryptedChatAlsoShowsOlderMessagesFromTheDeviceIndex() async {
    let timeline = FakeTimelineRepository()
    let server = FakeRoomSearch()
    let old = RoomSearchResult(
      eventId: "$9", senderId: "@ann:example.org", senderName: "Ann",
      date: Date(timeIntervalSince1970: 1), text: "Lunch last year", roomId: "!r")
    let loadedAgain = RoomSearchResult(
      eventId: "$1", senderId: "@bob:example.org", senderName: "Bob",
      date: Date(timeIntervalSince1970: 2), text: "lunch at noon", roomId: "!r")
    let stale = RoomSearchResult(
      eventId: "$8", senderId: "@ann:example.org", senderName: "Ann",
      date: Date(timeIntervalSince1970: 3), text: "dinner", roomId: "!r")
    server.onDevice = [loadedAgain, stale, old]
    let viewModel = RoomSearchViewModel(
      roomId: "!r", server: server, textTimeline: timeline, isEncrypted: { true })
    let task = Task { await viewModel.start() }
    while !timeline.calls.contains(.open) { await Task.yield() }
    timeline.publish([item("1", "lunch at noon"), item("2", "see you")])
    while viewModel.mode != .onDevice { await Task.yield() }
    viewModel.query = "lunch"
    while viewModel.results.count < 2 { await Task.yield() }
    #expect(viewModel.results.map(\.eventId) == ["$1", "$9"])
    #expect(viewModel.results.last?.roomId == nil)
    #expect(server.askedOnDevice == ["lunch@!r"])
    #expect(server.asked.isEmpty)
    timeline.finish()
    await task.value
  }

  @Test func onTheDeviceOlderMessagesLoadUntilTheStart() async {
    let timeline = FakeTimelineRepository()
    timeline.reachesStart = true
    let viewModel = RoomSearchViewModel(
      roomId: "!r", server: nil, textTimeline: timeline, isEncrypted: { true })
    let task = Task { await viewModel.start() }
    while !timeline.calls.contains(.open) { await Task.yield() }
    while viewModel.mode != .onDevice { await Task.yield() }
    viewModel.query = "lunch"
    #expect(viewModel.hasMore)
    await viewModel.loadOlderWhileVisible()
    #expect(viewModel.reachedStart)
    #expect(viewModel.hasMore == false)
    timeline.finish()
    await task.value
  }
}
