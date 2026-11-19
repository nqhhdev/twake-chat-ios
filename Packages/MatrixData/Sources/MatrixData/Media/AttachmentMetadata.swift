import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// What the SDK needs before it sends a media message. Its FFI turns `ImageInfo` and `VideoInfo` into the event's
/// info and refuses the attachment (`RoomError.InvalidAttachmentData`) when the width, height, size or blurhash is
/// missing, and an audio file without its duration; Element X fills them the same way before sending.
enum AttachmentMetadata {
  struct Visual: Sendable, Equatable {
    let width: UInt64
    let height: UInt64
    let blurhash: String
    var duration: TimeInterval?
  }

  /// The file's size: the one given, else the size on disk, else 0.
  static func size(of url: URL, given: Int?) -> UInt64 {
    if let given, given > 0 { return UInt64(given) }
    let attributes = try? FileManager.default.attributesOfItem(
      atPath: url.path(percentEncoded: false))
    return (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
  }

  /// A picture's size as it shows (EXIF orientation applied) and its blurhash; the sizes given win when set.
  static func image(at url: URL, width: Int?, height: Int?) -> Visual {
    var pixelWidth = width
    var pixelHeight = height
    var blurhash: String?
    if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
      if pixelWidth == nil || pixelHeight == nil,
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
        let w = properties[kCGImagePropertyPixelWidth] as? Int,
        let h = properties[kCGImagePropertyPixelHeight] as? Int
      {
        // Orientations 5 to 8 turn the picture a quarter turn: its width shows as its height.
        let turned = ((properties[kCGImagePropertyOrientation] as? Int) ?? 1) >= 5
        pixelWidth = turned ? h : w
        pixelHeight = turned ? w : h
      }
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 64,
      ]
      if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
        blurhash = BlurHash.encode(thumbnail)
      }
    }
    return Visual(
      width: UInt64(max(1, pixelWidth ?? 1)), height: UInt64(max(1, pixelHeight ?? 1)),
      blurhash: blurhash ?? BlurHash.placeholder)
  }

  /// A video's size as it plays (its track transform applied), its duration and the blurhash of its first frame.
  static func video(at url: URL, width: Int?, height: Int?, duration: TimeInterval?) async -> Visual
  {
    let asset = AVURLAsset(url: url)
    var size = (width: width, height: height)
    var seconds = duration
    if seconds == nil, let loaded = try? await asset.load(.duration), loaded.seconds.isFinite {
      seconds = loaded.seconds
    }
    if size.width == nil || size.height == nil,
      let track = try? await asset.loadTracks(withMediaType: .video).first,
      let loaded = try? await track.load(.naturalSize, .preferredTransform)
    {
      let shown = loaded.0.applying(loaded.1)
      size = (Int(abs(shown.width).rounded()), Int(abs(shown.height).rounded()))
    }
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 64, height: 64)
    let frame = try? await generator.image(at: .zero).image
    return Visual(
      width: UInt64(max(1, size.width ?? 1)), height: UInt64(max(1, size.height ?? 1)),
      blurhash: frame.flatMap(BlurHash.encode) ?? BlurHash.placeholder, duration: seconds ?? 0)
  }

  /// A JPEG thumbnail in a temporary file, which the caller deletes once the attachment is sent. Receivers show it
  /// while the media loads.
  struct Thumbnail: Sendable, Equatable {
    let url: URL
    let width: UInt64
    let height: UInt64
    let size: UInt64
  }

  /// The longest side of a thumbnail, in pixels.
  static let thumbnailMaxSide = 800

  /// A thumbnail of a picture larger than a thumbnail, as it shows (EXIF orientation applied); `nil` for a smaller
  /// picture, which receivers show itself, and for a file that is no picture.
  static func imageThumbnail(at url: URL) -> Thumbnail? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      max(width, height) > thumbnailMaxSide
    else { return nil }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxSide,
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { return nil }
    return writeThumbnail(image)
  }

  /// A thumbnail of a video's first frame, as it plays (its track transform applied).
  static func videoThumbnail(at url: URL) async -> Thumbnail? {
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: thumbnailMaxSide, height: thumbnailMaxSide)
    guard let frame = try? await generator.image(at: .zero).image else { return nil }
    return writeThumbnail(frame)
  }

  private static func writeThumbnail(_ image: CGImage) -> Thumbnail? {
    let url = FileManager.default.temporaryDirectory.appending(
      path: "thumbnail-\(UUID().uuidString).jpg")
    guard
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
    else { return nil }
    let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.8]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return Thumbnail(
      url: url, width: UInt64(image.width), height: UInt64(image.height),
      size: size(of: url, given: nil))
  }

  /// An audio file's duration: the one given, else read from the file, else 0.
  static func audioDuration(of url: URL, given: TimeInterval?) async -> TimeInterval {
    if let given { return given }
    guard let loaded = try? await AVURLAsset(url: url).load(.duration), loaded.seconds.isFinite
    else { return 0 }
    return loaded.seconds
  }
}

/// The BlurHash of a picture (blurha.sh): a few cosine components of its colours in base 83, which receivers draw as
/// a blurred placeholder while the media loads. Written from the published algorithm.
enum BlurHash {
  /// A plain grey, for media whose pixels cannot be read.
  static let placeholder = encode(pixels: [128, 128, 128, 255], width: 1, height: 1)

  private static let characters = Array(
    "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz#$%*+,-.:;=?@[]^_{|}~")

  /// Draws the picture into a small RGBA buffer and encodes it with 4 × 3 components.
  static func encode(_ image: CGImage) -> String? {
    let width = max(1, min(image.width, 64))
    let height = max(1, min(image.height, 64))
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard
        let context = CGContext(
          data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    return drawn ? encode(pixels: pixels, width: width, height: height) : nil
  }

  /// Encodes RGBA pixels, row by row, with `componentsX` × `componentsY` components (1 to 9 each).
  static func encode(
    pixels: [UInt8], width: Int, height: Int, componentsX: Int = 4, componentsY: Int = 3
  ) -> String {
    var factors: [(r: Float, g: Float, b: Float)] = []
    for j in 0..<componentsY {
      for i in 0..<componentsX {
        let normalisation: Float = (i == 0 && j == 0) ? 1 : 2
        var r: Float = 0
        var g: Float = 0
        var b: Float = 0
        for y in 0..<height {
          let basisY = cos(Float.pi * Float(j) * Float(y) / Float(height))
          for x in 0..<width {
            let basis = basisY * cos(Float.pi * Float(i) * Float(x) / Float(width))
            let index = (y * width + x) * 4
            r += basis * linear(pixels[index])
            g += basis * linear(pixels[index + 1])
            b += basis * linear(pixels[index + 2])
          }
        }
        let scale = normalisation / Float(width * height)
        factors.append((r * scale, g * scale, b * scale))
      }
    }
    let dc = factors[0]
    let ac = factors.dropFirst()
    var hash = base83((componentsX - 1) + (componentsY - 1) * 9, length: 1)
    let maximum: Float
    if ac.isEmpty {
      maximum = 1
      hash += base83(0, length: 1)
    } else {
      let actual = ac.map { max(abs($0.r), abs($0.g), abs($0.b)) }.max() ?? 0
      let quantised = Int(max(0, min(82, (actual * 166 - 0.5).rounded(.down))))
      maximum = Float(quantised + 1) / 166
      hash += base83(quantised, length: 1)
    }
    hash += base83((sRGB(dc.r) << 16) + (sRGB(dc.g) << 8) + sRGB(dc.b), length: 4)
    for factor in ac {
      func quantise(_ value: Float) -> Int {
        Int(max(0, min(18, (signedSquareRoot(value / maximum) * 9 + 9.5).rounded(.down))))
      }
      hash += base83(
        quantise(factor.r) * 19 * 19 + quantise(factor.g) * 19 + quantise(factor.b), length: 2)
    }
    return hash
  }

  private static func linear(_ value: UInt8) -> Float {
    let v = Float(value) / 255
    return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
  }

  private static func sRGB(_ value: Float) -> Int {
    let v = max(0, min(1, value))
    return v <= 0.003_130_8
      ? Int(v * 12.92 * 255 + 0.5) : Int((1.055 * pow(v, 1 / 2.4) - 0.055) * 255 + 0.5)
  }

  private static func signedSquareRoot(_ value: Float) -> Float {
    value < 0 ? -(-value).squareRoot() : value.squareRoot()
  }

  private static func base83(_ value: Int, length: Int) -> String {
    var result = ""
    for position in (0..<length).reversed() {
      var divisor = 1
      for _ in 0..<position { divisor *= 83 }
      result.append(characters[(value / divisor) % 83])
    }
    return result
  }
}
