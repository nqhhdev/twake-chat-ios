import Foundation

/// A picture, video, voice message or file of a message, as the room screen needs it to load and show it. `source` is
/// opaque: MatrixData writes it and reads it back (ADR 0006). No field holds the media itself.
public struct MediaReference: Sendable, Equatable, Hashable {
  public let source: String
  /// The source of the server's own thumbnail, when the sender attached one.
  public let thumbnailSource: String?
  public let mimeType: String?
  public let size: Int?
  public let width: Int?
  public let height: Int?

  public init(
    source: String, thumbnailSource: String? = nil, mimeType: String? = nil, size: Int? = nil,
    width: Int? = nil,
    height: Int? = nil
  ) {
    self.source = source
    self.thumbnailSource = thumbnailSource
    self.mimeType = mimeType
    self.size = size
    self.width = width
    self.height = height
  }

  /// Height over width, or `nil` when the sender did not give the size.
  public var aspectRatio: Double? {
    guard let width, let height, width > 0, height > 0 else { return nil }
    return Double(height) / Double(width)
  }
}

public enum MediaError: Error, Sendable, Equatable {
  case notSignedIn
  case downloadFailed
}

/// Loads a message's media from the homeserver (and decrypts it in an encrypted room). Implemented in MatrixData.
public protocol MediaRepository: Sendable {
  /// A thumbnail at least `width` × `height` points, from the server or the sender's own thumbnail.
  func thumbnail(_ media: MediaReference, width: Int, height: Int) async throws(MediaError) -> Data
  /// The whole media.
  func content(_ media: MediaReference) async throws(MediaError) -> Data
  /// The media saved as a file named `filename` in a temporary folder, to open or share it.
  func file(_ media: MediaReference, filename: String) async throws(MediaError) -> URL
}
