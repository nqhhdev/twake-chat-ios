import Foundation
import Testing

@testable import MatrixData

/// The SDK refuses a picture or video without a blurhash (`RoomError.InvalidAttachmentData`).
struct AttachmentMetadataTests {
  @Test func aPlainWhitePictureHasTheBlurHashOfWhite() {
    let white = [UInt8](repeating: 255, count: 4 * 4 * 4)
    // The well-known BlurHash of plain white, as the reference encoders give it.
    #expect(BlurHash.encode(pixels: white, width: 4, height: 4) == "L~TSUA~qfQ~q~q%MfQ%MfQfQfQfQ")
  }

  @Test func anyPictureGivesTwentyEightCharacters() {
    var pixels: [UInt8] = []
    for index in 0..<64 { pixels += [UInt8(index * 4), 0, UInt8(255 - index * 4), 255] }
    let hash = BlurHash.encode(pixels: pixels, width: 8, height: 8)
    #expect(hash.count == 28)
    #expect(
      hash != BlurHash.encode(pixels: [UInt8](repeating: 255, count: 256), width: 8, height: 8))
    #expect(BlurHash.placeholder.count == 28)
  }

  @Test func theSizeOnDiskIsUsedWhenNoneIsGiven() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).bin")
    try Data(count: 1_234).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(AttachmentMetadata.size(of: url, given: nil) == 1_234)
    #expect(AttachmentMetadata.size(of: url, given: 99) == 99)
  }
}
