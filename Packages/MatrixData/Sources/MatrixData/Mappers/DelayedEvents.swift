import Domain
import Foundation

enum DelayedEvents {
  static let feature = "org.matrix.msc4140"
  static let version = "unstable/org.matrix.msc4140"
  static let delayParameter = "org.matrix.msc4140.delay"

  static func supports(_ versions: [String: Any]) -> Bool {
    (versions["unstable_features"] as? [String: Any])?[feature] as? Bool == true
  }

  static func delay(until date: Date, now: Date = .now) -> Int {
    max(1000, Int((date.timeIntervalSince(now) * 1000).rounded()))
  }

  static func content(text: String, replyTo: String?, emotes: [String: String] = [:])
    -> [String: Any]
  {
    let isEmote = text.hasPrefix("/me ")
    let typed = isEmote ? String(text.dropFirst(4)) : text
    var content: [String: Any] = ["msgtype": isEmote ? "m.emote" : "m.text", "body": typed]
    let rich = RichMarkdown.content(typed, emotes: emotes)
    let html = rich?.html ?? RichMarkdown.inlineHTML(typed, emotes: emotes)
    if let rich { content["body"] = rich.body }
    if html != RichMarkdown.escape(typed) {
      content["format"] = "org.matrix.custom.html"
      content["formatted_body"] = html
    }
    var mentions: [String: Any] = [:]
    let userIds = TimelineProxy.mentionedUserIds(in: typed)
    if !userIds.isEmpty { mentions["user_ids"] = userIds }
    if TimelineProxy.mentionsRoom(typed) { mentions["room"] = true }
    content["m.mentions"] = mentions
    if let replyTo { content["m.relates_to"] = ["m.in_reply_to": ["event_id": replyTo]] }
    return content
  }

  static func scheduled(_ response: [String: Any], roomId: String) -> [ScheduledMessage] {
    let events =
      response["delayed_events"] as? [[String: Any]] ?? response["scheduled"] as? [[String: Any]]
      ?? []
    return events.compactMap { event in
      guard let id = event["delay_id"] as? String, event["room_id"] as? String == roomId,
        event["type"] as? String == "m.room.message", event["state_key"] == nil,
        let content = event["content"] as? [String: Any],
        let body = content["body"] as? String,
        let msgtype = content["msgtype"] as? String, msgtype == "m.text" || msgtype == "m.emote"
      else { return nil }
      let since = number(event["delayed_since_ts"]) ?? number(event["running_since"]) ?? 0
      let delay = number(event["delay_ms"]) ?? number(event["delay"]) ?? 0
      let reply =
        ((content["m.relates_to"] as? [String: Any])?["m.in_reply_to"]
        as? [String: Any])?["event_id"] as? String
      return ScheduledMessage(
        id: id, text: msgtype == "m.emote" ? "/me " + body : body,
        sendAt: Date(timeIntervalSince1970: (since + delay) / 1000), replyTo: reply)
    }
    .sorted { $0.sendAt < $1.sendAt }
  }

  static func error(status: Int, body: Data) -> ScheduleError {
    let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
    let code = object["errcode"] as? String ?? ""
    if ["M_DELAY_TOO_LARGE", "ORG.MATRIX.MSC4140_DELAY_TOO_LARGE"].contains(code)
      || object["\(feature).errcode"] as? String == "M_MAX_DELAY_EXCEEDED"
    {
      return .delayTooLong(maxDelay: number(object["\(feature).max_delay"]).map { $0 / 1000 })
    }
    if status == 429, code == "M_LIMIT_EXCEEDED" { return .tooMany }
    if status == 400 || status == 404, code == "M_UNRECOGNIZED" { return .unsupported }
    return .failed
  }

  private static func number(_ value: Any?) -> Double? {
    (value as? NSNumber)?.doubleValue
  }
}
