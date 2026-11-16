import Domain
import Foundation
import MatrixRustSDK
import UniformTypeIdentifiers

/// `MediaRepository` on the SDK client (ADR 0006): thumbnails and content come from the homeserver's media repository
/// and are decrypted by the SDK in encrypted rooms. Thumbnails are kept in memory for the session; nothing is written
/// to disk except a file the user opens, in a temporary folder. Nothing here logs.
public actor MediaProxy: MediaRepository {
  private let clientProxy: @Sendable () async -> ClientProxy?
  private let thumbnails = NSCache<NSString, NSData>()

  public init(authentication: MatrixAuthenticationRepository) {
    clientProxy = { await authentication.clientProxy }
    thumbnails.totalCostLimit = 64 * 1024 * 1024
  }

  public func thumbnail(_ media: MediaReference, width: Int, height: Int) async throws(MediaError)
    -> Data
  {
    let key = "\(media.source)|\(width)x\(height)" as NSString
    if let cached = thumbnails.object(forKey: key) { return cached as Data }
    let client = try await client()
    do {
      let data: Data
      if let thumbnailSource = media.thumbnailSource {
        // The sender's own thumbnail: in an encrypted room the server cannot make one.
        data = try await client.client.getMediaContent(
          mediaSource: MediaSource.fromJson(json: thumbnailSource))
      } else {
        data = try await client.client.getMediaThumbnail(
          mediaSource: MediaSource.fromJson(json: media.source), width: UInt64(width),
          height: UInt64(height))
      }
      thumbnails.setObject(data as NSData, forKey: key, cost: data.count)
      return data
    } catch {
      // The server cannot thumbnail every type (or an encrypted file): fall back to the whole media for pictures.
      if media.mimeType?.hasPrefix("image/") == true { return try await content(media) }
      throw .downloadFailed
    }
  }

  public func maxUploadSize() async -> Int? {
    guard let client = await clientProxy()?.client,
      let size = try? await client.getMaxMediaUploadSize(), size > 0
    else { return nil }
    return Int(clamping: size)
  }

  public func content(_ media: MediaReference) async throws(MediaError) -> Data {
    let client = try await client()
    do {
      return try await client.client.getMediaContent(
        mediaSource: MediaSource.fromJson(json: media.source))
    } catch {
      throw .downloadFailed
    }
  }

  public func file(_ media: MediaReference, filename: String) async throws(MediaError) -> URL {
    let data = try await content(media)
    let folder = FileManager.default.temporaryDirectory.appending(
      path: UUID().uuidString, directoryHint: .isDirectory)
    let name = Self.fileName(filename, mimeType: media.mimeType)
    do {
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let url = folder.appending(path: name)
      try data.write(to: url, options: [.completeFileProtection])
      return url
    } catch {
      throw .downloadFailed
    }
  }

  /// The name a downloaded file gets: the last part of the one given, with the extension its MIME type calls for when
  /// it has none ("image" becomes "image.jpeg"), so Quick Look and the share sheet know it and offer Save Image.
  static func fileName(_ filename: String, mimeType: String?) -> String {
    let name = filename.isEmpty ? "file" : (filename as NSString).lastPathComponent
    guard (name as NSString).pathExtension.isEmpty,
      let ext = mimeType.flatMap({ UTType(mimeType: $0) })?.preferredFilenameExtension
    else { return name }
    return "\(name).\(ext)"
  }

  private func client() async throws(MediaError) -> ClientProxy {
    guard let client = await clientProxy() else { throw .notSignedIn }
    return client
  }
}
