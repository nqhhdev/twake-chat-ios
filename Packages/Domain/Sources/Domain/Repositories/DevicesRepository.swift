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
  /// Signs sessions out (`POST /delete_devices`). The server usually asks the user to confirm first (User-Interactive
  /// Authentication): the first call then returns the challenge, and a second call with `auth` finishes.
  func signOut(deviceIds: [String], auth: DeviceAuth?) async throws(DevicesError) -> DeviceSignOut
}

extension DevicesRepository {
  public func signOut(deviceIds: [String], auth: DeviceAuth?) async throws(DevicesError)
    -> DeviceSignOut
  {
    throw .requestFailed
  }
}

/// What signing sessions out needs from the user, from the server's User-Interactive Authentication answer.
public struct DeviceAuthChallenge: Sendable, Equatable {
  /// The server's id of this confirmation, sent back with the answer.
  public let session: String
  /// The page where the user confirms with their single sign-on, when the server offers it.
  public let webURL: URL?
  /// The server accepts the account password.
  public let acceptsPassword: Bool

  public init(session: String, webURL: URL?, acceptsPassword: Bool) {
    self.session = session
    self.webURL = webURL
    self.acceptsPassword = acceptsPassword
  }
}

/// The user's confirmation for a challenge.
public enum DeviceAuth: Sendable, Equatable {
  /// The user confirmed on the single sign-on page.
  case confirmedOnWeb(session: String)
  /// The user typed their password.
  case password(String, session: String)
}

public enum DeviceSignOut: Sendable, Equatable {
  case done
  case needsConfirmation(DeviceAuthChallenge)
}
