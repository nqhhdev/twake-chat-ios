import ChatListTestSupport
import Domain
import Foundation
import Testing

@testable import ChatList

@MainActor
struct NewSpaceViewModelTests {
  private actor Spaces: SpacesRepository {
    private(set) var created: [(NewSpace, PictureUpload?)] = []
    var fails = false

    func fail() { fails = true }

    func children(of spaceId: String) async throws(SpacesError) -> [SpaceChild] { [] }
    func join(_ child: SpaceChild) async throws(SpacesError) -> String { child.id }
    func canAddChannel(to spaceId: String) async -> Bool { true }

    func createSpace(_ space: NewSpace, picture: PictureUpload?) async throws(SpacesError)
      -> String
    {
      if fails { throw .requestFailed }
      created.append((space, picture))
      return "!space:example.org"
    }
  }

  @Test func aSpaceIsCreatedWithItsNameTopicVisibilityAndPictureThenOpens() async {
    let spaces = Spaces()
    var opened: [RoomSummary] = []
    let viewModel = NewSpaceViewModel(repository: spaces) { opened.append($0) }
    #expect(!viewModel.canCreate)
    viewModel.draft.name = " Design "
    viewModel.draft.topic = "Team"
    viewModel.draft.isPublic = true
    viewModel.setPicture(jpeg: Data([1, 2]), side: 64)
    #expect(viewModel.canCreate)
    await viewModel.create()
    let created = await spaces.created
    #expect(created.count == 1)
    #expect(created.first?.0 == NewSpace(name: " Design ", topic: "Team", isPublic: true))
    #expect(
      created.first?.1
        == PictureUpload(data: Data([1, 2]), mimeType: "image/jpeg", width: 64, height: 64))
    #expect(opened.map(\.id) == ["!space:example.org"])
    #expect(opened.first?.name == "Design")
    #expect(opened.first?.isSpace == true)
  }

  @Test func aFailureSaysSoAndOpensNothing() async {
    let spaces = Spaces()
    await spaces.fail()
    var opened = 0
    let viewModel = NewSpaceViewModel(parentId: "!parent:example.org", repository: spaces) { _ in
      opened += 1
    }
    viewModel.draft.name = "Sub"
    await viewModel.create()
    #expect(opened == 0)
    #expect(viewModel.errorMessage == "Could not create the sub-space.")
    #expect(viewModel.isSubspace)
  }

  @Test func anEditorOfASpaceCreatesASubSpaceInIt() async {
    let spaces = Spaces()
    let space = SpaceViewModel(
      space: RoomSummary(
        id: "!parent:example.org", name: "Parent", lastMessageText: nil, lastMessageSender: nil,
        lastActivity: nil, isSpace: true),
      repository: spaces, picture: { _ in nil }, onOpen: { _ in })
    #expect(space.makeNewSubspace {} == nil)
    await space.load()
    var closed = 0
    let subspace = space.makeNewSubspace { closed += 1 }
    #expect(subspace?.draft.parentId == "!parent:example.org")
    subspace?.draft.name = "Sub"
    await subspace?.create()
    #expect(closed == 1)
    #expect(await spaces.created.first?.0.parentId == "!parent:example.org")
  }
}
