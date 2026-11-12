import AppShared
import Domain
import Foundation
import MatrixRustSDK

/// Maps the SDK `Session` to the Domain `UserSession` and to the Keychain record, and SDK errors to
/// `AuthenticationError`. Internal: no SDK type or SDK error leaves MatrixData (ADR 0006).
enum UserSessionMapper {
  /// The names under which `StoredSession.slidingSyncVersion` keeps the SDK's `SlidingSyncVersion`.
  static let slidingSyncNative = "native"
  static let slidingSyncNone = "none"

  static func userSession(from session: Session) throws(AuthenticationError) -> UserSession {
    UserSession(
      userId: session.userId, deviceId: session.deviceId,
      homeserverURL: try homeserverURL(session.homeserverUrl),
      accessToken: session.accessToken, refreshToken: session.refreshToken)
  }

  static func userSession(from stored: StoredSession) -> UserSession {
    UserSession(
      userId: stored.userId, deviceId: stored.deviceId, homeserverURL: stored.homeserverURL,
      accessToken: stored.accessToken, refreshToken: stored.refreshToken)
  }

  static func storedSession(from session: Session) throws(AuthenticationError) -> StoredSession {
    StoredSession(
      userId: session.userId, deviceId: session.deviceId,
      homeserverURL: try homeserverURL(session.homeserverUrl),
      accessToken: session.accessToken, refreshToken: session.refreshToken,
      slidingSyncVersion: slidingSyncName(session.slidingSyncVersion))
  }

  /// The SDK session to restore. Only password login exists, so there is no OIDC data.
  static func sdkSession(from stored: StoredSession) -> Session {
    Session(
      accessToken: stored.accessToken, refreshToken: stored.refreshToken, userId: stored.userId,
      deviceId: stored.deviceId, homeserverUrl: stored.homeserverURL.absoluteString, oidcData: nil,
      slidingSyncVersion: stored.slidingSyncVersion == slidingSyncNative ? .native : .none)
  }

  static func slidingSyncName(_ version: SlidingSyncVersion) -> String {
    switch version {
    case .native: slidingSyncNative
    case .none: slidingSyncNone
    }
  }

  private static func homeserverURL(_ string: String) throws(AuthenticationError) -> URL {
    guard let url = URL(string: string), url.scheme != nil, url.host() != nil else {
      throw .invalidHomeserverURL
    }
    return url
  }

  /// Any error from the SDK, or an `AuthenticationError` already mapped, as an `AuthenticationError`.
  static func authenticationError(from error: any Error) -> AuthenticationError {
    switch error {
    case let error as AuthenticationError: error
    case let error as ClientError: authenticationError(from: error)
    case let error as ClientBuildError: authenticationError(from: error)
    default: .unknown
    }
  }

  static func authenticationError(from error: ClientError) -> AuthenticationError {
    switch error {
    case .MatrixApi(kind: .forbidden, _, _, _): .invalidCredentials
    case .MatrixApi(kind: .connectionFailed, _, _, _),
      .MatrixApi(kind: .connectionTimeout, _, _, _):
      .serverUnreachable
    case .MatrixApi, .Generic: .unknown
    }
  }

  static func authenticationError(from error: ClientBuildError) -> AuthenticationError {
    switch error {
    case .InvalidServerName, .WellKnownLookupFailed, .WellKnownDeserializationError:
      .invalidHomeserverURL
    case .ServerUnreachable: .serverUnreachable
    case .SlidingSync, .SlidingSyncVersion, .Sdk, .EventCache, .Generic: .unknown
    }
  }
}
