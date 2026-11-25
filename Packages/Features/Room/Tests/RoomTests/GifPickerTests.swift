import Domain
import Foundation
import RoomTestSupport
import Testing

@testable import Room

@MainActor
struct GifPickerTests {
  private func gif(_ id: String, width: Int = 220, height: Int = 160) -> Gif {
    Gif(
      id: id, title: "Cat \(id)", previewURL: URL(string: "https://proxy.example/p/\(id).webp")!,
      url: URL(string: "https://proxy.example/f/\(id).gif")!, width: width, height: height)
  }

  private func viewModel(
    _ repository: FakeTimelineRepository = FakeTimelineRepository(),
    gifs: FakeGifRepository?
  ) -> RoomViewModel {
    RoomViewModel(
      roomId: "!room:example.org", roomName: "Team", repository: repository,
      media: FakeMediaRepository(), gifs: gifs)
  }

  @Test func gifsShowOnlyWithAProxyThatOffersThemInARoomThatAllowsThem() async {
    let gifs = FakeGifRepository()
    let timeline = FakeTimelineRepository()
    let room = viewModel(timeline, gifs: gifs)
    await room.loadGifsAvailability()
    #expect(room.gifsAvailable)
    #expect(room.makeGifPicker() != nil)

    timeline.gifsOn = false
    await room.loadGifsAvailability()
    #expect(!room.gifsAvailable)
    #expect(room.makeGifPicker() == nil)

    timeline.gifsOn = true
    gifs.placeholder = nil
    await room.loadGifsAvailability()
    #expect(!room.gifsAvailable)

    let plain = viewModel(gifs: nil)
    await plain.loadGifsAvailability()
    #expect(!plain.gifsAvailable)
  }

  @Test func thePickerOpensOnTrendingWithTheProxysPlaceholder() async {
    let gifs = FakeGifRepository()
    gifs.setPage(GifPage(results: [gif("1"), gif("2")], next: "c2"))
    let picker = GifPicker(repository: gifs, locale: "fr")
    await picker.start()
    #expect(picker.placeholder == "Search KLIPY")
    #expect(picker.gifs.map(\.id) == ["1", "2"])
    #expect(picker.next == "c2")
    #expect(picker.phase == .loaded)
    #expect(gifs.calls.contains(.trending(nil, "fr")))
  }

  @Test func typingSearchesAfterAPauseAndAnEmptyResultSaysSo() async {
    let gifs = FakeGifRepository()
    gifs.setPage(GifPage(results: [gif("1")], next: nil))
    gifs.setPage(GifPage(results: [], next: nil), search: "dog")
    let picker = GifPicker(repository: gifs, locale: "en")
    picker.searchDelay = .zero
    await picker.start()
    picker.query = " dog "
    while !gifs.calls.contains(.search("dog", nil, "en")) { await Task.yield() }
    while !picker.gifs.isEmpty { await Task.yield() }
    #expect(picker.isEmpty)
  }

  @Test func moreGifsAreAddedOnceEach() async {
    let gifs = FakeGifRepository()
    gifs.setPage(GifPage(results: [gif("1"), gif("2")], next: "c2"))
    gifs.setPage(GifPage(results: [gif("2"), gif("3")], next: nil), cursor: "c2")
    let picker = GifPicker(repository: gifs, locale: "en")
    await picker.start()
    await picker.loadMore()
    #expect(picker.gifs.map(\.id) == ["1", "2", "3"])
    #expect(picker.next == nil)
    await picker.loadMore()
    #expect(gifs.calls.filter { $0 == .trending("c2", "en") }.count == 1)
  }

  @Test func aProxyThatDoesNotAnswerShowsTheFailure() async {
    let picker = GifPicker(repository: FakeGifRepository(), locale: "en")
    await picker.start()
    #expect(picker.phase == .failed)
  }

  @Test func aPickedGifIsSentAsAPictureAnsweringTheReplyAndItsCopyIsRemoved() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appending(path: "Cat 1.gif")
    try Data("GIF89a".utf8).write(to: file)
    let gifs = FakeGifRepository()
    gifs.downloadResult = .success(GifFile(fileURL: file, mimeType: "image/gif", size: 6))
    let timeline = FakeTimelineRepository()
    let room = viewModel(timeline, gifs: gifs)
    room.reply(
      to: TimelineMessage(
        eventId: "$q", senderId: "@bob:example.org", senderName: "Bob", isOwn: false,
        date: .now, body: .text("Look")))
    await room.send(gif: gif("1"))
    #expect(
      timeline.calls == [
        .attachment(
          OutgoingAttachment(
            kind: .image(width: 220, height: 160), fileURL: file, mimeType: "image/gif", size: 6,
            replyTo: "$q"))
      ])
    #expect(room.composerMode == .new)
    #expect(room.uploadCount == 0)
    #expect(!FileManager.default.fileExists(atPath: directory.path))
  }

  @Test func anExpiredGifSaysToSearchAgainAndSendsNothing() async {
    let gifs = FakeGifRepository()
    gifs.downloadResult = .failure(.expired)
    let timeline = FakeTimelineRepository()
    let room = viewModel(timeline, gifs: gifs)
    await room.send(gif: gif("1", width: 0, height: 0))
    #expect(timeline.calls.isEmpty)
    #expect(room.errorMessage == "This GIF is no longer available. Search again.")
    #expect(room.uploadCount == 0)
  }

  @Test func theSearchLanguageIsTheDevicesLanguage() {
    #expect(RoomViewModel.gifLocale(Locale(identifier: "fr_FR")) == "fr")
    #expect(RoomViewModel.gifLocale(Locale(identifier: "vi")) == "vi")
  }
}
