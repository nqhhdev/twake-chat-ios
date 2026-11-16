import Testing

@testable import MatrixData

/// A downloaded file needs an extension for Quick Look and the share sheet to know it (Save Image, Save Video).
struct MediaFileNameTests {
  @Test func aPictureWithoutAnExtensionGetsItsMIMETypes() {
    #expect(MediaProxy.fileName("image", mimeType: "image/jpeg") == "image.jpeg")
    #expect(MediaProxy.fileName("video", mimeType: "video/mp4") == "video.mp4")
  }

  @Test func aNameWithAnExtensionIsKept() {
    #expect(MediaProxy.fileName("report.pdf", mimeType: "image/png") == "report.pdf")
  }

  @Test func onlyTheLastPartOfThePathIsKept() {
    #expect(MediaProxy.fileName("../../etc/report.pdf", mimeType: nil) == "report.pdf")
  }

  @Test func anEmptyOrUnknownNameStaysReadable() {
    #expect(MediaProxy.fileName("", mimeType: nil) == "file")
    #expect(MediaProxy.fileName("notes", mimeType: "application/x-unknown-type") == "notes")
  }
}
