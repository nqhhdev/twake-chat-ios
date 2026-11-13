import ChatListTestSupport
import Domain
import Foundation
import Testing

@testable import ChatList

/// The archive: left chats load, rejoin or delete one at a time, and Delete All keeps the ones that fail.
@MainActor
struct ArchivedChatsViewModelTests {
  private actor Archive: ArchivedRoomsRepository {
    var rooms: [RoomSummary]
    var failing: Set<String> = []
    private(set) var rejoined: [String] = []
    private(set) var forgotten: [String] = []

    init(_ rooms: [RoomSummary]) { self.rooms = rooms }

    func fail(_ id: String) { failing.insert(id) }

    func archivedRooms() async throws(RoomListError) -> [RoomSummary] { rooms }

    func rejoin(roomId: String) async throws(RoomListError) {
      if failing.contains(roomId) { throw .requestFailed }
      rejoined.append(roomId)
    }

    func forget(roomId: String) async throws(RoomListError) {
      if failing.contains(roomId) { throw .requestFailed }
      forgotten.append(roomId)
    }
  }

  private func room(_ id: String) -> RoomSummary {
    RoomSummary(
      id: id, name: "Room \(id)", lastMessageText: nil, lastMessageSender: nil, lastActivity: nil,
      isArchived: true)
  }

  @Test func rejoiningTakesTheChatOutOfTheArchive() async {
    let archive = Archive([room("!a"), room("!b")])
    let viewModel = ArchivedChatsViewModel(repository: archive)
    await viewModel.load()
    #expect(viewModel.rooms?.map(\.id) == ["!a", "!b"])
    #expect(await viewModel.rejoin(room("!a")))
    #expect(await archive.rejoined == ["!a"])
    #expect(viewModel.rooms?.map(\.id) == ["!b"])
  }

  @Test func aChatThatCannotBeRejoinedStaysAndSaysWhy() async {
    let archive = Archive([room("!a")])
    await archive.fail("!a")
    let viewModel = ArchivedChatsViewModel(repository: archive)
    await viewModel.load()
    #expect(await viewModel.rejoin(room("!a")) == false)
    #expect(viewModel.rooms?.map(\.id) == ["!a"])
    #expect(viewModel.errorMessage == "Could not join Room !a again. It may need an invitation.")
  }

  @Test func deleteAllKeepsTheChatsThatFail() async {
    let archive = Archive([room("!a"), room("!b"), room("!c")])
    await archive.fail("!b")
    let viewModel = ArchivedChatsViewModel(repository: archive)
    await viewModel.load()
    await viewModel.deleteAll()
    #expect(await archive.forgotten == ["!a", "!c"])
    #expect(viewModel.rooms?.map(\.id) == ["!b"])
  }

  @Test func theChatListOffersTheArchiveOnlyWhenTheAppGivesOne() {
    let without = ChatListViewModel(repository: FakeRoomListRepository()) { true }
    #expect(without.hasArchive == false)
    let with = ChatListViewModel(repository: FakeRoomListRepository(), archive: Archive([])) {
      true
    }
    #expect(with.hasArchive)
    #expect(with.makeArchive() != nil)
  }
}
