import Domain
import Foundation

/// How the Twake clients mark calls in Matrix (#92), read and written byte for byte as the Flutter app and the web
/// client do: a Meet call is a text message with its link under `call_url`; the web marks the message that opens a
/// call's thread with `app.twake.chat.call_thread`. Call signalling and MatrixRTC events never show in the timeline.
enum CallEvents {
  static let linkKey = "call_url"
  static let threadKey = "app.twake.chat.call_thread"

  private static let memberType = "org.matrix.msc3401.call.member"
  private static let notifyTypes: Set<String> = [
    "org.matrix.msc4075.call.notify", "org.matrix.msc4075.rtc.notification", "m.rtc.notification",
  ]
  private static let prefixes = ["m.call.", "org.matrix.call.", "com.famedly.call."]

  /// Call signalling and MatrixRTC events, legacy ones included, which the room never shows.
  static func isCallEvent(_ type: String) -> Bool {
    type == memberType || notifyTypes.contains(type) || prefixes.contains { type.hasPrefix($0) }
  }

  /// The call mark of a text message, from its original JSON (`EventTimelineItemDebugInfo.originalJson`); `nil` for
  /// any other message. The keys are looked for in the text first, so most messages skip the parse.
  static func mark(inOriginalJSON json: String?) -> TimelineMessage.Call? {
    guard let json, json.contains(linkKey) || json.contains(threadKey),
      let event = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
      let content = event["content"] as? [String: Any]
    else { return nil }
    if content[threadKey] != nil { return .threadRoot }
    if let link = content[linkKey] as? String, !link.isEmpty { return .link(link) }
    return nil
  }

  /// The content of a call message: `text` and the link, as the body, and the link under `call_url`.
  static func messageContent(text: String, link: URL) -> [String: Any] {
    ["msgtype": "m.text", "body": "\(text) \(link.absoluteString)", linkKey: link.absoluteString]
  }
}
