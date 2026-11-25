import Domain
import Foundation
import RoomTestSupport
import Testing

@testable import Room

@MainActor
struct StickerTests {
  private let sticker = Sticker(
    id: "user/cat", body: "Cat", url: "mxc://example.org/cat",
    media: MediaReference(source: "{}", mimeType: "image/png", width: 256, height: 128))

  private func viewModel(_ repository: FakeTimelineRepository) -> RoomViewModel {
    RoomViewModel(
      roomId: "!room:example.org", roomName: "Team", repository: repository,
      media: FakeMediaRepository())
  }

  @Test func theRoomsAndTheUsersPacksAreOffered() async {
    let repository = FakeTimelineRepository()
    let pack = StickerPack(id: "user", name: "Mine", avatar: nil, stickers: [sticker])
    repository.packs = [pack]
    let room = viewModel(repository)
    #expect(room.stickerPacks.isEmpty)
    await room.loadStickerPacks()
    #expect(room.stickerPacks == [pack])
  }

  @Test func aPickedStickerIsSent() async {
    let repository = FakeTimelineRepository()
    let room = viewModel(repository)
    await room.send(sticker: sticker)
    #expect(repository.calls == [.sticker("user/cat")])
    #expect(room.sendCount == 1)
    #expect(room.errorMessage == nil)
  }

  @Test func aStickerThatCannotBeSentSaysSo() async {
    let repository = FakeTimelineRepository()
    repository.actionResult = .failure(.network)
    let room = viewModel(repository)
    await room.send(sticker: sticker)
    #expect(room.errorMessage == "Could not send the sticker. Please try again.")
  }

  @Test func aReceivedStickerKeepsItsShapeWithin160Points() {
    #expect(
      StickerMessage.size(of: MediaReference(source: "", width: 512, height: 256))
        == CGSize(width: 160, height: 80))
    #expect(
      StickerMessage.size(of: MediaReference(source: "", width: 100, height: 200))
        == CGSize(width: 80, height: 160))
    #expect(StickerMessage.size(of: MediaReference(source: "")) == CGSize(width: 160, height: 160))
  }
}
