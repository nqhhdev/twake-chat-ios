import ChatListTestSupport
import Domain
import Foundation
import Testing

@testable import ChatList

/// A space lists its sub-spaces and rooms; a joined room opens, another is joined first.
@MainActor
struct SpaceViewModelTests {
  private actor Spaces: SpacesRepository {
    var children: [SpaceChild] = []
    var joinFails = false
    private(set) var joined: [String] = []

    func set(_ children: [SpaceChild]) { self.children = children }
    func failJoins() { joinFails = true }

    func children(of spaceId: String) async throws(SpacesError) -> [SpaceChild] { children }

    func join(_ child: SpaceChild) async throws(SpacesError) -> String {
      if joinFails { throw .requestFailed }
      joined.append(child.id)
      return child.id
    }
  }

  private let space = RoomSummary(
    id: "!space", name: "Team", lastMessageText: nil, lastMessageSender: nil, lastActivity: nil,
    isSpace: true)

  private func child(_ id: String, _ name: String, joined: Bool, space: Bool = false)
    -> SpaceChild
  {
    SpaceChild(
      id: id, name: name, topic: nil, avatar: nil, memberCount: 2, isJoined: joined,
      isSpace: space, via: ["example.org"])
  }

  @Test func subSpacesComeFirstThenJoinedRoomsThenByName() async {
    let spaces = Spaces()
    await spaces.set([
      child("!b", "Beta", joined: false), child("!a", "Alpha", joined: true),
      child("!s", "Sub", joined: true, space: true), child("!c", "Charlie", joined: true),
    ])
    let viewModel = SpaceViewModel(
      space: space, repository: spaces, picture: { _ in nil }, onOpen: { _ in })
    await viewModel.load()
    #expect(viewModel.children?.map(\.id) == ["!s", "!a", "!c", "!b"])
  }

  @Test func aJoinedRoomOpensAtOnce() async {
    var opened: [String] = []
    let spaces = Spaces()
    let viewModel = SpaceViewModel(
      space: space, repository: spaces, picture: { _ in nil }, onOpen: { opened.append($0.id) })
    await viewModel.open(child("!a", "Alpha", joined: true))
    #expect(opened == ["!a"])
    #expect(await spaces.joined.isEmpty)
  }

  @Test func anotherRoomIsJoinedThenOpened() async {
    var opened: [String] = []
    let spaces = Spaces()
    let beta = child("!b", "Beta", joined: false)
    await spaces.set([beta])
    let viewModel = SpaceViewModel(
      space: space, repository: spaces, picture: { _ in nil }, onOpen: { opened.append($0.id) })
    await viewModel.load()
    await viewModel.open(beta)
    #expect(await spaces.joined == ["!b"])
    #expect(opened == ["!b"])
    #expect(viewModel.children?.first?.isJoined == true)
  }

  @Test func aRoomThatCannotBeJoinedSaysWhy() async {
    let spaces = Spaces()
    await spaces.failJoins()
    let viewModel = SpaceViewModel(
      space: space, repository: spaces, picture: { _ in nil }, onOpen: { _ in })
    await viewModel.open(child("!b", "Beta", joined: false))
    #expect(viewModel.errorMessage == "Could not join Beta. It may need an invitation.")
  }

  @Test func theListOpensASpaceOnlyWhenTheAppGivesSpaces() {
    let without = ChatListViewModel(repository: FakeRoomListRepository()) { true }
    #expect(without.makeSpace(space, onOpen: { _ in }) == nil)
    let with = ChatListViewModel(repository: FakeRoomListRepository(), spaces: Spaces()) { true }
    #expect(with.makeSpace(space, onOpen: { _ in }) != nil)
    let room = RoomSummary(
      id: "!r", name: "Room", lastMessageText: nil, lastMessageSender: nil, lastActivity: nil)
    #expect(with.makeSpace(room, onOpen: { _ in }) == nil)
  }
}
