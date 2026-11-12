import Foundation

/// A signed-in Matrix session. The tokens are secrets: they are kept in the Keychain only (ADR 0007),
/// and `description` and `debugDescription` leave them out so that printing a session never shows one.
public struct UserSession: Sendable, Equatable {
  public let userId: String
  public let deviceId: String
  public let homeserverURL: URL
  public let accessToken: String
  public let refreshToken: String?

  public init(
    userId: String, deviceId: String, homeserverURL: URL, accessToken: String, refreshToken: String?
  ) {
    self.userId = userId
    self.deviceId = deviceId
    self.homeserverURL = homeserverURL
    self.accessToken = accessToken
    self.refreshToken = refreshToken
  }
}

extension UserSession: CustomStringConvertible, CustomDebugStringConvertible {
  public var description: String {
    "UserSession(userId: \(userId), deviceId: \(deviceId), homeserverURL: \(homeserverURL.absoluteString), tokens: <redacted>)"
  }

  public var debugDescription: String { description }
}
