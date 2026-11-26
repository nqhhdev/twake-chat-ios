import Domain
import Foundation
import RoomTestSupport
import Testing

@testable import Room

@MainActor
struct ChannelSettingsViewModelTests {
  private func details(isDirect: Bool = false) -> RoomDetails {
    RoomDetails(
      id: "!r:example.org", name: "News", topic: nil, alias: "#news:example.org",
      isDirect: isDirect, isEncrypted: false, isPublic: true, joinedMemberCount: 3)
  }

  private func loaded(_ channel: ChannelSettings?, isDirect: Bool = false) async -> (
    RoomDetailsViewModel, FakeRoomDetailsRepository
  ) {
    let repository = FakeRoomDetailsRepository()
    repository.detailsResult = .success(details(isDirect: isDirect))
    repository.channel = channel
    let viewModel = RoomDetailsViewModel(
      roomId: "!r:example.org", repository: repository, onLeft: {})
    await viewModel.load()
    return (viewModel, repository)
  }

  @Test func theOwnerTurnsGifsOffAndBackOn() async {
    let (viewModel, repository) = await loaded(ChannelSettings(isOwner: true, gifsEnabled: true))
    await viewModel.setGifs(false)
    #expect(viewModel.channel?.gifsEnabled == false)
    await viewModel.setGifs(true)
    #expect(viewModel.channel?.gifsEnabled == true)
    #expect(repository.channelChanges == ["gifs false", "gifs true"])
    #expect(viewModel.errorMessage == nil)
  }

  @Test func aMemberWhoIsNotTheOwnerChangesNothing() async {
    let (viewModel, repository) = await loaded(ChannelSettings(isOwner: false, gifsEnabled: true))
    await viewModel.setGifs(false)
    #expect(repository.channelChanges.isEmpty)
    #expect(viewModel.channel?.gifsEnabled == true)
  }

  @Test func aRefusedChangeGoesBack() async {
    let (viewModel, repository) = await loaded(ChannelSettings(isOwner: true, gifsEnabled: true))
    repository.channelFails = true
    await viewModel.setGifs(false)
    #expect(viewModel.channel?.gifsEnabled == true)
    #expect(viewModel.errorMessage == "Could not change the GIFs of this chat. Please try again.")
  }

  @Test func aDirectChatHasNoChannelSettings() async {
    let (viewModel, _) = await loaded(
      ChannelSettings(isOwner: true, gifsEnabled: true), isDirect: true)
    #expect(viewModel.channel == nil)
  }
}
