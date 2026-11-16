import Testing

@testable import MatrixData

/// The thumbnail size asked of the homeserver (`MediaProxy.serverSize`).
struct MediaThumbnailSizeTests {
  @Test func aSmallSizeIsAskedAsItIs() {
    let size = MediaProxy.serverSize(width: 300, height: 200)
    #expect(size.width == 300)
    #expect(size.height == 200)
  }

  @Test func aLargeSizeIsScaledDownWithItsShape() {
    let wide = MediaProxy.serverSize(width: 1600, height: 600)
    #expect(wide.width == 800)
    #expect(wide.height == 300)
    let tall = MediaProxy.serverSize(width: 1032, height: 1376)
    #expect(tall.height == 600)
    #expect(tall.width == 450)
  }

  @Test func aSizeOfNothingAsksForTheLargestThumbnail() {
    let size = MediaProxy.serverSize(width: 0, height: 0)
    #expect(size.width == 800)
    #expect(size.height == 600)
  }
}
