import Testing

@testable import Room

struct BlurHashImageTests {
  /// One component only: "00" (a 1 by 1 grid, no detail) then the colour in four base 83 digits.
  @Test func aHashOfOneColourDrawsThatColour() throws {
    // 0x808080 in base 83: 8421504 = 14·83³ + 60·83² + 37·83 + 75, the digits "Eyb[".
    let pixels = try #require(BlurHashImage.pixels(from: "00Eyb[", width: 2, height: 2))
    #expect(pixels.count == 16)
    #expect(pixels[0] == 128)
    #expect(pixels[1] == 128)
    #expect(pixels[2] == 128)
    #expect(pixels[3] == 255)
  }

  @Test func aKnownHashGivesAPictureOfTheAskedSize() throws {
    let image = try #require(
      BlurHashImage.image(from: "LEHV6nWB2yk8pyo0adR*.7kCMdnj", width: 32, height: 24))
    #expect(image.cgImage?.width == 32)
    #expect(image.cgImage?.height == 24)
  }

  @Test func whatIsNotABlurHashGivesNothing() {
    #expect(BlurHashImage.image(from: "") == nil)
    #expect(BlurHashImage.image(from: "LEHV6nWB2yk8") == nil)
    #expect(BlurHashImage.image(from: "00 not base 83 ") == nil)
  }
}
