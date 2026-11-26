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

  private func loaded(_ name: String, mimeType: String) throws -> AttachmentLoader.Loaded {
    let folder = FileManager.default.temporaryDirectory.appending(path: "gifs-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appending(path: name)
    try Data([1]).write(to: url)
    return AttachmentLoader.Loaded(
      kind: .image(width: 1, height: 1), fileURL: url, mimeType: mimeType, size: 1)
  }

  private func picture(_ id: String, mimeType: String, batch: String? = "b") -> TimelineItem {
    TimelineItem(
      id: id,
      kind: .message(
        TimelineMessage(
          eventId: "$\(id)", senderId: "@bob:example.org", senderName: "Bob", isOwn: false,
          date: Date(timeIntervalSince1970: 1_700_000_000), body: .image(caption: nil),
          media: MediaReference(source: id, mimeType: mimeType), batchId: batch)))
  }

  private let target = RoomSummary(
    id: "!news", name: "News", lastMessageText: nil, lastMessageSender: nil, lastActivity: nil)

  @Test func aPickedGifIsRefusedInAChannelWithGifsOff() async throws {
    let (room, _) = room(gifsOn: false)
    await room.loadGifsAvailability()
    let gif = try loaded("a.gif", mimeType: "image/gif")
    let png = try loaded("b.png", mimeType: "image/png")
    let kept = room.sendable([gif, png])
    #expect(kept.map(\.id) == [png.id])
    #expect(room.errorMessage == "GIFs are off in this chat, so GIF files cannot be sent here.")
    #expect(!FileManager.default.fileExists(atPath: gif.fileURL.path()))
  }

  @Test func aPickedGifIsKeptWhenGifsAreOn() async throws {
    let (room, _) = room(gifsOn: true)
    await room.loadGifsAvailability()
    let gif = try loaded("a.gif", mimeType: "image/gif")
    #expect(room.sendable([gif]).map(\.id) == [gif.id])
    #expect(room.errorMessage == nil)
  }

  @Test func aSharedGifIsNotUploadedInAChannelWithGifsOff() async throws {
    let (room, timeline) = room(gifsOn: false)
    await room.loadGifsAvailability()
    let gif = try loaded("a.gif", mimeType: "image/gif")
    await room.send(
      attachment: gif.kind, fileURL: gif.fileURL, mimeType: gif.mimeType, size: gif.size)
    #expect(timeline.calls.isEmpty)
    #expect(room.errorMessage == "GIFs are off in this chat, so GIF files cannot be sent here.")
  }

  @Test func gifsSentTogetherStaySingleHiddenMessagesWhenGifsAreOff() {
    let items = [picture("1", mimeType: "image/gif"), picture("2", mimeType: "image/gif")]
    let off = TimelineRows.rows(from: items, gifsOff: true)
    #expect(off.allSatisfy { if case .message = $0 { true } else { false } })
    let on = TimelineRows.rows(from: items, gifsOff: false)
    #expect(on.count == 1)
    #expect(on.allSatisfy { if case .album = $0 { true } else { false } })
  }

  @Test func theMediaTabLeavesGifsOutWhenGifsAreOff() {
    let items = [picture("1", mimeType: "image/gif"), picture("2", mimeType: "image/png")]
    #expect(RoomContentViewModel.entries(in: items, kind: .media, gifsOff: true).map(\.id) == ["2"])
    #expect(
      RoomContentViewModel.entries(in: items, kind: .media, gifsOff: false).map(\.id) == [
        "2", "1",
      ])
  }

  @Test func aGifIsNotForwardedIntoAChannelWithGifsOff() async {
    let (room, timeline) = room(gifsOn: true)
    timeline.gifsOffRooms = ["!news"]
    await room.forward(gif(), to: target)
    #expect(timeline.calls.isEmpty)
    #expect(room.errorMessage == "GIFs are off in News, so GIFs are not forwarded there.")
  }

  @Test func onlyTheGifsOfASelectionAreLeftOutOfAChannelWithGifsOff() async {
    let (room, timeline) = room(gifsOn: true)
    timeline.gifsOffRooms = ["!news"]
    let text = TimelineMessage(
      eventId: "$t", senderId: "@bob:example.org", senderName: "Bob", isOwn: false, date: .now,
      body: .text("hi"))
    await room.forward([gif(), text], to: target)
    #expect(timeline.calls == [.forward("$t", "!news")])
    #expect(room.errorMessage == "GIFs are off in News, so GIFs are not forwarded there.")
  }

  @Test func aGifIsForwardedIntoAChannelWithGifsOn() async {
    let (room, timeline) = room(gifsOn: false)
    await room.forward(gif(), to: target)
    #expect(timeline.calls == [.forward("$g", "!news")])
  }
}
