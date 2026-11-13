import DesignSystem
import Testing
import UIKit

/// Avatar pictures are cut to a square and scaled down before they upload.
struct PreparedPictureTests {
  private func png(width: CGFloat, height: CGFloat) -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
      .pngData { context in
        UIColor.systemBlue.setFill()
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
      }
  }

  @Test func aLargeWidePhotoBecomesASquareOfAtMost512() throws {
    let prepared = try #require(PreparedPicture.prepare(png(width: 2000, height: 1200)))
    #expect(prepared.side == 512)
    let image = try #require(UIImage(data: prepared.jpeg))
    #expect(image.size.width * image.scale == 512)
    #expect(image.size.height * image.scale == 512)
  }

  @Test func aSmallPictureKeepsItsShortSide() throws {
    let prepared = try #require(PreparedPicture.prepare(png(width: 300, height: 200)))
    #expect(prepared.side == 200)
  }

  @Test func dataThatIsNotAPictureIsRefused() {
    #expect(PreparedPicture.prepare(Data("nope".utf8)) == nil)
  }
}
