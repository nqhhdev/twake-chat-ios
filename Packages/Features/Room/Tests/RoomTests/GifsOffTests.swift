import Domain
import Foundation
import RoomTestSupport
import Testing

@testable import Room

@MainActor
struct GifsOffTests {
  private func gif(
    mimeType: String? = "image/gif", body: TimelineMessage.Body = .image(caption: nil)
  )
    -> TimelineMessage
  {
    TimelineMessage(
      eventId: "$g", senderId: "@bob:example.org", senderName: "Bob", isOwn: false, date: .now,
      body: body, media: MediaReference(source: "s", mimeType: mimeType))
  }

  private func room(gifsOn: Bool, details: FakeRoomDetailsRepository? = nil) -> (
    RoomViewModel, FakeTimelineRepository
  ) {
    let timeline = FakeTimelineRepository()
    timeline.gifsOn = gifsOn
    let room = RoomViewModel(
      roomId: "!r:example.org", roomName: "News", repository: timeline,
      media: FakeMediaRepository(), details: details, gifs: FakeGifRepository())
    return (room, timeline)
  }

  @Test func aChannelWithGifsOffHidesThePickerAndItsGifs() async {
    let (off, _) = room(gifsOn: false)
    await off.loadGifsAvailability()
    #expect(off.gifsOff)
    #expect(!off.gifsAvailable)
    let (on, _) = room(gifsOn: true)
    await on.loadGifsAvailability()
    #expect(!on.gifsOff)
    #expect(on.gifsAvailable)
  }

  @Test func onlyAGifPictureIsHiddenAndOnlyWhenGifsAreOff() {
    #expect(RoomViewModel.isHiddenGif(gif(), gifsOff: true))
    #expect(RoomViewModel.isHiddenGif(gif(mimeType: "IMAGE/GIF"), gifsOff: true))
    #expect(!RoomViewModel.isHiddenGif(gif(), gifsOff: false))
    #expect(!RoomViewModel.isHiddenGif(gif(mimeType: "image/png"), gifsOff: true))
    #expect(!RoomViewModel.isHiddenGif(gif(mimeType: nil), gifsOff: true))
    #expect(!RoomViewModel.isHiddenGif(gif(body: .file(name: "a.gif")), gifsOff: true))
  }

  @Test func theOwnersSwitchInTheDetailsAppliesToTheOpenChat() async {
    let details = FakeRoomDetailsRepository()
    details.detailsResult = .success(
      RoomDetails(
        id: "!r:example.org", name: "News", topic: nil, alias: nil, isDirect: false,
        isEncrypted: false, isPublic: true, joinedMemberCount: 3))
    details.channel = ChannelSettings(isOwner: true, gifsEnabled: true)
    let (room, _) = room(gifsOn: true, details: details)
    await room.loadGifsAvailability()
    #expect(room.gifsAvailable)
    let info = room.makeDetails()
    await info?.load()
    await info?.setGifs(false)
    while room.gifsAvailable { await Task.yield() }
    #expect(room.gifsOff)
    await info?.setGifs(true)
    while !room.gifsAvailable { await Task.yield() }
    #expect(!room.gifsOff)
  }
}
