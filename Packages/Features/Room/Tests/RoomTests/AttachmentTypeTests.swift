import Domain
import Foundation
import Testing
import UIKit
import UniformTypeIdentifiers

@testable import Room

/// A picked file is sent with the MIME type and extension of what it is, not of what the picker listed first.
struct AttachmentTypeTests {
  private var png: Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4), format: format).pngData {
      context in
      UIColor.systemBlue.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    }
  }

  @Test func thePictureBytesWinOverTheListedTypes() {
    let type = AttachmentType.of(data: png, offered: [.heic, .jpeg])
    #expect(type == .png)
    #expect(type.preferredMIMEType == "image/png")
    #expect(type.preferredFilenameExtension == "png")
  }

  @Test func aVideoTakesTheFirstListedPictureOrVideoType() {
    let type = AttachmentType.of(
      data: Data(count: 32), offered: [.data, .quickTimeMovie, .mpeg4Movie])
    #expect(type == .quickTimeMovie)
    #expect(type.preferredMIMEType == "video/quicktime")
    // A video's bytes are never read as a picture.
    #expect(AttachmentType.of(data: png, offered: [.quickTimeMovie]) == .quickTimeMovie)
  }

  @Test func withNothingUsableItFallsBackToTheFirstListedTypeThenJPEG() {
    #expect(AttachmentType.of(data: Data(count: 32), offered: [.data]) == .data)
    #expect(AttachmentType.of(data: Data(count: 32), offered: []) == .jpeg)
  }

  @Test func aDocumentIsTypedByItsFile() throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let pdf = folder.appending(path: "Report.PDF")
    try Data("%PDF-1.4".utf8).write(to: pdf)
    #expect(AttachmentType.of(file: pdf)?.preferredMIMEType == "application/pdf")
    let unknown = folder.appending(path: "notes.qqqzzz")
    try Data(count: 8).write(to: unknown)
    // An extension the system does not know has no MIME type; the data layer sends it as application/octet-stream.
    #expect(AttachmentType.of(file: unknown)?.preferredMIMEType == nil)
  }

  @Test func theKindFollowsTheType() {
    #expect(AttachmentType.kind(of: .png) == .image(width: nil, height: nil))
    #expect(
      AttachmentType.kind(of: .quickTimeMovie) == .video(width: nil, height: nil, duration: nil))
    #expect(AttachmentType.kind(of: .mp3) == .audio(duration: nil))
    #expect(AttachmentType.kind(of: .pdf) == .file)
    #expect(AttachmentType.kind(of: nil) == .file)
  }
}
