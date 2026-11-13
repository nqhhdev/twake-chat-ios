import Foundation

/// One signed-in session of the account, as the devices list shows it.
public struct DeviceSession: Sendable, Equatable, Identifiable {
  public let id: String
  public let displayName: String?
  public let lastSeen: Date?
  /// This app's own session.
  public let isCurrent: Bool

  public init(id: String, displayName: String?, lastSeen: Date?, isCurrent: Bool) {
    self.id = id
    self.displayName = displayName
    self.lastSeen = lastSeen
    self.isCurrent = isCurrent
  }

  /// The name shown, or the device id when the session has none.
  public var name: String { displayName.flatMap { $0.isEmpty ? nil : $0 } ?? id }
}

public enum DevicesError: Error, Sendable, Equatable {
  case notSignedIn
  case requestFailed
}

/// The account's sessions. Implemented in MatrixData; no SDK type appears here (ADR 0006).
public protocol DevicesRepository: Sendable {
  /// This session first, then the others, most recently seen first.
  func devices() async throws(DevicesError) -> [DeviceSession]
  /// Renames a session, as other people and devices see it.
  func rename(deviceId: String, to name: String) async throws(DevicesError)
}
