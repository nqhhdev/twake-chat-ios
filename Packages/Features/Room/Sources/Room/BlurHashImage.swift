import UIKit

/// Draws a BlurHash (blurha.sh): the few colours a sender attaches to a picture, shown blurred while the picture
/// loads. Written from the published algorithm; the encoder is in MatrixData (`BlurHash`).
enum BlurHashImage {
  private static let values: [Character: Int] = Dictionary(
    uniqueKeysWithValues: Array(
      "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~"
    ).enumerated().map { ($1, $0) })

  /// The picture of `hash`, `width` by `height` pixels (small: the view scales it up), or `nil` when `hash` is not a
  /// BlurHash.
  static func image(from hash: String, width: Int = 32, height: Int = 32) -> UIImage? {
    guard let pixels = pixels(from: hash, width: width, height: height) else { return nil }
    let data = Data(pixels) as CFData
    guard let provider = CGDataProvider(data: data),
      let image = CGImage(
        width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
        provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    else { return nil }
    return UIImage(cgImage: image)
  }

  /// The RGBA bytes of the picture, row by row.
  static func pixels(from hash: String, width: Int, height: Int) -> [UInt8]? {
    let characters = Array(hash)
    guard characters.count >= 6, width > 0, height > 0,
      let sizeFlag = number(characters[0..<1]), let quantised = number(characters[1..<2])
    else { return nil }
    let countY = sizeFlag / 9 + 1
    let countX = sizeFlag % 9 + 1
    guard characters.count == 4 + 2 * countX * countY else { return nil }
    let maximum = Float(quantised + 1) / 166
    var colours: [(Float, Float, Float)] = []
    for index in 0..<(countX * countY) {
      if index == 0 {
        guard let value = number(characters[2..<6]) else { return nil }
        colours.append((linear(value >> 16), linear((value >> 8) & 255), linear(value & 255)))
      } else {
        guard let value = number(characters[(4 + index * 2)..<(6 + index * 2)]) else { return nil }
        colours.append(
          (
            signedSquare(Float(value / 361) - 9) * maximum,
            signedSquare(Float((value / 19) % 19) - 9) * maximum,
            signedSquare(Float(value % 19) - 9) * maximum
          ))
      }
    }
    var pixels = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
      for x in 0..<width {
        var red: Float = 0
        var green: Float = 0
        var blue: Float = 0
        for j in 0..<countY {
          for i in 0..<countX {
            let basis =
              cos(Float.pi * Float(x) * Float(i) / Float(width))
              * cos(Float.pi * Float(y) * Float(j) / Float(height))
            let colour = colours[i + j * countX]
            red += colour.0 * basis
            green += colour.1 * basis
            blue += colour.2 * basis
          }
        }
        let offset = (y * width + x) * 4
        pixels[offset] = sRGB(red)
        pixels[offset + 1] = sRGB(green)
        pixels[offset + 2] = sRGB(blue)
      }
    }
    return pixels
  }

  /// The number a run of base 83 digits writes, or `nil` when a character is not a digit.
  private static func number(_ digits: ArraySlice<Character>) -> Int? {
    var result = 0
    for digit in digits {
      guard let value = values[digit] else { return nil }
      result = result * 83 + value
    }
    return result
  }

  private static func signedSquare(_ value: Float) -> Float {
    let scaled = value / 9
    return scaled < 0 ? -(scaled * scaled) : scaled * scaled
  }

  private static func linear(_ value: Int) -> Float {
    let scaled = Float(value) / 255
    return scaled <= 0.04045 ? scaled / 12.92 : pow((scaled + 0.055) / 1.055, 2.4)
  }

  private static func sRGB(_ value: Float) -> UInt8 {
    let clamped = max(0, min(1, value))
    let scaled = clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
    return UInt8(max(0, min(255, (scaled * 255).rounded())))
  }
}
