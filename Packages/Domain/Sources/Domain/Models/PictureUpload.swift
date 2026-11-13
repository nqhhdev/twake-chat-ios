import Foundation

/// A picture to set as the user's or a room's avatar: encoded, with its type and size in pixels.
public struct PictureUpload: Sendable, Equatable {
  public let data: Data
  public let mimeType: String
  public let width: Int
  public let height: Int

  public init(data: Data, mimeType: String, width: Int, height: Int) {
    self.data = data
    self.mimeType = mimeType
    self.width = width
    self.height = height
  }
}

extension PictureUpload: CustomStringConvertible {
  /// The picture is the user's: never in logs (ADR 0009).
  public var description: String { "PictureUpload(\(mimeType), \(width)x\(height), <redacted>)" }
}
