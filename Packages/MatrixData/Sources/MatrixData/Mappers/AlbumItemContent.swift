import Foundation

enum AlbumItemContent {
  enum Media {
    case url(String)
    case file([String: Any])
  }

  struct Item {
    let isVideo: Bool
    let filename: String
    let caption: String?
    let mimeType: String
    let size: UInt64
    let width: UInt64
    let height: UInt64
    let blurhash: String?
    let duration: TimeInterval?
    let media: Media
    let thumbnail: Media?
    let thumbnailInfo: [String: Any]?
  }

  static func content(
    _ item: Item, batchId: String, replyTo: String?, threadRoot: String?
  ) -> [String: Any] {
    var info: [String: Any] = [
      "mimetype": item.mimeType, "size": item.size, "w": item.width, "h": item.height,
    ]
    if let blurhash = item.blurhash { info["xyz.amorgan.blurhash"] = blurhash }
    if item.isVideo, let duration = item.duration {
      info["duration"] = Int((duration * 1000).rounded())
    }
    if let thumbnailInfo = item.thumbnailInfo, let thumbnail = item.thumbnail {
      info["thumbnail_info"] = thumbnailInfo
      switch thumbnail {
      case .url(let url): info["thumbnail_url"] = url
      case .file(let file): info["thumbnail_file"] = file
      }
    }
    let caption = item.caption?.trimmingCharacters(in: .whitespacesAndNewlines)
    var content: [String: Any] = [
      "msgtype": item.isVideo ? "m.video" : "m.image",
      "body": caption.flatMap { $0.isEmpty ? nil : $0 } ?? item.filename,
      "filename": item.filename,
      "info": info,
      MediaBatch.contentKey: batchId,
    ]
    switch item.media {
    case .url(let url): content["url"] = url
    case .file(let file): content["file"] = file
    }
    if let threadRoot {
      content["m.relates_to"] = [
        "rel_type": "m.thread", "event_id": threadRoot, "is_falling_back": replyTo == nil,
        "m.in_reply_to": ["event_id": replyTo ?? threadRoot],
      ]
    } else if let replyTo {
      content["m.relates_to"] = ["m.in_reply_to": ["event_id": replyTo]]
    }
    return content
  }
}
