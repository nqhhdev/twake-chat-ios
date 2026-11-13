import Domain
import Foundation
import RoomTestSupport
import Testing

@testable import Room

@MainActor
struct RoomContentViewModelTests {
  private let media = MediaReference(source: "mxc://example.org/a")

  private func item(
    _ id: String, _ body: TimelineMessage.Body, media: MediaReference? = nil,
    date: Date = Date(timeIntervalSince1970: 1_790_000_000)
  ) -> TimelineItem {
    TimelineItem(
      id: id,
      kind: .message(
        TimelineMessage(
          eventId: "$\(id)", senderId: "@bob:example.org", senderName: "Bob", isOwn: false,
          date: date, body: body, media: media)))
  }

  @Test func theMediaTabKeepsPicturesAndVideosNewestFirst() {
    let items = [
      item("1", .image(caption: nil), media: media),
      item("2", .text("hello")),
      item("3", .video(caption: nil), media: media),
      item("4", .image(caption: nil)),
      item("5", .file(name: "a.pdf"), media: media),
    ]
    let entries = RoomContentViewModel.entries(in: items, kind: .media)
    #expect(entries.map(\.id) == ["3", "1"])
  }

  @Test func theFilesTabKeepsFilesOnly() {
    let items = [
      item("1", .file(name: "a.pdf"), media: media),
      item("2", .audio(caption: nil), media: media),
      item("3", .image(caption: nil), media: media),
    ]
    #expect(RoomContentViewModel.entries(in: items, kind: .files).map(\.id) == ["1"])
  }

  @Test func theLinksTabKeepsTheFirstWebLinkOfATextMessage() {
    let items = [
      item("1", .text("see https://twake.app/a and https://linagora.com")),
      item("2", .text("no link here")),
      item("3", .notice("mail me at bob@example.org")),
      item("4", .emote("likes http://example.org/b")),
    ]
    let entries = RoomContentViewModel.entries(in: items, kind: .links)
    #expect(entries.map(\.id) == ["4", "1"])
    #expect(entries.map(\.link?.absoluteString) == ["http://example.org/b", "https://twake.app/a"])
  }

  @Test func entriesAreGroupedByMonth() async {
    let repository = FakeTimelineRepository()
    let viewModel = RoomContentViewModel(
      kind: .media, repository: repository, media: FakeMediaRepository())
    let task = Task { await viewModel.start() }
    while !repository.calls.contains(.open) { await Task.yield() }
    let october = Date(timeIntervalSince1970: 1_791_000_000)
    let november = Date(timeIntervalSince1970: 1_794_000_000)
    repository.publish([
      item("1", .image(caption: nil), media: media, date: october),
      item("2", .image(caption: nil), media: media, date: november),
      item("3", .video(caption: nil), media: media, date: november),
    ])
    while viewModel.entries.count < 3 { await Task.yield() }
    #expect(viewModel.months.map { $0.entries.map(\.id) } == [["3", "2"], ["1"]])
    #expect(viewModel.pictures.map(\.id) == ["2", "1"])
    repository.finish()
    await task.value
  }

  @Test func loadingOlderPagesStopsAtTheStartOfTheRoom() async {
    let repository = FakeTimelineRepository()
    repository.reachesStart = true
    let viewModel = RoomContentViewModel(
      kind: .files, repository: repository, media: FakeMediaRepository())
    let task = Task { await viewModel.start() }
    while !repository.calls.contains(.open) { await Task.yield() }
    while !viewModel.reachedStart {
      await viewModel.loadOlder()
      await Task.yield()
    }
    await viewModel.loadOlderWhileVisible()
    #expect(repository.calls.filter { $0 == .loadOlder }.count == 1)
    repository.finish()
    await task.value
  }
}
