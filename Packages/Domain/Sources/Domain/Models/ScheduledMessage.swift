import Foundation

public struct ScheduledMessage: Sendable, Equatable, Identifiable {
  public let id: String
  public let text: String
  public let sendAt: Date
  public let replyTo: String?

  public init(id: String, text: String, sendAt: Date, replyTo: String? = nil) {
    self.id = id
    self.text = text
    self.sendAt = sendAt
    self.replyTo = replyTo
  }
}

public enum ScheduleError: Error, Sendable, Equatable {
  case unsupported
  case encryptedRoom
  case delayTooLong(maxDelay: TimeInterval?)
  case tooMany
  case failed
}
