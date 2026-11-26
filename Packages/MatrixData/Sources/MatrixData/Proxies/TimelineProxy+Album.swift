import Domain
import Foundation
import MatrixRustSDK

extension TimelineProxy {
  func sendAlbumItem(_ attachment: OutgoingAttachment, batchId: String)
    async throws(TimelineError)
  {
    let opened = try openedState()
    let client = opened.client.client
    let url = attachment.fileURL
    guard let data = try? Data(contentsOf: url) else { throw .uploadFailed }
    let isEncrypted = (try? await opened.room.latestEncryptionState()) != .notEncrypted
    let mimeType = Self.mimeType(for: attachment)
    var isVideo = false
    var visual: AttachmentMetadata.Visual
    var thumbnail: AttachmentMetadata.Thumbnail?
    switch attachment.kind {
    case .video(let width, let height, let duration):
      isVideo = true
      visual = await AttachmentMetadata.video(
        at: url, width: width, height: height, duration: duration)
      thumbnail = await AttachmentMetadata.videoThumbnail(at: url)
    case .image(let width, let height):
      visual = AttachmentMetadata.image(at: url, width: width, height: height)
      thumbnail = AttachmentMetadata.imageThumbnail(at: url)
    default:
      throw .unsupportedType
    }
    defer { if let thumbnail { try? FileManager.default.removeItem(at: thumbnail.url) } }
    do {
      let media = try await Self.upload(
        data, mimeType: mimeType, encrypted: isEncrypted, client: client)
      var thumbnailMedia: AlbumItemContent.Media?
      var thumbnailInfo: [String: Any]?
      if let thumbnail, let thumbnailData = try? Data(contentsOf: thumbnail.url) {
        thumbnailMedia = try await Self.upload(
          thumbnailData, mimeType: "image/jpeg", encrypted: isEncrypted, client: client)
        thumbnailInfo = [
          "mimetype": "image/jpeg", "size": thumbnail.size, "w": thumbnail.width,
          "h": thumbnail.height,
        ]
      }
      let item = AlbumItemContent.Item(
        isVideo: isVideo, filename: url.lastPathComponent, caption: attachment.caption,
        mimeType: mimeType, size: AttachmentMetadata.size(of: url, given: attachment.size),
        width: visual.width, height: visual.height, blurhash: visual.blurhash,
        duration: isVideo ? visual.duration : nil, media: media, thumbnail: thumbnailMedia,
        thumbnailInfo: thumbnailInfo)
      let content = AlbumItemContent.content(
        item, batchId: batchId, replyTo: attachment.replyTo, threadRoot: threadRoot)
      let json = try JSONSerialization.data(withJSONObject: content)
      try await opened.room.sendRaw(
        eventType: "m.room.message", content: String(decoding: json, as: UTF8.self))
    } catch {
      throw Self.failure("sendAlbumItem", error)
    }
  }

  private static func upload(
    _ data: Data, mimeType: String, encrypted: Bool, client: Client
  ) async throws -> AlbumItemContent.Media {
    guard encrypted else {
      return .url(
        try await client.uploadMedia(mimeType: mimeType, data: data, progressWatcher: nil))
    }
    let sealed = try AttachmentCrypto.encrypt(data)
    let url = try await client.uploadMedia(
      mimeType: "application/octet-stream", data: sealed.data, progressWatcher: nil)
    return .file(sealed.file(url: url))
  }
}
