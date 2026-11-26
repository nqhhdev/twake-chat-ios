import Foundation

public struct RoomCallState: Sendable, Equatable {
  public let isActive: Bool
  public let participants: [String]

  public init(isActive: Bool, participants: [String]) {
    self.isActive = isActive
    self.participants = participants
  }

  public static let idle = RoomCallState(isActive: false, participants: [])

  public func includes(_ userId: String) -> Bool { participants.contains(userId) }
}

public enum CallIntent: Sendable, Equatable {
  case start
  case join
}

public enum RoomCallError: Error, Sendable, Equatable {
  case unavailable
  case notJoined
  case notAllowed
  case failed
}

public protocol CallWidgetSession: Sendable {
  var url: URL { get }
  var userId: String { get }
  func messagesToWidget() async -> AsyncStream<String>
  func receiveFromWidget(_ message: String) async
  func end() async
}

public protocol RoomCallRepository: Sendable {
  func isAvailable() async -> Bool
  func decline(roomId: String, notificationEventId: String) async
  func callStates(roomId: String) async -> AsyncStream<RoomCallState>
  func open(roomId: String, intent: CallIntent) async throws(RoomCallError)
    -> any CallWidgetSession
}

extension RoomCallRepository {
  public func decline(roomId: String, notificationEventId: String) async {}
}
