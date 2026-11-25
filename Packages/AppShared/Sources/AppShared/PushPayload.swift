import Foundation

public enum PushPayload {
  public static func unreadCount(in userInfo: [AnyHashable: Any]) -> Int? {
    guard let count = (userInfo["unread_count"] as? NSNumber)?.intValue, count >= 0 else {
      return nil
    }
    return count
  }

  public static let roomIdKey = "room_id"
  public static let eventIdKey = "event_id"
  public static let threadIdKey = "thread_id"
  public static let messageCategory = "message"
  public static let replyAction = "inline-reply"
  public static let markAsReadAction = "mark-as-read"

  public static func roomId(in userInfo: [AnyHashable: Any]) -> String? {
    nonEmpty(userInfo[roomIdKey])
  }

  public static func eventId(in userInfo: [AnyHashable: Any]) -> String? {
    nonEmpty(userInfo[eventIdKey])
  }

  public static func threadId(in userInfo: [AnyHashable: Any]) -> String? {
    nonEmpty(userInfo[threadIdKey])
  }

  private static func nonEmpty(_ value: Any?) -> String? {
    guard let text = value as? String, !text.isEmpty else { return nil }
    return text
  }
}
