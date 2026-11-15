import Domain
import Foundation
import Testing

/// The protocol is implementable by a hand-written fake with no SDK type (ADR 0006, ADR 0010), `start()` throws
/// `RoomListError` as a typed error, and a summary never prints its message text (ADR 0009).
struct RoomListRepositoryTests {
  private actor FakeRoomListRepository: RoomListRepository {
    private let signedIn: Bool
    private var continuation: AsyncStream<[RoomSummary]>.Continuation?

    init(signedIn: Bool) {
      self.signedIn = signedIn
    }

    func start() async throws(RoomListError) -> AsyncStream<[RoomSummary]> {
      guard signedIn else { throw .notSignedIn }
      let (stream, continuation) = AsyncStream<[RoomSummary]>.makeStream()
      continuation.yield([RoomListRepositoryTests.room])
      self.continuation = continuation
      return stream
    }

    func accept(roomId: String) async throws(RoomListError) {}
    func decline(roomId: String) async throws(RoomListError) {}
    func setUnread(_ unread: Bool, roomId: String) async throws(RoomListError) {}
    func setFavourite(_ favourite: Bool, roomId: String) async throws(RoomListError) {}
    func leave(roomId: String) async throws(RoomListError) {}
    func setMuted(_ muted: Bool, roomId: String) async throws(RoomListError) {}

    func stop() async {
      continuation?.finish()
      continuation = nil
    }
  }

  static let room = RoomSummary(
    id: "!a:example.org", name: "Team", lastMessageText: "secret text",
    lastMessageSender: "Alice", lastActivity: Date(timeIntervalSince1970: 1_700_000_000))

  @Test func startYieldsTheRoomsUntilStopped() async throws {
    let repository: any RoomListRepository = FakeRoomListRepository(signedIn: true)
    let rooms = try await repository.start()
    await repository.stop()
    var received: [[RoomSummary]] = []
    for await list in rooms { received.append(list) }
    #expect(received == [[Self.room]])
  }

  @Test func startThrowsATypedError() async {
    let repository: any RoomListRepository = FakeRoomListRepository(signedIn: false)
    await #expect(throws: RoomListError.notSignedIn) { _ = try await repository.start() }
  }

  @Test func summariesCompareByValue() {
    let same = RoomSummary(
      id: "!a:example.org", name: "Team", lastMessageText: "secret text",
      lastMessageSender: "Alice", lastActivity: Date(timeIntervalSince1970: 1_700_000_000))
    let renamed = RoomSummary(
      id: "!a:example.org", name: "Other", lastMessageText: "secret text",
      lastMessageSender: "Alice", lastActivity: Date(timeIntervalSince1970: 1_700_000_000))
    #expect(Self.room == same)
    #expect(Self.room != renamed)
    #expect(Self.room.id == "!a:example.org")
  }

  @Test func printingASummaryLeavesOutTheMessageText() {
    #expect(!String(describing: Self.room).contains("secret text"))
    #expect(!String(reflecting: Self.room).contains("secret text"))
    #expect(String(describing: Self.room).contains("!a:example.org"))
  }
}

@Suite struct AppBadgeTests {
  @Test func mutedRoomsAndSpacesAreLeftOutOfTheBadge() {
    let rooms = [
      RoomSummary(
        id: "!a", name: "A", lastMessageText: nil, lastMessageSender: nil, lastActivity: nil,
        unreadCount: 3),
      RoomSummary(
        id: "!b", name: "B", lastMessageText: nil, lastMessageSender: nil, lastActivity: nil,
        unreadCount: 5,
        mentionCount: 1, isMuted: true),
      RoomSummary(
        id: "!c", name: "C", lastMessageText: nil, lastMessageSender: nil, lastActivity: nil,
        unreadCount: 2,
        isSpace: true),
    ]
    #expect(RoomSummary.appBadge(for: rooms) == 3)
    #expect(rooms[1].badgeCount == 0)
  }
}
