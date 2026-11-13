import Domain
import Foundation
import Testing

@testable import ChatList

/// Public groups: browse, search from 2 letters after a pause, join an open group, ask to join one that takes requests.
@MainActor
struct PublicRoomsViewModelTests {
  private actor Directory: PublicRoomsRepository {
    private(set) var searches: [String?] = []
    private(set) var joined: [String] = []
    private(set) var requested: [String] = []
    private var continuation: AsyncStream<[PublicRoom]>.Continuation?
    var rooms: [PublicRoom] = []

    func set(_ rooms: [PublicRoom]) { self.rooms = rooms }

    func search(_ term: String?) async throws(PublicRoomsError) -> AsyncStream<[PublicRoom]> {
      searches.append(term)
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

    func requestToJoin(roomId: String) async throws(PublicRoomsError) {
      requested.append(roomId)
    }
  }

  private func room(_ id: String, _ name: String, _ access: PublicRoom.Access) -> PublicRoom {
    PublicRoom(
      id: id, name: name, topic: nil, alias: nil, avatar: nil, memberCount: 3, access: access)
  }

  @Test func browsingThenSearchingFromTwoLetters() async {
    let directory = Directory()
    await directory.set([room("!a", "Design", .open), room("!b", "Sales", .request)])
    let viewModel = PublicRoomsViewModel(repository: directory, onJoined: { _ in })
    viewModel.start()
    while viewModel.rooms == nil { await Task.yield() }
    #expect(viewModel.rooms?.map(\.id) == ["!a", "!b"])
    viewModel.query = "s"
    try? await Task.sleep(for: .milliseconds(400))
    #expect(await directory.searches == [nil])
    viewModel.query = "sa"
    viewModel.query = "sal"
    while await directory.searches.count < 2 { await Task.yield() }
    while viewModel.rooms?.map(\.id) != ["!b"] { await Task.yield() }
    #expect(await directory.searches == [nil, "sal"])
    viewModel.stop()
  }

  @Test func joiningAnOpenGroupOpensIt() async {
    var opened: [String] = []
    let directory = Directory()
    let viewModel = PublicRoomsViewModel(
      repository: directory, onJoined: { opened.append($0.id) })
    await viewModel.open(room("!a", "Design", .open))
    #expect(await directory.joined == ["!a"])
    #expect(opened == ["!a"])
  }

  @Test func askingToJoinMarksTheGroupRequestedOnce() async {
    let directory = Directory()
    let viewModel = PublicRoomsViewModel(repository: directory, onJoined: { _ in })
    let sales = room("!b", "Sales", .request)
    await viewModel.open(sales)
    await viewModel.open(sales)
    #expect(await directory.requested == ["!b"])
    #expect(viewModel.requested == ["!b"])
  }

  @Test func anInviteOnlyGroupSaysSo() async {
    let directory = Directory()
    let viewModel = PublicRoomsViewModel(repository: directory, onJoined: { _ in })
    await viewModel.open(room("!c", "Board", .inviteOnly))
    #expect(await directory.joined.isEmpty)
    #expect(viewModel.errorMessage == "Board needs an invitation.")
  }
}
