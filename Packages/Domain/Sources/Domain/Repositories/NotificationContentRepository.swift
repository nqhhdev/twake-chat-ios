import Foundation

public struct NotificationContent: Sendable, Equatable {
  public let title: String
  public let subtitle: String
  public let body: String
  public let senderId: String
  public let senderName: String
  public let roomName: String
  public let isDirect: Bool
  public let threadId: String?
  public let isMessage: Bool
  public var senderAvatar: Data?
  public var roomAvatar: Data?
  public let ring: CallRing?

  public init(
    title: String, subtitle: String, body: String, senderId: String = "", senderName: String = "",
    roomName: String = "", isDirect: Bool = false, threadId: String? = nil, isMessage: Bool = false,
    senderAvatar: Data? = nil, roomAvatar: Data? = nil, ring: CallRing? = nil
  ) {
    self.title = title
    self.subtitle = subtitle
    self.body = body
    self.senderId = senderId
    self.senderName = senderName
    self.roomName = roomName
    self.isDirect = isDirect
    self.threadId = threadId
    self.isMessage = isMessage
    self.senderAvatar = senderAvatar
    self.roomAvatar = roomAvatar
    self.ring = ring
  }
}

public enum NotificationOutcome: Sendable, Equatable {
  case show(NotificationContent)
  case hide
  case generic
}

public protocol NotificationContentRepository: Sendable {
  func content(roomId: String, eventId: String) async -> NotificationOutcome
}
