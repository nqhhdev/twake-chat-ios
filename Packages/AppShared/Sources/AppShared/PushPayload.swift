import Foundation

/// Reads the push gateway's payload (ADR 0009, keys kept as the Flutter app's pusher asks for them, ADR 0017).
public enum PushPayload {
  /// The homeserver's unread count the gateway adds to every push (`unread_count`), for the app icon badge; `nil` when
  /// the push has none or it is not a count, so the badge stays as it is.
  public static func unreadCount(in userInfo: [AnyHashable: Any]) -> Int? {
    guard let count = (userInfo["unread_count"] as? NSNumber)?.intValue, count >= 0 else {
      return nil
    }
    return count
  }
}
