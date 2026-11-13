import Domain
import Foundation
import RoomTestSupport
import Testing

@testable import Room

@MainActor
struct RoomDetailsViewModelTests {
  private let details = RoomDetails(
    id: "!r:example.org", name: "Team", topic: "Daily sync", alias: "#team:example.org",
    isDirect: false,
    isEncrypted: true, isPublic: false, joinedMemberCount: 2)

  @Test func loadsTheDetailsAndMembers() async {
    let repository = FakeRoomDetailsRepository()
    repository.detailsResult = .success(details)
    repository.members = [
      .init(id: "@alice:example.org", displayName: "Alice", membership: .joined),
      .init(id: "@bob:example.org", displayName: nil, membership: .invited),
    ]
    let viewModel = RoomDetailsViewModel(
      roomId: "!r:example.org", repository: repository, onLeft: {})
    await viewModel.load()
    #expect(viewModel.state == .loaded(details))
    #expect(viewModel.members.map(\.name) == ["Alice", "@bob:example.org"])
  }

  @Test func aRoomThatCannotLoadShowsAnError() async {
    let viewModel = RoomDetailsViewModel(
      roomId: "!r", repository: FakeRoomDetailsRepository(), onLeft: {})
    await viewModel.load()
    #expect(viewModel.state == .failed("Could not load the chat details."))
  }

  @Test func searchFiltersMembersByNameOrId() async {
    let repository = FakeRoomDetailsRepository()
    repository.detailsResult = .success(details)
    repository.members = [
      .init(id: "@alice:example.org", displayName: "Alice", membership: .joined),
      .init(id: "@bob:example.org", displayName: "Bob", membership: .joined),
    ]
    let viewModel = RoomDetailsViewModel(roomId: "!r", repository: repository, onLeft: {})
    await viewModel.load()
    viewModel.memberQuery = "ali"
    #expect(viewModel.filteredMembers.map(\.id) == ["@alice:example.org"])
    viewModel.memberQuery = "@bob"
    #expect(viewModel.filteredMembers.map(\.id) == ["@bob:example.org"])
  }

  @Test func leavingClosesTheChat() async {
    let repository = FakeRoomDetailsRepository()
    var closed = false
    let viewModel = RoomDetailsViewModel(
      roomId: "!r", repository: repository, onLeft: { closed = true })
    await viewModel.leave()
    #expect(repository.leftRooms == ["!r"])
    #expect(closed)
  }

  @Test func aFailedLeaveKeepsTheChatWithAMessage() async {
    let repository = FakeRoomDetailsRepository()
    repository.leaveResult = .failure(.requestFailed)
    var closed = false
    let viewModel = RoomDetailsViewModel(
      roomId: "!r", repository: repository, onLeft: { closed = true })
    await viewModel.leave()
    #expect(!closed)
    #expect(viewModel.errorMessage == "Could not leave the chat. Please try again.")
  }

  @Test func aRoomWithoutDetailsRepositoryHasNoDetailsPage() {
    let room = RoomViewModel(
      roomId: "!r", roomName: "Team", repository: FakeTimelineRepository(),
      media: FakeMediaRepository())
    #expect(room.makeDetails() == nil)
  }
}
