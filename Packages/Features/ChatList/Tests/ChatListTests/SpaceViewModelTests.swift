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
    var styles: [String: PageStyle] = [:]
    private(set) var styleRequests: [String] = []
    func setStyles(_ styles: [String: PageStyle]) { self.styles = styles }

    func pageStyle(of roomId: String) async -> PageStyle? {
      styleRequests.append(roomId)
      return styles[roomId]
    }
    private(set) var created: [String] = []

    func canAddChannel(to spaceId: String) async -> Bool { true }

    func createChannel(named name: String, in spaceId: String) async throws(SpacesError) -> String {
      created.append(name)
      return "!new"
    }
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

  private func child(
    _ id: String, _ name: String, joined: Bool, space: Bool = false, broadcast: Bool = false
  ) -> SpaceChild {
    SpaceChild(
      id: id, name: name, topic: nil, avatar: nil, memberCount: 2, isJoined: joined,
      isSpace: space, via: ["example.org"], isBroadcast: broadcast)
  }

  @Test func readsThePageStyleOfTheSpaceAndOfItsBroadcastsOnly() async {
    let spaces = Spaces()
    let cover = PageStyle(cover: MediaReference(source: "mxc://s/c"), accentColor: "#3f51b5")
    let accent = PageStyle(cover: nil, accentColor: "#ff0000")
    await spaces.set([
      child("!news", "News", joined: true, broadcast: true),
      child("!quiet", "Quiet", joined: true, broadcast: true),
      child("!chat", "Chat", joined: true),
    ])
    await spaces.setStyles(["!space": cover, "!news": accent, "!chat": accent])
    let viewModel = SpaceViewModel(
      space: space, repository: spaces, picture: { _ in nil }, onOpen: { _ in })
    await viewModel.load()
    #expect(viewModel.pageStyle == cover)
    #expect(viewModel.childStyles == ["!news": accent])
    #expect(await Set(spaces.styleRequests) == ["!space", "!news", "!quiet"])
  }

  @Test func aSpaceWithoutPageStyleKeepsThePlainHeader() async {
    let spaces = Spaces()
    await spaces.set([child("!a", "Alpha", joined: true)])
    let viewModel = SpaceViewModel(
      space: space, repository: spaces, picture: { _ in nil }, onOpen: { _ in })
    await viewModel.load()
    #expect(viewModel.pageStyle == nil)
    #expect(viewModel.childStyles.isEmpty)
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

  @Test func aSubSpaceTheUserIsNotInIsJoinedWithoutOpeningIt() async {
    var opened: [String] = []
    let spaces = Spaces()
    let sub = child("!sub", "Design", joined: false, space: true)
    await spaces.set([sub])
    let viewModel = SpaceViewModel(
      space: space, repository: spaces, picture: { _ in nil }, onOpen: { opened.append($0.id) })
    await viewModel.load()
    await viewModel.join(subspace: sub)
    #expect(await spaces.joined == ["!sub"])
    #expect(opened.isEmpty)
    #expect(viewModel.children?.first?.isJoined == true)
    #expect(viewModel.children?.first?.isSpace == true)
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

  @Test func anEditorCreatesAChannelInTheSpaceAndOpensIt() async {
    let spaces = Spaces()
    let opened = OpenedRooms()
    let viewModel = SpaceViewModel(
      space: space, repository: spaces, picture: { _ in nil }, onOpen: { opened.ids.append($0.id) })
    await viewModel.load()
    #expect(viewModel.canAddChannel)
    await viewModel.createChannel(named: "  Design ")
    #expect(await spaces.created == ["Design"])
    #expect(opened.ids == ["!new"])
  }

  @Test func markingASpaceReadMarksEachJoinedRoomOnceIncludingSubSpaces() async {
    let spaces = Spaces()
    await spaces.set([
      child("!a", "Alpha", joined: true), child("!b", "Beta", joined: false),
      child("!s", "Sub", joined: true, space: true),
    ])
    let marked = MarkedRooms()
    let viewModel = SpaceViewModel(
      space: space, repository: spaces, picture: { _ in nil }, onOpen: { _ in },
      markRead: { marked.ids.append($0) })
    await viewModel.load()
    await viewModel.markAllRead()
    #expect(marked.ids == ["!a"])
    #expect(!viewModel.isMarkingRead)
  }
}

@MainActor
private final class OpenedRooms {
  var ids: [String] = []
}

@MainActor
private final class MarkedRooms {
  var ids: [String] = []
}
