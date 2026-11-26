import Foundation

public struct CallRing: Sendable, Equatable {
  public static let maximumRingTime: TimeInterval = 90

  enum Key {
    static let roomId = "room_id"
    static let eventId = "rtc_notification_event_id"
    static let roomName = "room_name"
    static let isVoice = "is_voice"
    static let expiresAt = "expires_at"
    static let accountUserId = "user_id"
  }

  public let roomId: String
  public let eventId: String
  public let roomName: String
  public let isVoice: Bool
  public let expiresAt: Date
  public let accountUserId: String?

  public init(
    roomId: String, eventId: String, roomName: String, isVoice: Bool, expiresAt: Date,
    accountUserId: String? = nil
  ) {
    self.roomId = roomId
    self.eventId = eventId
    self.roomName = roomName
    self.isVoice = isVoice
    self.expiresAt = expiresAt
    self.accountUserId = accountUserId
  }

  public func isRinging(at now: Date = Date()) -> Bool {
    now < expiresAt && expiresAt.timeIntervalSince(now) <= Self.maximumRingTime
  }

  public func with(accountUserId: String?) -> CallRing {
    CallRing(
      roomId: roomId, eventId: eventId, roomName: roomName, isVoice: isVoice,
      expiresAt: expiresAt, accountUserId: accountUserId)
  }

  public var payload: [String: Any] {
    var payload: [String: Any] = [
      Key.roomId: roomId, Key.eventId: eventId, Key.roomName: roomName, Key.isVoice: isVoice,
      Key.expiresAt: expiresAt.timeIntervalSince1970,
    ]
    if let accountUserId { payload[Key.accountUserId] = accountUserId }
    return payload
  }

  public init?(payload: [AnyHashable: Any]) {
    guard let roomId = payload[Key.roomId] as? String, !roomId.isEmpty,
      let eventId = payload[Key.eventId] as? String, !eventId.isEmpty,
      let expiresAt = (payload[Key.expiresAt] as? NSNumber)?.doubleValue
    else { return nil }
    self.init(
      roomId: roomId, eventId: eventId, roomName: payload[Key.roomName] as? String ?? "",
      isVoice: (payload[Key.isVoice] as? NSNumber)?.boolValue ?? false,
      expiresAt: Date(timeIntervalSince1970: expiresAt),
      accountUserId: (payload[Key.accountUserId] as? String).flatMap { $0.isEmpty ? nil : $0 })
  }
}

public enum CallRingPayload {
  public static let userInfoKey = "call_ring"
}
