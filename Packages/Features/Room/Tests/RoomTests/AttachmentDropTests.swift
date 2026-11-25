import Domain
import Foundation
import RoomTestSupport
import Testing
import UniformTypeIdentifiers

@testable import Room

@MainActor
struct AttachmentDropTests {
  @Test func aPictureFromPhotosIsTakenAsThePictureItHolds() {
    #expect(AttachmentDrop.fileType(offered: [.heic, .jpeg], isNamed: true) == .heic)
  }

  @Test func aVideoOrASoundIsPreferredToTheTextBesideIt() {
    #expect(
      AttachmentDrop.fileType(offered: [.plainText, .mpeg4Movie], isNamed: false) == .mpeg4Movie)
    #expect(AttachmentDrop.fileType(offered: [.url, .mp3], isNamed: false) == .mp3)
  }

  @Test func aDocumentFromFilesIsTakenAsItsOwnType() {
    #expect(AttachmentDrop.fileType(offered: [.url, .pdf], isNamed: true) == .pdf)
    #expect(AttachmentDrop.fileType(offered: [.zip], isNamed: false) == .zip)
  }

  @Test func draggedTextOrALinkIsNotAFile() {
    #expect(AttachmentDrop.fileType(offered: [.utf8PlainText, .html], isNamed: false) == nil)
    #expect(AttachmentDrop.fileType(offered: [.url], isNamed: true) == nil)
    #expect(AttachmentDrop.fileType(offered: [], isNamed: true) == nil)
  }

  @Test func aNamedTextFileIsAFile() {
    #expect(AttachmentDrop.fileType(offered: [.plainText], isNamed: true) == .plainText)
  }

  @Test func theFileKeepsItsNameAndGetsTheExtensionOfItsType() {
    #expect(AttachmentDrop.fileName(suggested: "IMG_0001", type: .jpeg) == "IMG_0001.jpeg")
    #expect(AttachmentDrop.fileName(suggested: "IMG_0001.JPG", type: .jpeg) == "IMG_0001.JPG")
    #expect(AttachmentDrop.fileName(suggested: "Report v1.2", type: .pdf) == "Report v1.2.pdf")
    #expect(AttachmentDrop.fileName(suggested: " a/b.pdf ", type: .pdf) == "a-b.pdf")
  }

  @Test func aFileWithoutANameGetsAUniqueOne() {
    let name = AttachmentDrop.fileName(suggested: nil, type: .png)
    #expect(name.hasSuffix(".png"))
    #expect(name != AttachmentDrop.fileName(suggested: "  ", type: .png))
  }

  @Test func aDroppedFileIsCopiedUnderItsNameAndTypedByIt() throws {
    let source = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).tmp")
    try Data("hello".utf8).write(to: source)
    defer { try? FileManager.default.removeItem(at: source) }

    let loaded = try #require(AttachmentDrop.stage(source, named: "notes.pdf"))
    defer { AttachmentLoader.remove(loaded) }

    #expect(loaded.fileURL.lastPathComponent == "notes.pdf")
    #expect(loaded.mimeType == "application/pdf")
    #expect(loaded.kind == .file)
    #expect(loaded.size == 5)
    #expect(FileManager.default.fileExists(atPath: loaded.fileURL.path(percentEncoded: false)))
  }

  @Test func aFileThatCannotBeReadIsSkipped() {
    let missing = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    #expect(AttachmentDrop.stage(missing, named: "gone.png") == nil)
  }

  @Test func theDroppedFilesArriveTogetherInTheOrderTheyWereDropped() throws {
    let first = try #require(Self.file("a.txt"))
    let second = try #require(Self.file("b.txt"))
    defer { [first, second].forEach(AttachmentLoader.remove) }
    var delivered: [[UUID]] = []
    let gathering = DropGathering(count: 3) { items in delivered.append(items.map(\.id)) }

    gathering.receive(second, at: 2)
    gathering.receive(nil, at: 1)
    #expect(delivered.isEmpty)
    gathering.receive(first, at: 0)
    gathering.receive(first, at: 0)

    #expect(delivered == [[first.id, second.id]])
  }

  @Test func filesAreTakenOnlyWhereTheComposerIsShown() {
    let open = viewModel()
    #expect(open.acceptsDroppedFiles)

    open.isSelectingMessages = true
    #expect(!open.acceptsDroppedFiles)

    let blocked = viewModel()
    blocked.blockedUserId = "@bob:example.org"
    #expect(!blocked.acceptsDroppedFiles)

    #expect(!viewModel(isArchived: true).acceptsDroppedFiles)
  }

  private func viewModel(isArchived: Bool = false) -> RoomViewModel {
    RoomViewModel(
      roomId: "!room:example.org", roomName: "Team", repository: FakeTimelineRepository(),
      media: FakeMediaRepository(), isArchived: isArchived)
  }

  private static func file(_ name: String) -> AttachmentLoader.Loaded? {
    let source = FileManager.default.temporaryDirectory.appending(
      path: "\(UUID().uuidString)-\(name)")
    guard (try? Data("x".utf8).write(to: source)) != nil else { return nil }
    defer { try? FileManager.default.removeItem(at: source) }
    return AttachmentDrop.stage(source, named: name)
  }
}
