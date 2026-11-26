import Domain
import Foundation
import RoomTestSupport
import Testing

@testable import Room

@MainActor
struct PictureDescriptionTests {
  private func file(_ name: String) throws -> AttachmentLoader.Loaded {
    let folder = FileManager.default.temporaryDirectory.appending(path: "alt-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appending(path: name)
    try Data([1]).write(to: url)
    return AttachmentLoader.Loaded(
      kind: .image(width: 1, height: 1), fileURL: url, mimeType: "image/png", size: 1)
  }

  @Test func eachDescribedPictureCarriesItsDescriptionAndTheCaptionTakesTheLast() async throws {
    let repository = FakeTimelineRepository()
    let viewModel = RoomViewModel(
      roomId: "!r", roomName: "Team", repository: repository, media: FakeMediaRepository())
    let first = try file("a.png")
    let second = try file("b.png")
    let third = try file("c.png")
    await viewModel.send(
      batch: [first, second, third], caption: "Our trip",
      descriptions: [first.id: " A cat on a sofa ", second.id: "  ", third.id: "A dog"])
    let sent = repository.calls.compactMap { call -> OutgoingAttachment? in
      if case .attachment(let attachment) = call { attachment } else { nil }
    }
    #expect(sent.map(\.caption) == ["A cat on a sofa", nil, "Our trip"])
  }

  @Test func aLonePictureWithoutCaptionSendsItsDescription() async throws {
    let repository = FakeTimelineRepository()
    let viewModel = RoomViewModel(
      roomId: "!r", roomName: "Team", repository: repository, media: FakeMediaRepository())
    let picture = try file("a.png")
    await viewModel.send(batch: [picture], caption: "", descriptions: [picture.id: "A sunset"])
    let sent = repository.calls.compactMap { call -> OutgoingAttachment? in
      if case .attachment(let attachment) = call { attachment } else { nil }
    }
    #expect(sent.map(\.caption) == ["A sunset"])
  }

  @Test func voiceOverReadsTheDescriptionOfAPicture() {
    #expect(MessageMediaView.accessibilityLabel(of: .image(caption: "A cat")) == "A cat")
    #expect(MessageMediaView.accessibilityLabel(of: .image(caption: nil)) == "Picture")
    #expect(MessageMediaView.accessibilityLabel(of: .image(caption: " ")) == "Picture")
    #expect(MessageMediaView.accessibilityLabel(of: .video(caption: "Goal")) == "Video: Goal")
    #expect(MessageMediaView.accessibilityLabel(of: .sticker("Hi")) == "Sticker Hi")
  }
}
