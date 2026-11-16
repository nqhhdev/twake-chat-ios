import Foundation

/// The key Twake web and Flutter write on every file of one send (`app.twake.chat.batch`, a UUID string), which ties
/// those pictures into one album (Flutter `MediaBatchStamp`). In an encrypted room it sits inside the encrypted content.
/// This client reads it; it cannot write it yet, because the SDK's attachment upload takes no extra content field.
enum MediaBatch {
  static let contentKey = "app.twake.chat.batch"

  /// The batch id in an event's original JSON (`EventTimelineItemDebugInfo.originalJson`), or `nil` when it has none.
  static func id(inOriginalJSON json: String?) -> String? {
    guard let json,
      let event = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
      let content = event["content"] as? [String: Any],
      let id = content[contentKey] as? String, !id.isEmpty
    else { return nil }
    return id
  }

  /// Removes the batch id from content being forwarded: a copy never keeps the id of the original send, or forwarding
  /// two pictures of one album into a room would merge them into one album there.
  static func remove(from content: inout [String: Any]) {
    content[contentKey] = nil
  }
}
