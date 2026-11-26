import Domain
import Foundation
import RoomTestSupport
import Testing

@testable import Room

@MainActor
struct AlbumSendTests {
  private func file(_ name: String, kind: OutgoingAttachment.Kind = .image(width: 1, height: 1))
    throws -> AttachmentLoader.Loaded
  {
    let folder = FileManager.default.temporaryDirectory.appending(path: "album-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appending(path: name)
    try Data([1]).write(to: url)
    return AttachmentLoader.Loaded(kind: kind, fileURL: url, mimeType: "image/png", size: 1)
  }

  private func sent(_ repository: FakeTimelineRepository) -> [OutgoingAttachment] {
    repository.calls.compactMap { call -> OutgoingAttachment? in
      if case .attachment(let attachment) = call { attachment } else { nil }
    }
  }

  @Test func picturesSentTogetherShareOneBatchIdAndTheReplyGoesWithTheFirst() async throws {
    let repository = FakeTimelineRepository()
    let room = RoomViewModel(
      roomId: "!r", roomName: "Team", repository: repository, media: FakeMediaRepository())
    room.reply(
      to: TimelineMessage(
        eventId: "$q", senderId: "@bob", senderName: "Bob", isOwn: false, date: .now,
        body: .text("Photos?")))
    let pictures = [try file("a.png"), try file("b.png"), try file("c.png")]
    await room.send(batch: pictures, caption: "")
    let attachments = sent(repository)
    #expect(attachments.count == 3)
    let ids = Set(attachments.compactMap(\.batchId))
    #expect(ids.count == 1)
    #expect(ids.first.map { UUID(uuidString: $0) != nil } == true)
    #expect(ids.first == ids.first?.lowercased())
    #expect(attachments.map(\.replyTo) == ["$q", nil, nil])
  }

  @Test func aSinglePictureAndTheFilesOfABatchCarryNoBatchId() async throws {
    let repository = FakeTimelineRepository()
    let room = RoomViewModel(
      roomId: "!r", roomName: "Team", repository: repository, media: FakeMediaRepository())
    await room.send(batch: [try file("a.png")], caption: "")
    await room.send(
      batch: [try file("b.png"), try file("c.png"), try file("d.pdf", kind: .file)], caption: "")
    #expect(sent(repository).map { $0.batchId != nil } == [false, true, true, false])
  }

  @Test func oneVisualItemAmongFilesIsNoAlbum() throws {
    let batch = [try file("a.png"), try file("b.pdf", kind: .file)]
    #expect(RoomViewModel.albumId(for: batch) == nil)
    let fixed = UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!
    #expect(
      RoomViewModel.albumId(for: [try file("a.png"), try file("b.png")], make: { fixed })
        == "6f9619ff-8b86-d011-b42d-00c04fc964ff")
  }
}
