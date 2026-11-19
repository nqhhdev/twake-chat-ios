import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

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

/// Receivers show a picture's or video's thumbnail while the media loads; the SDK uploads the file given as
/// `thumbnailSource` and fills `thumbnail_info` from `ThumbnailInfo`.
struct AttachmentThumbnailTests {
  private func picture(width: Int, height: Int) throws -> URL {
    let context = try #require(
      CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    context.setFillColor(red: 0, green: 0.4, blue: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).png")
    let destination = try #require(
      CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return url
  }

  @Test func aLargePictureGetsAJPEGThumbnailOfAtMost800() throws {
    let url = try picture(width: 2_000, height: 1_000)
    defer { try? FileManager.default.removeItem(at: url) }
    let thumbnail = try #require(AttachmentMetadata.imageThumbnail(at: url))
    defer { try? FileManager.default.removeItem(at: thumbnail.url) }
    #expect(thumbnail.width == 800)
    #expect(thumbnail.height == 400)
    #expect(thumbnail.size > 0)
    #expect(thumbnail.size == AttachmentMetadata.size(of: thumbnail.url, given: nil))
    let source = try #require(CGImageSourceCreateWithURL(thumbnail.url as CFURL, nil))
    #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
  }

  @Test func aSmallPictureIsItsOwnThumbnail() throws {
    let url = try picture(width: 300, height: 200)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(AttachmentMetadata.imageThumbnail(at: url) == nil)
  }

  @Test func aFileThatIsNoPictureHasNoThumbnail() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).bin")
    try Data(count: 64).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    #expect(AttachmentMetadata.imageThumbnail(at: url) == nil)
  }
}
