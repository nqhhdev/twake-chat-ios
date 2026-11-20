import DesignSystem
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

  @Test func aRoomChangeReloadsTheMembersWhileTheScreenIsOpen() async {
    let repository = FakeRoomDetailsRepository()
    repository.detailsResult = .success(details)
    repository.members = [
      .init(id: "@alice:example.org", displayName: "Alice", membership: .joined),
      .init(id: "@bob:example.org", displayName: "Bob", membership: .joined),
    ]
    let viewModel = RoomDetailsViewModel(
      roomId: "!r:example.org", repository: repository, onLeft: {})
    await viewModel.load()
    let following = Task { await viewModel.followChanges(settle: .zero) }
    // Bob was removed from another device: the SDK reports the room changed.
    repository.members = [
      .init(id: "@alice:example.org", displayName: "Alice", membership: .joined)
    ]
    repository.roomChanges.continuation.yield()
    repository.roomChanges.continuation.finish()
    await following.value
    #expect(viewModel.members.map(\.name) == ["Alice"])
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

  @Test func savingSendsOnlyWhatChangedThenReloads() async {
    let repository = FakeRoomDetailsRepository()
    repository.detailsResult = .success(details)
    let viewModel = RoomDetailsViewModel(
      roomId: "!r:example.org", repository: repository, onLeft: {})
    await viewModel.load()
    let saved = await viewModel.save(name: "  Team  ", topic: "Weekly sync")
    #expect(saved)
    #expect(repository.changes == ["topic Weekly sync"])
  }

  @Test func anEmptyNameIsRefused() async {
    let repository = FakeRoomDetailsRepository()
    repository.detailsResult = .success(details)
    let viewModel = RoomDetailsViewModel(
      roomId: "!r:example.org", repository: repository, onLeft: {})
    await viewModel.load()
    #expect(await viewModel.save(name: " ", topic: "") == false)
    #expect(repository.changes.isEmpty)
    #expect(viewModel.errorMessage != nil)
  }

  @Test func aFailedSaveShowsAnError() async {
    let repository = FakeRoomDetailsRepository()
    repository.detailsResult = .success(details)
    repository.changeResult = .failure(.requestFailed)
    let viewModel = RoomDetailsViewModel(
      roomId: "!r:example.org", repository: repository, onLeft: {})
    await viewModel.load()
    #expect(await viewModel.save(name: "Renamed", topic: "Daily sync") == false)
    #expect(viewModel.errorMessage == "Could not save the changes. Please try again.")
  }
}

@MainActor
struct RoomNotificationModeTests {
  @Test func mutingTheRoomAndGoingBackToTheDefault() async {
    let repository = FakeRoomDetailsRepository()
    let viewModel = RoomDetailsViewModel(roomId: "!r", repository: repository, onLeft: {})
    await viewModel.load()
    #expect(viewModel.followsDefault)
    await viewModel.setNotificationMode(.mute)
    #expect(viewModel.notificationMode == .mute)
    #expect(!viewModel.followsDefault)
    await viewModel.setNotificationMode(nil)
    #expect(viewModel.followsDefault)
    #expect(viewModel.notificationMode == .allMessages)
  }

  @Test func aFailedChangeGoesBack() async {
    let repository = FakeRoomDetailsRepository()
    repository.setModeResult = .failure(.requestFailed)
    let viewModel = RoomDetailsViewModel(roomId: "!r", repository: repository, onLeft: {})
    await viewModel.load()
    await viewModel.setNotificationMode(.mute)
    #expect(viewModel.followsDefault)
    #expect(viewModel.errorMessage != nil)
  }

  @Test func removingAMemberAsksTheServerAndRefreshesTheMembers() async {
    let repository = FakeRoomDetailsRepository()
    repository.detailsResult = .success(
      RoomDetails(
        id: "!r", name: "Team", topic: nil, alias: nil, isDirect: false, isEncrypted: true,
        isPublic: false, joinedMemberCount: 2))
    let bob = RoomMember(
      id: "@bob:example.org", displayName: "Bob", membership: .joined, canBeRemoved: true)
    repository.members = [
      .init(id: "@me:example.org", displayName: "Me", membership: .joined, isOwn: true), bob,
    ]
    let viewModel = RoomDetailsViewModel(roomId: "!r", repository: repository, onLeft: {})
    await viewModel.load()
    #expect(await viewModel.remove(bob))
    #expect(repository.changes == ["remove @bob:example.org"])
    #expect(viewModel.members.map(\.id) == ["@me:example.org"])
  }

  @Test func aMemberThatCannotBeRemovedIsLeftAlone() async {
    let repository = FakeRoomDetailsRepository()
    let viewModel = RoomDetailsViewModel(roomId: "!r", repository: repository, onLeft: {})
    let admin = RoomMember(
      id: "@admin:example.org", displayName: "Admin", membership: .joined, role: .administrator)
    #expect(await viewModel.remove(admin) == false)
    #expect(repository.changes.isEmpty)
  }

  @Test func aFailedRemoveShowsAnError() async {
    let repository = FakeRoomDetailsRepository()
    repository.changeResult = .failure(.requestFailed)
    let viewModel = RoomDetailsViewModel(roomId: "!r", repository: repository, onLeft: {})
    let bob = RoomMember(
      id: "@bob:example.org", displayName: "Bob", membership: .joined, canBeRemoved: true)
    #expect(await viewModel.remove(bob) == false)
    #expect(viewModel.errorMessage == "Could not remove Bob. Please try again.")
  }

  @Test func messageOpensTheDirectChatThroughTheApp() async {
    var opened: [String] = []
    let viewModel = RoomDetailsViewModel(
      roomId: "!r", repository: FakeRoomDetailsRepository(), onLeft: {},
      openDirectChat: { userId in
        opened.append(userId)
        return userId != "@carol:example.org"
      })
    await viewModel.message(.init(id: "@bob:example.org", displayName: "Bob", membership: .joined))
    await viewModel.message(
      .init(id: "@me:example.org", displayName: "Me", membership: .joined, isOwn: true))
    #expect(opened == ["@bob:example.org"])
    #expect(viewModel.errorMessage == nil)
    await viewModel.message(
      .init(id: "@carol:example.org", displayName: "Carol", membership: .joined))
    #expect(viewModel.errorMessage == "Could not open the chat with Carol. Please try again.")
  }

  @Test func blockingAMemberUsesTheRoomsBlockAndNeverTheUser() async {
    var blocked: [String] = []
    let viewModel = RoomDetailsViewModel(
      roomId: "!r", repository: FakeRoomDetailsRepository(), onLeft: {},
      block: { userId in
        blocked.append(userId)
        return true
      })
    let me = RoomMember(id: "@me:example.org", displayName: "Me", membership: .joined, isOwn: true)
    let bob = RoomMember(id: "@bob:example.org", displayName: "Bob", membership: .joined)
    #expect(viewModel.canBlock(me) == false)
    #expect(viewModel.canBlock(bob))
    #expect(await viewModel.block(me) == false)
    #expect(await viewModel.block(bob))
    #expect(blocked == ["@bob:example.org"])
  }

  @Test func changingTheChatPictureUploadsItThenRemovesIt() async {
    let repository = FakeRoomDetailsRepository()
    let viewModel = RoomDetailsViewModel(roomId: "!r", repository: repository, onLeft: {})
    await viewModel.setPicture(PreparedPicture(jpeg: Data([1]), side: 300))
    await viewModel.removePicture()
    #expect(repository.changes == ["avatar 300x300", "remove avatar"])
    #expect(viewModel.errorMessage == nil)
  }

  @Test func aFailedChatPictureChangeSaysSo() async {
    let repository = FakeRoomDetailsRepository()
    repository.changeResult = .failure(.requestFailed)
    let viewModel = RoomDetailsViewModel(roomId: "!r", repository: repository, onLeft: {})
    await viewModel.setPicture(PreparedPicture(jpeg: Data([1]), side: 300))
    #expect(viewModel.errorMessage == "Could not change the chat picture. Please try again.")
  }

  private func group(
    encrypted: Bool, rule: RoomDetails.JoinRule = .invite, canChange: Bool = true
  ) -> RoomDetails {
    RoomDetails(
      id: "!r", name: "Team", topic: nil, alias: nil, isDirect: false, isEncrypted: encrypted,
      isPublic: false, joinedMemberCount: 2, joinRule: rule, canChangeAccess: canChange,
      canEnableEncryption: !encrypted && canChange, canBan: canChange)
  }

  @Test func changingWhoCanJoinAsksTheServer() async {
    let repository = FakeRoomDetailsRepository()
    repository.detailsResult = .success(group(encrypted: false))
    let viewModel = RoomDetailsViewModel(roomId: "!r", repository: repository, onLeft: {})
    await viewModel.load()
    await viewModel.setJoinRule(.knock)
    await viewModel.setJoinRule(.public)
    #expect(repository.changes == ["join rule knock", "join rule public"])
  }

  @Test func anEncryptedChatIsNotOpenedToAnyone() async {
    let repository = FakeRoomDetailsRepository()
    repository.detailsResult = .success(group(encrypted: true))
    let viewModel = RoomDetailsViewModel(roomId: "!r", repository: repository, onLeft: {})
    await viewModel.load()
    await viewModel.setJoinRule(.public)
    await viewModel.enableEncryption()
    #expect(repository.changes.isEmpty)
  }

  @Test func encryptionTurnsOnWhenTheUserMay() async {
    let repository = FakeRoomDetailsRepository()
    repository.detailsResult = .success(group(encrypted: false))
    let viewModel = RoomDetailsViewModel(roomId: "!r", repository: repository, onLeft: {})
    await viewModel.load()
    await viewModel.enableEncryption()
    #expect(repository.changes == ["encryption"])
  }

  @Test func banningMovesAMemberToBannedAndUnbanningLetsThemBack() async {
    let repository = FakeRoomDetailsRepository()
    repository.detailsResult = .success(group(encrypted: true))
    let bob = RoomMember(
      id: "@bob:example.org", displayName: "Bob", membership: .joined, canBeBanned: true)
    repository.members = [bob]
    let viewModel = RoomDetailsViewModel(roomId: "!r", repository: repository, onLeft: {})
    await viewModel.load()
    #expect(await viewModel.ban(bob))
    #expect(viewModel.members.isEmpty)
    await viewModel.loadBanned()
    #expect(viewModel.banned?.map(\.id) == ["@bob:example.org"])
    let banned = viewModel.banned![0]
    #expect(await viewModel.unban(banned))
    #expect(viewModel.banned?.isEmpty == true)
    #expect(repository.changes == ["ban @bob:example.org", "unban @bob:example.org"])
  }

  @Test func onlyTheRolesTheUserMayGiveAreSet() async {
    let repository = FakeRoomDetailsRepository()
    repository.detailsResult = .success(group(encrypted: true))
    let viewModel = RoomDetailsViewModel(roomId: "!r", repository: repository, onLeft: {})
    let bob = RoomMember(
      id: "@bob:example.org", displayName: "Bob", membership: .joined,
      assignableRoles: [.user, .moderator])
    #expect(await viewModel.setRole(.moderator, for: bob))
    #expect(await viewModel.setRole(.administrator, for: bob) == false)
    #expect(await viewModel.setRole(.user, for: bob) == false)
    #expect(repository.changes == ["role @bob:example.org moderator"])
  }
}
